// Supabase Edge Function: werkt de verzendwachtrij van een nieuwsbriefcampagne
// af. Deel 2 van de nieuwsbriefmodule; hoort bij migratie 0089.
//
// ---------------------------------------------------------------------------
// Anders dan de rest: deze functie WIL wel JWT-verificatie
// ---------------------------------------------------------------------------
// Alle andere functies hier staan op --no-verify-jwt, omdat ze door de databank
// of door een mailclient worden aangeroepen. Deze niet: ze wordt aangeroepen
// door een ingelogde superbeheerder vanuit het portaal. Dat is het enige geval
// waarin die schakelaar -- die bij elke herimplementatie terugspringt -- in ons
// voordeel werkt. Laat hem dus aan staan.
//
// De JWT alleen volstaat niet: elke ingelogde klant heeft er een. Daarom wordt
// daarnaast is_superbeheerder() gecontroleerd met de sleutel van de aanroeper
// zelf, niet met de service-rol.
//
// ---------------------------------------------------------------------------
// Waarom een wachtrij en niet gewoon een lus
// ---------------------------------------------------------------------------
// Resend neemt hoogstens 100 adressen per aanroep en knijpt op een paar
// aanroepen per seconde. Bij 2000 abonnees is dat een halve minuut werk -- lang
// genoeg om ergens halverwege stuk te gaan. De rijen in nieuwsbrief_verzendingen
// zijn de wachtrij: elke rij die vertrokken is, springt op 'verzonden'. Loopt de
// functie vast of valt ze stil op haar tijdslimiet, dan roep je haar gewoon
// opnieuw aan en pikt ze op waar ze gebleven was. Niemand krijgt dubbele post,
// want een rij die 'verzonden' is wordt nooit meer opgepikt.
//
// Deploy:
//   supabase functions deploy verzend-nieuwsbrief

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');

const AFZENDER = Deno.env.get('NIEUWSBRIEF_AFZENDER') || 'PrevX <nieuws@prevx.be>';
const ANTWOORD_AAN = Deno.env.get('NIEUWSBRIEF_ANTWOORD') || '';
const SITE_URL = Deno.env.get('SITE_URL') || 'https://prevx.be';
const LINK_BASIS = Deno.env.get('NIEUWSBRIEF_LINK_BASIS') || `${SUPABASE_URL}/functions/v1/nieuwsbrief`;

// Resend neemt er 100 per aanroep. Niet hoger zetten: dan weigert de hele
// batch en is er niets vertrokken.
const PER_BATCH = 100;

// Een paar aanroepen per seconde is de standaardlimiet. 600 ms geeft wat
// speling; loop je toch tegen een 429 aan, dan verhoog je dit.
const PAUZE_MS = 600;

// Supabase kapt een functie af rond 150 seconden. Op 100 stoppen we zelf, netjes
// en met een verslag, in plaats van halverwege een batch te worden afgebroken.
// De aanroeper ziet dan hoeveel er nog te gaan is en roept opnieuw aan.
const TIJDBUDGET_MS = 100_000;

const wacht = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// CORS
// ---------------------------------------------------------------------------
// Het portaal draait op prevx.be en deze functie op supabase.co, dus elke
// aanroep is cross-origin. De browser stuurt daarom eerst een OPTIONS-verzoek,
// en dat moet beantwoord worden met deze headers -- anders blokkeert hij het
// echte verzoek en ziet de aanroeper enkel "Failed to fetch", zonder dat er
// ooit een regel van deze functie draait.
//
// De poort laat OPTIONS wel door ondanks Verify JWT; een preflight draagt geen
// Authorization-header en hoeft die ook niet te dragen.
const TOEGELATEN_HERKOMST = ['https://prevx.be', 'https://www.prevx.be'];

