// Supabase Edge Function: herinnert aan de nazorgcontrole na heet werk.
// Aangeroepen vanuit verwerk_nazorg_herinneringen() via pg_cron + pg_net.
//
// Twee soorten bericht:
//   escalatie = false -> naar de brandwacht: "tijd voor je controle"
//   escalatie = true  -> naar de verantwoordelijke: "die controle is uitgebleven"
//
// Sinds migratie 0065 gaat er naast de e-mail ook een pushmelding naar elk
// toestel dat de ontvanger geregistreerd heeft. Push is een TOEVOEGING, geen
// vervanging: op een werf kijkt niemand in zijn mailbox, maar een toestel kan
// uitstaan, geen batterij hebben of de melding geweigerd hebben. De e-mail
// blijft dus onvoorwaardelijk vertrekken. Planning en escalatielogica (0060)
// zijn ongewijzigd.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const AFZENDER = Deno.env.get('AFZENDER_EMAIL') || 'rapporten@prevx.be';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

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

// Stuurt de melding naar elk geregistreerd toestel van deze ontvangers.
// Faalt bewust nooit hard: een kapot abonnement mag de e-mail niet meeslepen.
async function stuurPush(sb, gebruikerIds, kop, tekst, vergunningId) {
  if (!gebruikerIds.length) return { verstuurd: 0, opgeruimd: 0 };

  const { data: cfg } = await sb.rpc('rpc_vapid_config');
  const vapid = Array.isArray(cfg) ? cfg[0] : cfg;
  if (!vapid || !vapid.prive_sleutel || !vapid.publieke_sleutel) {
    console.error('VAPID-sleutels ontbreken in Vault; push overgeslagen.');
    return { verstuurd: 0, opgeruimd: 0 };
  }
  webpush.setVapidDetails(vapid.onderwerp, vapid.publieke_sleutel, vapid.prive_sleutel);

  const { data: abos } = await sb
    .from('push_abonnementen')
    .select('id,endpoint,p256dh,auth')
    .in('gebruiker_id', gebruikerIds);
  if (!abos || !abos.length) return { verstuurd: 0, opgeruimd: 0 };

  const lading = JSON.stringify({
    titel: kop,
    tekst,
    tag: 'nazorg-' + vergunningId,
    url: '/app'
  });

  let verstuurd = 0;
  let opgeruimd = 0;
  for (const a of abos) {
    try {
      await webpush.sendNotification(
        { endpoint: a.endpoint, keys: { p256dh: a.p256dh, auth: a.auth } },
        lading
      );
      verstuurd++;
      await sb.from('push_abonnementen').update({ laatst_gelukt_op: new Date().toISOString(), laatste_fout: null }).eq('id', a.id);
    } catch (e) {
      const status = e && e.statusCode;
      // 404/410 = de pushdienst kent dit endpoint niet meer: app verwijderd of
      // meldingen uitgezet. Zo'n rij opruimen, anders blijven we eeuwig naar
      // een dood toestel sturen.
      if (status === 404 || status === 410) {
        await sb.from('push_abonnementen').delete().eq('id', a.id);
        opgeruimd++;
      } else {
        console.error('Push mislukt voor abonnement', a.id, status, e && e.body ? e.body : String(e));
        await sb.from('push_abonnementen').update({ laatste_fout: String(status || (e && e.message) || e).slice(0, 300) }).eq('id', a.id);
      }
    }
  }
  return { verstuurd, opgeruimd };
}

