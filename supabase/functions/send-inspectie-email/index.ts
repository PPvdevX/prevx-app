// Supabase Edge Function: stuurt een e-mail naar de leidinggevenden van een
// bedrijf zodra een inspectierapport wordt verzonden. Wordt intern aangeroepen
// vanuit rpc_verzend_inspectie (via pg_net), niet rechtstreeks vanaf het internet
// — vandaar de check op een gedeelde sleutel i.p.v. gewone JWT-verificatie (die
// staat voor deze functie uit, zie deploy-instructies).
//
// Die sleutel komt sinds migratie 0056 uit Vault, niet meer uit een
// functie-geheim: anders moest dezelfde waarde op twee plaatsen staan en viel
// alle mail stil zodra die uit elkaar liepen.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const AFZENDER = Deno.env.get('AFZENDER_EMAIL') || 'rapporten@prevx.be';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const VERDICT_LABELS = {
  rijklaar: 'RIJKLAAR',
  niet_rijklaar: 'NIET RIJKLAAR',
  onvolledig: 'ONVOLLEDIG',
  rijklaar_met_opmerkingen: 'RIJKLAAR MET OPMERKINGEN'
};
const VERDICT_KLEUR = {
  rijklaar: '#3FBF3F',
  niet_rijklaar: '#dc2626',
  onvolledig: '#64748b',
  rijklaar_met_opmerkingen: '#E97F02'
};

// Haalt de verwachte sleutel uit Vault en vergelijkt met wat de aanroeper
// meestuurde. Faalt de opvraging, dan weigeren we -- fail closed: liever geen
// mail dan een functie die openstaat voor het internet.
async function isGeautoriseerd(req, sb) {
  const meegestuurd = req.headers.get('x-webhook-secret');
  if (!meegestuurd) return false;

  const { data: verwacht, error } = await sb.rpc('rpc_webhook_secret');
  if (error || !verwacht) {
    console.error('Kon de webhook-sleutel niet uit Vault lezen:', error);
    return false;
  }
  return meegestuurd === verwacht;
}

// Sinds migratie 0070 is de bucket inspectie-media privé, dus de opgeslagen URL
// werkt niet meer rechtstreeks in een mail. Hier wordt er een tijdelijke link
// van gemaakt.
//
// Waarom een link en geen ingesloten afbeelding: een data:-URI in een <img>
// wordt door Gmail en Outlook weggefilterd, dan ziet de ontvanger niets. Een
// ondertekende link rendert overal.
//
// Waarom dertig dagen: de mail is een bericht, niet het archief. Het dossier
// staat in het portaal en blijft daar. Een handtekening die eeuwig openbaar
// blijft omdat iemand ooit een mail doorstuurde, is precies wat we met 0070
// wilden wegnemen -- dat mag er niet via de mail weer insluipen.
async function tijdelijkeLink(sb, url) {
  if (!url) return null;
  const m = /\/storage\/v1\/object\/(?:public\/|sign\/)?([^\/?]+)\/([^?]+)/.exec(url);
  if (!m || m[1] !== 'inspectie-media') return url;
  const { data, error } = await sb.storage.from(m[1])
    .createSignedUrl(decodeURIComponent(m[2]), 60 * 60 * 24 * 30);
  if (error || !data) {
    console.error('Ondertekende link voor de handtekening mislukt:', error);
    return null;
  }
  return data.signedUrl;
}

Deno.serve(async (req) => {
  // Zonder try/catch verdween elke fout hier vroeger spoorloos (crash zonder
  // enige console.error-regel in de logs, enkel een generieke
  // EDGE_FUNCTION_ERROR/EarlyDrop zichtbaar in het dashboard).
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('send-inspectie-email crashte:', e && e.stack ? e.stack : e);
    return new Response(JSON.stringify({ error: String((e && e.message) || e) }), { status: 500 });
  }
});