function corsHeaders(req) {
  const herkomst = req.headers.get('origin') || '';
  return {
    'Access-Control-Allow-Origin': TOEGELATEN_HERKOMST.includes(herkomst) ? herkomst : TOEGELATEN_HERKOMST[0],
    'Access-Control-Allow-Headers': 'authorization, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
}

// ---------------------------------------------------------------------------
// De voettekst die onder elke nieuwsbrief komt
// ---------------------------------------------------------------------------
// Bewust hier en niet in de campagnetekst: een nieuwsbrief zonder werkende
// uitschrijflink is geen slordigheid maar een overtreding, en dat mag niet
// afhangen van of iemand eraan dacht bij het opstellen. Wie de link liever
// ergens in zijn eigen tekst zet, gebruikt {{uitschrijflink}} -- die wordt
// hieronder ook vervangen. De voettekst blijft er dan gewoon bij staan.
//
// Tabellen met inline CSS, geen div met padding: Outlook op Windows negeert
// padding en max-width op een div, en dan loopt de voettekst over de volle
// breedte van het scherm.
//
// LET OP: controleer of hier nog een postadres bij moet. Voor commerciele mail
// wordt dat in verschillende rechtsgebieden verwacht, en het staat er nu niet.
function voettekst(uitschrijfUrl) {
  return `
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:28px;border-top:1px solid #e2e8f0">
  <tr><td align="center" style="padding:18px 24px;font-family:sans-serif;font-size:12px;line-height:1.6;color:#94a3b8">
    Je krijgt deze mail omdat je je inschreef op de nieuwsbrief van PrevX.<br>
    <a href="${uitschrijfUrl}" style="color:#64748b">Uitschrijven</a>
    &nbsp;&middot;&nbsp;
    <a href="${SITE_URL}/contact" style="color:#64748b">Contact</a>
    &nbsp;&middot;&nbsp;
    <a href="${SITE_URL}" style="color:#64748b">prevx.be</a>
  </td></tr>
</table>`;
}

function bouwHtml(campagneHtml, uitschrijfUrl) {
  const romp = String(campagneHtml || '').split('{{uitschrijflink}}').join(uitschrijfUrl);
  return `
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f1f5f9">
  <tr><td align="center" style="padding:24px 12px">
    <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:600px;max-width:100%;background:#ffffff;border-radius:12px">
      <tr><td style="padding:28px 32px;font-family:sans-serif;font-size:15px;line-height:1.7;color:#334155">
${romp}
      </td></tr>
    </table>
    ${voettekst(uitschrijfUrl)}
  </td></tr>
</table>`;
}

function bouwTekst(campagneTekst, uitschrijfUrl) {
  const romp = String(campagneTekst || '').split('{{uitschrijflink}}').join(uitschrijfUrl);
  return `${romp}

---
Je krijgt deze mail omdat je je inschreef op de nieuwsbrief van PrevX.
Uitschrijven: ${uitschrijfUrl}
${SITE_URL}`;
}

// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('verzend-nieuwsbrief crashte:', e && e.stack ? e.stack : e);
    return new Response(JSON.stringify({ error: String((e && e.message) || e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...corsHeaders(req) }
    });
  }
});

