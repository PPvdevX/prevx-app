// Supabase Edge Function: stuurt een eenmalige code naar de goedkeurder van een
// vuurvergunning. Aangeroepen vanuit rpc_goedkeuring_code_aanvragen via pg_net,
// niet vanaf het internet -- vandaar de gedeelde sleutel i.p.v. JWT-verificatie
// (die staat voor deze functie uit, zelfde patroon als de andere twee).
//
// De sleutel komt uit Vault, niet uit een functie-geheim: zo staat hij op één
// plek en kan er niets uit elkaar lopen (zie migratie 0056).

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const AFZENDER = Deno.env.get('AFZENDER_EMAIL') || 'rapporten@prevx.be';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

// Faalt de opvraging, dan weigeren we -- fail closed: liever geen mail dan een
// functie die openstaat voor het internet.
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

Deno.serve(async (req) => {
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('send-goedkeuring-code-email crashte:', e && e.stack ? e.stack : e);
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

  const { gebruiker_id, vergunning_id, code } = await req.json();
  if (!gebruiker_id || !vergunning_id || !code) {
    return new Response(JSON.stringify({ error: 'gebruiker_id, vergunning_id of code ontbreekt' }), { status: 400 });
  }

  const { data: gebruiker, error: gErr } = await sb
    .from('gebruikers')
    .select('naam,email')
    .eq('id', gebruiker_id)
    .single();
  if (gErr || !gebruiker || !gebruiker.email) {
    return new Response(JSON.stringify({ error: 'Gebruiker niet gevonden of geen e-mailadres' }), { status: 404 });
  }

  const { data: verg } = await sb
    .from('vuurvergunningen')
    .select('vergunningsnummer,locatie_omschrijving,geldig_van,geldig_tot,werktypes(naam),gebruikers!vuurvergunningen_aanvrager_id_fkey(naam)')
    .eq('id', vergunning_id)
    .single();

  const werktype = verg && verg.werktypes ? verg.werktypes.naam : '';
  const aanvrager = verg && verg.gebruikers ? verg.gebruikers.naam : '';
  const nummer = verg ? verg.vergunningsnummer : '';
  const locatie = verg ? verg.locatie_omschrijving : '';

  const html = `
  <div style="font-family:sans-serif;max-width:520px;margin:0 auto">
    <div style="background:#003366;padding:18px 24px"><span style="color:#fff;font-weight:800;font-size:16px;letter-spacing:0.5px">VUURVERGUNNING GOEDKEUREN</span></div>
    <div style="padding:20px 24px;color:#334155;font-size:14px">
      <p>Hallo ${gebruiker.naam},</p>
      <p>Er wacht een vuurvergunning op uw beslissing. Gebruik onderstaande code (geldig 15 minuten) om te ondertekenen in de PrevX app:</p>
      <div style="font-family:monospace;font-size:28px;font-weight:800;letter-spacing:4px;background:#f1f5f9;padding:14px 20px;border-radius:8px;text-align:center;margin:16px 0">${code}</div>
      <table style="width:100%;font-size:13px;color:#334155;margin-top:8px">
        <tr><td style="padding:4px 0;color:#94a3b8">Nummer</td><td style="padding:4px 0;font-weight:700">${nummer}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Werk</td><td style="padding:4px 0">${werktype}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Werkplek</td><td style="padding:4px 0">${locatie}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Aangevraagd door</td><td style="padding:4px 0">${aanvrager}</td></tr>
      </table>
      <p style="font-size:12px;color:#94a3b8;margin-top:18px">Vroeg u dit niet zelf aan? Geef deze code dan aan niemand door en verwittig uw preventieadviseur. Met deze code wordt er in uw naam getekend.</p>
    </div>
  </div>`;

  const emailResp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: AFZENDER,
      to: [gebruiker.email],
      subject: `Code om vuurvergunning ${nummer} goed te keuren`,
      html
    })
  });

  const ruw = await emailResp.text();
  let body;
  try { body = JSON.parse(ruw); } catch (e) { body = { ruw }; }
  if (!emailResp.ok) {
    console.error('Resend gaf een foutstatus terug:', emailResp.status, ruw);
  }
  return new Response(JSON.stringify({ ok: emailResp.ok, resend: body }), {
    status: emailResp.ok ? 200 : 502
  });
}