Deno.serve(async (req) => {
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('send-nazorg-herinnering crashte:', e && e.stack ? e.stack : e);
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

  const { vergunning_id, type, ontvanger_id, escalatie } = await req.json();
  if (!vergunning_id || !type) {
    return new Response(JSON.stringify({ error: 'vergunning_id of type ontbreekt' }), { status: 400 });
  }

  const { data: verg } = await sb
    .from('vuurvergunningen')
    .select('vergunningsnummer,locatie_omschrijving,werk_beeindigd_op,bedrijf_id,werktype_id')
    .eq('id', vergunning_id)
    .single();
  if (!verg) {
    return new Response(JSON.stringify({ error: 'Vergunning niet gevonden' }), { status: 404 });
  }

  const { data: werktype } = await sb
    .from('werktypes').select('naam').eq('id', verg.werktype_id).single();

  // Bij escalatie gaat het bericht naar wie mag beslissen, niet naar de
  // brandwacht die al niet reageerde.
  let ontvangers = [];
  if (escalatie) {
    const { data: leiding } = await sb
      .from('gebruikers')
      .select('id,naam,email')
      .eq('bedrijf_id', verg.bedrijf_id)
      .in('rol', ['leidinggevende', 'preventieadviseur', 'beheerder'])
      .eq('actief', true)
      .not('email', 'is', null);
    ontvangers = leiding || [];
  } else if (ontvanger_id) {
    const { data: g } = await sb
      .from('gebruikers').select('id,naam,email').eq('id', ontvanger_id).single();
    if (g) ontvangers = [g];
  }

  if (!ontvangers.length) {
    console.error('Geen ontvanger voor vergunning', verg.vergunningsnummer, 'type', type);
    return new Response(JSON.stringify({ skipped: 'geen ontvanger' }), { status: 200 });
  }

  // Adressen apart houden: een ontvanger zonder e-mailadres kan nog altijd een
  // pushabonnement hebben, en omgekeerd.
  const mailOntvangers = ontvangers.filter((g) => g.email);

  const uren = type === 'controle_2u' ? '2 uur' : '24 uur';
  const beeindigd = verg.werk_beeindigd_op
    ? new Date(verg.werk_beeindigd_op).toLocaleString('nl-BE', { timeZone: 'Europe/Brussels' })
    : '';

  const kop = escalatie ? 'NAZORGCONTROLE UITGEBLEVEN' : 'NAZORGCONTROLE VEREIST';
  const kleur = escalatie ? '#dc2626' : '#E97F02';
  const boodschap = escalatie
    ? `De controle van ${uren} na het heet werk is nog niet bevestigd. Nagloeiend materiaal is een van de belangrijkste oorzaken van brand die pas uren later ontstaat — ga na of die controle effectief gebeurd is.`
    : `Het is tijd voor de controle van ${uren} na het heet werk. Ga de werkplek en de aangrenzende, verborgen en technische ruimten na, en bevestig daarna in de PrevX app.`;

  const html = `
  <div style="font-family:sans-serif;max-width:520px;margin:0 auto">
    <div style="background:${kleur};padding:18px 24px"><span style="color:#fff;font-weight:800;font-size:16px;letter-spacing:0.5px">${kop}</span></div>
    <div style="padding:20px 24px;color:#334155;font-size:14px">
      <p>${boodschap}</p>
      <table style="width:100%;font-size:13px;color:#334155;margin-top:12px">
        <tr><td style="padding:4px 0;color:#94a3b8">Vergunning</td><td style="padding:4px 0;font-weight:700">${verg.vergunningsnummer}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Werk</td><td style="padding:4px 0">${werktype ? werktype.naam : ''}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Werkplek</td><td style="padding:4px 0">${verg.locatie_omschrijving}</td></tr>
        <tr><td style="padding:4px 0;color:#94a3b8">Werk beëindigd</td><td style="padding:4px 0">${beeindigd}</td></tr>
      </table>
    </div>
  </div>`;

  // Push eerst: dat is het kanaal dat de brandwacht op de werf effectief ziet.
  // De hele oproep zit in een try -- een stukgelopen pushdienst mag er nooit
  // toe leiden dat ook de e-mail achterwege blijft.
  let push = { verstuurd: 0, opgeruimd: 0 };
  try {
    push = await stuurPush(
      sb,
      ontvangers.map((g) => g.id),
      escalatie ? 'Nazorgcontrole uitgebleven' : 'Nazorgcontrole vereist',
      // Bewust zonder werkplek: dit verschijnt op een vergrendeld scherm.
      `${verg.vergunningsnummer} — controle ${uren} na het heet werk. Open de app om te bevestigen.`,
      vergunning_id
    );
  } catch (e) {
    console.error('Push volledig mislukt, e-mail gaat gewoon door:', e && e.stack ? e.stack : e);
  }

  if (!mailOntvangers.length) {
    // Geen e-mailadres is geen fout van deze functie, maar het is wel precies
    // het gat waardoor een nazorgcontrole gemist wordt -- dus loggen, ook als
    // de pushmelding wel vertrok.
    console.error('Geen ontvanger met e-mailadres voor vergunning', verg.vergunningsnummer, 'type', type);
    return new Response(JSON.stringify({ ok: push.verstuurd > 0, push, email: 'geen ontvanger met e-mailadres' }), { status: 200 });
  }

  const emailResp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: AFZENDER,
      to: mailOntvangers.map((g) => g.email),
      subject: `${escalatie ? 'Uitgebleven' : 'Herinnering'}: nazorgcontrole ${uren} — ${verg.vergunningsnummer}`,
      html
    })
  });

  const ruw = await emailResp.text();
  let body;
  try { body = JSON.parse(ruw); } catch (e) { body = { ruw }; }
  if (!emailResp.ok) {
    console.error('Resend gaf een foutstatus terug:', emailResp.status, ruw);
  }
  return new Response(JSON.stringify({ ok: emailResp.ok, ontvangers: mailOntvangers.length, push, resend: body }), {
    status: emailResp.ok ? 200 : 502
  });
}