async function verwerk(req) {
  // antwoord() staat binnen verwerk zodat het req kent en overal de
  // CORS-headers meegeeft. Zonder die headers ziet de browser elk antwoord --
  // ook een keurige 403 -- als een netwerkfout.
  function antwoord(data, status) {
    return new Response(JSON.stringify(data), {
      status: status || 200,
      headers: { 'Content-Type': 'application/json', ...corsHeaders(req) }
    });
  }

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method !== 'POST') {
    return antwoord({ error: 'Gebruik POST' }, 405);
  }

  // De rolcontrole gebeurt met de sleutel van de aanroeper, niet met de
  // service-rol: anders zou is_superbeheerder() naar auth.uid() kijken van
  // niemand en altijd false teruggeven.
  const auth = req.headers.get('Authorization') || '';
  const alsGebruiker = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } }
  });
  const { data: isSuper, error: rolFout } = await alsGebruiker.rpc('is_superbeheerder');
  if (rolFout || !isSuper) {
    return antwoord({ error: 'Enkel de superbeheerder mag een nieuwsbrief versturen' }, 403);
  }

  const { campagne_id, test_naar } = await req.json().catch(() => ({}));
  if (!campagne_id) return antwoord({ error: 'campagne_id ontbreekt' }, 400);

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: campagne, error: cFout } = await sb
    .from('nieuwsbrief_campagnes')
    .select('id,onderwerp,html,tekst,status')
    .eq('id', campagne_id)
    .maybeSingle();

  if (cFout || !campagne) return antwoord({ error: 'Onbekende campagne' }, 404);
  if (!campagne.onderwerp || !campagne.html) {
    return antwoord({ error: 'Campagne heeft geen onderwerp of geen html' }, 422);
  }

  // ---------------------------------------------------------------------------
  // Testmail
  // ---------------------------------------------------------------------------
  // Staat bewust voor de statuscontroles hieronder: een test hoort te werken
  // terwijl de campagne nog een klad is. Dat is het hele punt -- je wil de
  // opmaak in je eigen mailbox zien voordat je ontvangers klaarzet, niet erna.
  //
  // Raakt de wachtrij niet aan en schrijft niets weg. De uitschrijflink wijst
  // naar een verzonnen token, zodat de pagina 'link werkt niet meer' toont in
  // plaats van iemand echt uit te schrijven -- maar de knop staat er wel, want
  // juist die wil je in een test kunnen zien.
  if (test_naar) {
    const nepUrl = `${LINK_BASIS}?actie=uitschrijven&token=test`;
    const bericht = {
      from: AFZENDER,
      to: [String(test_naar)],
      subject: `[TEST] ${campagne.onderwerp}`,
      html: bouwHtml(campagne.html, nepUrl),
      text: bouwTekst(campagne.tekst, nepUrl)
    };
    if (ANTWOORD_AAN) bericht.reply_to = ANTWOORD_AAN;

    const tResp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(bericht)
    });
    const tRuw = await tResp.text();
    if (!tResp.ok) {
      console.error('Testmail vertrok niet:', tResp.status, tRuw.slice(0, 500));
      return antwoord({ error: `Testmail vertrok niet: ${tRuw.slice(0, 200)}` }, 502);
    }
    return antwoord({ ok: true, test: true, boodschap: `Testmail verstuurd naar ${test_naar}.` });
  }

  if (campagne.status === 'verzonden') return antwoord({ error: 'Deze campagne is al verzonden' }, 409);
  if (campagne.status === 'klad') {
    return antwoord({ error: 'Zet eerst de ontvangers klaar met rpc_nieuwsbrief_klaarzetten' }, 409);
  }

  await sb.from('nieuwsbrief_campagnes').update({ status: 'bezig' }).eq('id', campagne_id);

  const start = Date.now();
  let verzonden = 0;
  let mislukt = 0;

  while (Date.now() - start < TIJDBUDGET_MS) {
    const { data: rijen, error: rFout } = await sb
      .from('nieuwsbrief_verzendingen')
      .select('id,email,abonnee_id,nieuwsbrief_abonnees(token,status)')
      .eq('campagne_id', campagne_id)
      .eq('status', 'wachtrij')
      .limit(PER_BATCH);

    if (rFout) {
      console.error('Wachtrij lezen faalde:', rFout);
      return antwoord({ error: 'Wachtrij lezen faalde' }, 500);
    }
    if (!rijen || rijen.length === 0) break;

    // Wie intussen uitschreef, bouncete of klaagde tussen het klaarzetten en
    // het versturen, valt hier alsnog af. Dat venster kan dagen zijn; zonder
    // deze controle stuur je post naar iemand die net op 'uitschrijven' duwde.
    // Een gewiste abonnee (abonnee_id null) heeft geen token en dus geen
    // geldige uitschrijflink -- die mag per definitie geen mail krijgen.
    const overslaan = [];
    const versturen = [];
    for (const rij of rijen) {
      const ab = rij.nieuwsbrief_abonnees;
      if (!ab || !ab.token || ab.status !== 'aangemeld') overslaan.push(rij);
      else versturen.push(rij);
    }

    if (overslaan.length) {
      await sb.from('nieuwsbrief_verzendingen')
        .update({ status: 'mislukt', fout: 'niet langer aangemeld bij verzenden' })
        .in('id', overslaan.map((r) => r.id));
      mislukt += overslaan.length;
    }
    if (versturen.length === 0) continue;

    const batch = versturen.map((rij) => {
      const uitschrijfUrl = `${LINK_BASIS}?actie=uitschrijven&token=${rij.nieuwsbrief_abonnees.token}`;
      const bericht = {
        from: AFZENDER,
        to: [rij.email],
        subject: campagne.onderwerp,
        html: bouwHtml(campagne.html, uitschrijfUrl),
        text: bouwTekst(campagne.tekst, uitschrijfUrl),
        // Hiermee toont Gmail zijn eigen Uitschrijven-knop naast de afzender.
        // Dat is geen beleefdheid maar reputatiebeheer: wie die knop niet
        // vindt, duwt op Spam, en dat weegt vele malen zwaarder.
        headers: {
          'List-Unsubscribe': `<${uitschrijfUrl}>`,
          'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click'
        }
      };
      if (ANTWOORD_AAN) bericht.reply_to = ANTWOORD_AAN;
      return bericht;
    });

    const resp = await fetch('https://api.resend.com/emails/batch', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(batch)
    });

    const ruw = await resp.text();
    let uitslag;
    try { uitslag = JSON.parse(ruw); } catch (e) { uitslag = null; }

    if (!resp.ok) {
      // Deze rijen worden NIET teruggezet op 'wachtrij'. We weten niet of er
      // iets vertrokken is, en dan is niets sturen beter dan mogelijk dubbel
      // sturen. Opnieuw in de wachtrij zetten is een bewuste handmatige daad:
      //   update nieuwsbrief_verzendingen set status = 'wachtrij', fout = null
      //   where campagne_id = '...' and status = 'mislukt';
      console.error('Resend weigerde de batch:', resp.status, ruw.slice(0, 800));
      await sb.from('nieuwsbrief_verzendingen')
        .update({ status: 'mislukt', fout: `resend ${resp.status}: ${ruw.slice(0, 300)}` })
        .in('id', versturen.map((r) => r.id));
      mislukt += versturen.length;
      await wacht(PAUZE_MS);
      continue;
    }

    // Resend geeft de ids terug in dezelfde volgorde als de aanvraag. Klopt de
    // lengte niet, dan kunnen we ze niet toewijzen -- de mail is dan wel
    // vertrokken, dus we markeren ze als verzonden maar zonder resend_id. Die
    // ontvangers zijn onvindbaar voor de bounce-webhook; vandaar het luide log.
    const ids = uitslag && Array.isArray(uitslag.data) ? uitslag.data : [];
    if (ids.length !== versturen.length) {
      console.warn(`Resend gaf ${ids.length} ids voor ${versturen.length} berichten -- geen toewijzing mogelijk.`);
    }

    const nu = new Date().toISOString();
    for (let i = 0; i < versturen.length; i++) {
      const { error: uFout } = await sb.from('nieuwsbrief_verzendingen')
        .update({ status: 'verzonden', resend_id: (ids[i] && ids[i].id) || null, verzonden_op: nu })
        .eq('id', versturen[i].id);

      // Hier stoppen en niet doorgaan. Deze rij staat nog op 'wachtrij' terwijl
      // de mail al vertrokken is; de volgende ronde zou hem opnieuw oppikken en
      // dezelfde persoon een tweede keer aanschrijven. Beter een campagne die
      // halverwege stilvalt en die je met de hand nakijkt, dan een lus die
      // stilletjes dubbele post uitdeelt.
      if (uFout) {
        console.error('KRITIEK: mail vertrok maar de rij kon niet bijgewerkt worden.',
          'verzending_id=', versturen[i].id, uFout);
        return antwoord({
          error: 'Verzending gestopt: een rij kon niet bijgewerkt worden nadat de mail vertrokken was. ' +
                 'Kijk deze campagne met de hand na voor je opnieuw verstuurt.',
          verzonden: verzonden,
          verzending_id: versturen[i].id
        }, 500);
      }

      await sb.from('nieuwsbrief_abonnees')
        .update({ laatste_mail_op: nu })
        .eq('id', versturen[i].abonnee_id);
      verzonden++;
    }

    await wacht(PAUZE_MS);
  }

  const { count: resterend } = await sb
    .from('nieuwsbrief_verzendingen')
    .select('id', { count: 'exact', head: true })
    .eq('campagne_id', campagne_id)
    .eq('status', 'wachtrij');

  const klaar = !resterend;
  if (klaar) {
    await sb.from('nieuwsbrief_campagnes')
      .update({ status: 'verzonden', verzonden_op: new Date().toISOString() })
      .eq('id', campagne_id);
  }

  return antwoord({
    ok: true,
    verzonden: verzonden,
    mislukt: mislukt,
    resterend: resterend || 0,
    klaar: klaar,
    boodschap: klaar
      ? 'De campagne is volledig verzonden.'
      : `Tijdslimiet bereikt. Roep opnieuw aan om de resterende ${resterend} af te werken.`
  });
}