async function verwerk(req) {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  if (!(await isGeautoriseerd(req, sb))) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  if (!RESEND_API_KEY) {
    console.error('RESEND_API_KEY ontbreekt als functie-secret.');
    return new Response(JSON.stringify({ error: 'RESEND_API_KEY niet ingesteld' }), { status: 500 });
  }

  const { inspectie_id } = await req.json();
  if (!inspectie_id) {
    return new Response(JSON.stringify({ error: 'inspectie_id ontbreekt' }), { status: 400 });
  }

  const { data: ins, error: insErr } = await sb
    .from('inspecties')
    .select('*, voertuigen(nummerplaat,omschrijving,notificatie_emails,voertuig_types(naam)), gebruikers(naam), bedrijven(naam,afzender_email)')
    .eq('id', inspectie_id)
    .single();
  if (insErr || !ins) {
    return new Response(JSON.stringify({ error: 'Inspectie niet gevonden', details: insErr }), { status: 404 });
  }

  const { data: resultaten } = await sb
    .from('inspectie_resultaten')
    .select('*, inspectie_punten(omschrijving,volgorde,niveau,inspectie_secties(naam,icon,volgorde))')
    .eq('inspectie_id', inspectie_id);

  const { data: leidinggevenden } = await sb
    .from('gebruikers')
    .select('email')
    .eq('bedrijf_id', ins.bedrijf_id)
    .eq('rol', 'leidinggevende')
    .eq('actief', true)
    .not('email', 'is', null);

  // Naast de vaste leidinggevenden-lijst kan dit specifieke bedrijfsmiddel
  // ook eigen (eventueel externe) ontvangers hebben, komma-gescheiden.
  const voertuigEmails = ((ins.voertuigen && ins.voertuigen.notificatie_emails) || '')
    .split(',')
    .map((e) => e.trim())
    .filter(Boolean);

  const ontvangers = Array.from(
    new Set([...(leidinggevenden || []).map((g) => g.email).filter(Boolean), ...voertuigEmails])
  );
  if (!ontvangers.length) {
    return new Response(JSON.stringify({ skipped: 'Geen leidinggevenden of bedrijfsmiddel-e-mailadressen voor dit bedrijf' }), { status: 200 });
  }

  const secties = {};
  (resultaten || []).forEach((r) => {
    const p = r.inspectie_punten;
    if (!p || !p.inspectie_secties) return;
    const s = p.inspectie_secties;
    if (!secties[s.naam]) secties[s.naam] = { icon: s.icon, volgorde: s.volgorde, punten: [] };
    secties[s.naam].punten.push({ ...r, punt: p });
  });
  const sectieArr = Object.values(secties).sort((a, b) => a.volgorde - b.volgorde);

  const badge = { ok: ['JA', '#3FBF3F'], nok: ['NEE', '#dc2626'], na: ['NVT', '#64748b'], open: ['-', '#94a3b8'] };
  let secBlokken = '';
  sectieArr.forEach((s) => {
    s.punten.sort((a, b) => (a.punt.volgorde || 0) - (b.punt.volgorde || 0));
    let rijen = '';
    s.punten.forEach((r) => {
      const st = r.status || 'open';
      const [label, kleur] = badge[st] || badge.open;
      rijen += `<tr>
        <td style="padding:6px 10px;font-size:12px;font-weight:700;color:#fff;background:${kleur};border-radius:4px;text-align:center;white-space:nowrap">${label}</td>
        <td style="padding:6px 10px;font-size:13px;color:#334155">${r.punt.omschrijving}${r.punt.niveau === 'informatief' ? ' <span style="font-size:10px;color:#E97F02">(informatief)</span>' : ''}${r.opmerking ? `<div style="font-size:11px;color:#64748b;font-style:italic">${r.opmerking}</div>` : ''}</td>
      </tr>`;
    });
    secBlokken += `<div style="margin-bottom:14px">
      <div style="background:#003366;color:#fff;padding:8px 12px;font-size:12px;font-weight:700;text-transform:uppercase;border-radius:6px 6px 0 0">${s.icon || ''} ${Object.keys(secties).find((k) => secties[k] === s)}</div>
      <table style="width:100%;border-collapse:collapse;border:1px solid #e2e8f0;border-top:none">${rijen}</table>
    </div>`;
  });

  const type = ins.voertuigen && ins.voertuigen.voertuig_types ? ins.voertuigen.voertuig_types.naam : '';
  const handtekeningLink = await tijdelijkeLink(sb, ins.handtekening);

  const html = `
  <div style="font-family:sans-serif;max-width:640px;margin:0 auto">
    <div style="background:#003366;padding:18px 24px"><span style="color:#fff;font-weight:800;font-size:16px;letter-spacing:0.5px">PRE-INSPECTIE RAPPORT</span></div>
    <div style="padding:20px 24px">
      <div style="display:inline-block;padding:10px 16px;border-radius:8px;background:${VERDICT_KLEUR[ins.verdict] || '#64748b'}22;color:${VERDICT_KLEUR[ins.verdict] || '#64748b'};font-weight:800;margin-bottom:16px">${VERDICT_LABELS[ins.verdict] || ins.verdict}</div>
      <table style="width:100%;margin-bottom:20px;font-size:13px;color:#334155">
        <tr><td style="padding:4px 0;color:#94a3b8">Bedrijfsmiddel</td><td style="padding:4px 0;font-weight:700">${ins.voertuigen ? ins.voertuigen.nummerplaat : '-'} (${type})</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Chauffeur</td><td style="padding:4px 0">${ins.gebruikers ? ins.gebruikers.naam : '-'}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Datum</td><td style="padding:4px 0">${ins.datum} ${ins.tijdstip ? ins.tijdstip.slice(0, 5) : ''}</td></tr>
      </table>
      ${secBlokken}
      ${handtekeningLink ? `<div style="margin-top:16px"><div style="font-size:11px;color:#94a3b8;text-transform:uppercase;margin-bottom:6px">Handtekening uitvoerder</div><img src="${handtekeningLink}" style="max-width:280px;border:1px solid #e2e8f0;border-radius:6px"></div>` : ''}
    </div>
  </div>`;

  const emailResp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: (ins.bedrijven && ins.bedrijven.afzender_email) || AFZENDER,
      to: ontvangers,
      subject: `Inspectierapport ${ins.voertuigen ? ins.voertuigen.nummerplaat : ''} — ${VERDICT_LABELS[ins.verdict] || ins.verdict}`,
      html
    })
  });

  // Defensief parsen: als Resend om welke reden dan ook geen geldige JSON
  // teruggeeft (bv. bij een netwerk-/authenticatieprobleem), crashte de
  // functie hier vroeger hard op een simpele .json()-aanroep.
  const emailRuw = await emailResp.text();
  let emailBody;
  try { emailBody = JSON.parse(emailRuw); } catch (e) { emailBody = { ruw: emailRuw }; }
  if (!emailResp.ok) {
    console.error('Resend gaf een foutstatus terug:', emailResp.status, emailRuw);
  }
  return new Response(JSON.stringify({ ok: emailResp.ok, resend: emailBody }), {
    status: emailResp.ok ? 200 : 502
  });
}
