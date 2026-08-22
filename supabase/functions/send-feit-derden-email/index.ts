// Supabase Edge Function: verwittigt de vertrouwenspersoon zodra er vanaf de
// gsm een verklaring in het register van feiten van derden valt. Wordt intern
// aangeroepen vanuit de trigger op die tabel (migratie 0106) via pg_net, niet
// rechtstreeks vanaf het internet -- vandaar dezelfde controle op de gedeelde
// sleutel uit Vault als bij de andere interne functies, en JWT-verificatie van
// de gateway uit.
//
// ---------------------------------------------------------------------------
// DEZE FUNCTIE KENT DE INHOUD NIET
// ---------------------------------------------------------------------------
// Ze krijgt alleen een bedrijf-id binnen. Geen id van de verklaring, dus er is
// niets om op te zoeken -- ook niet per ongeluk, en ook niet wanneer iemand
// haar later uitbreidt. Dat is met opzet zo gebouwd: de tekst van een verklaring
// hoort in het register te blijven en nergens anders langs te komen.
//
// De mail zelf zegt daarom niets over wat er gemeld is. Niet uit
// voorzichtigheidsdrang: een mailbox is een andere plaats dan een afgeschermd
// scherm. Mail wordt doorgestuurd, staat te lezen op een vergrendeld scherm, en
// bij een zaakvoerder kijkt er soms iemand mee.
//
// Naar PrevX gaat er niets, ook geen kopie.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const AFZENDER = Deno.env.get('AFZENDER_EMAIL') || 'rapporten@prevx.be';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-webhook-secret'
};

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

function veilig(t) {
  return String(t == null ? '' : t)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  if (!(await isGeautoriseerd(req, sb))) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const { bedrijf_id } = await req.json();
  if (!bedrijf_id) {
    return new Response(JSON.stringify({ error: 'bedrijf_id ontbreekt' }), { status: 400, headers: CORS_HEADERS });
  }

  const { data: doel, error } = await sb.rpc('rpc_ontvangers_feiten_derden', { p_bedrijf_id: bedrijf_id });
  if (error || !doel) {
    console.error('Kon de ontvangers niet bepalen:', error);
    return new Response(JSON.stringify({ error: 'Ontvangers onbekend' }), { status: 500, headers: CORS_HEADERS });
  }

  const adressen = doel.adressen || [];
  if (!adressen.length) {
    // Niemand om te verwittigen. Dat is zelf een probleem -- er staat nu een
    // verklaring te wachten waar niemand van weet -- maar het is er geen dat
    // wij oplossen door de inhoud naar een ander adres te sturen. We loggen het
    // en geven 200 terug: de melding zelf is wel degelijk opgeslagen, en de
    // trigger hoeft niet te blijven proberen.
    console.warn('Geen ontvanger met e-mailadres voor bedrijf', bedrijf_id,
                 '- verklaring staat in het register maar niemand kreeg bericht');
    return new Response(JSON.stringify({ ok: true, verzonden: 0 }), {
      status: 200, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
    });
  }

  const geenVp = doel.vertrouwenspersoon_aangewezen === false;

  // Sober en zonder inhoud. Wat hier staat mag iedereen lezen die toevallig
  // over een schouder meekijkt.
  const html = `
    <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#0f1826;line-height:1.6">
      <p style="margin:0 0 14px">Er is een nieuwe verklaring opgenomen in het
        <strong>register van feiten van derden</strong> van ${veilig(doel.bedrijf)}.</p>
      <p style="margin:0 0 14px">Ze is gemeld vanaf de werkvloer. Wie ze verstuurd heeft,
        is niet gekend, tenzij de melder zijn naam zelf heeft meegegeven.</p>
      <p style="margin:0 0 18px;color:#64748b">In dit bericht staat met opzet niet wat er gemeld is.
        U leest de verklaring in het portaal, waar ze alleen zichtbaar is voor wie er volgens
        artikel I.3-3 van de codex bij mag.</p>
      ${geenVp ? `
      <p style="margin:0 0 18px;padding:12px 16px;background:#fff7ed;border-left:3px solid #ea580c;color:#9a3412">
        U krijgt dit bericht omdat er in uw bedrijf geen vertrouwenspersoon aangewezen is.
        Zolang dat zo blijft, komen deze meldingen bij u als werkgever terecht. Overweeg iemand aan te
        wijzen: voor een werknemer is de drempel om iets te vertellen lager bij iemand die niet zijn baas is.
      </p>` : ''}
      <a href="https://prevx.be/account" style="display:inline-block;background:#003366;color:#fff;text-decoration:none;padding:10px 18px;border-radius:8px">Openen in Mijn PrevX</a>
      <p style="margin:18px 0 0;color:#94a3b8;font-size:12px">Dit bericht is vertrouwelijk en voor u persoonlijk bestemd.</p>
    </div>`;

  // Eén mail per ontvanger, niet één mail met iedereen in het veld To. Wie
  // vertrouwenspersoon is, hoeft niet uit een adresregel af te leiden wie dat
  // nog meer is.
  let verzonden = 0;
  for (const adres of adressen) {
    const resp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: AFZENDER,
        to: [adres],
        subject: 'Nieuwe melding in uw register van feiten van derden',
        html
      })
    });
    if (resp.ok) verzonden++;
    else console.error('Resend weigerde de mail:', resp.status, await resp.text());
  }

  return new Response(JSON.stringify({ ok: true, verzonden }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
