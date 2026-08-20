// Supabase Edge Function: de publieke kant van de nieuwsbrief -- aanmelden,
// bevestigen, uitschrijven. Hoort bij migratie 0089.
//
// ---------------------------------------------------------------------------
// Deze functie is bewust WEL publiek. Lees dit voor je hem aanpast.
// ---------------------------------------------------------------------------
// Alle andere functies hier controleren een gedeelde sleutel uit Vault, omdat
// ze door de databank worden aangeroepen en door niemand anders. Deze niet, en
// dat kan ook niet anders: het aanmeldformulier staat op prevx.be en de
// uitschrijflink wordt aangeklikt door Gmail, Outlook en Apple Mail. Er is geen
// sleutel die je daar kwijt kan zonder hem meteen weg te geven.
//
// Wat de functie dan wel beschermt, is dat ze bijna niets kan:
//
//   - Ze geeft nooit een lijst terug. Geen enkel antwoord verschilt naargelang
//     een adres al bestaat of niet -- anders wordt dit een gratis dienst om uit
//     te zoeken wie er bij ons in de lijst staat.
//   - Aanmelden zet iemand op 'bevestiging_open'. Dat verstuurt precies een
//     mail: de bevestiging. Wie het adres van iemand anders invult, veroorzaakt
//     dus een mail, geen abonnement.
//   - Bevestigen en uitschrijven werken enkel op een token van 64 hextekens dat
//     alleen in de mail zelf staat.
//
// Verify JWT moet voor deze functie UIT staan. Die schakelaar springt bij elke
// herimplementatie terug aan; staat hij aan, dan krijgt elke bezoeker
// UNAUTHORIZED_NO_AUTH_HEADER en merk je dat pas als iemand klaagt dat
// uitschrijven niet werkt. Zet hem meteen na het deployen weer uit:
//
//   supabase functions deploy nieuwsbrief --no-verify-jwt

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');

// Bewust een eigen afzender, niet rapporten@ of account@. Een nieuwsbrief wordt
// nu eenmaal weggeklikt als spam, en die reputatieschade mag nooit de
// bezorging van een inspectierapport of een inlogmail meeslepen. Zet dit
// geheim op een adres van een apart (sub)domein dat in Resend geverifieerd is.
const AFZENDER = Deno.env.get('NIEUWSBRIEF_AFZENDER') || 'PrevX <nieuws@prevx.be>';
const ANTWOORD_AAN = Deno.env.get('NIEUWSBRIEF_ANTWOORD') || '';

const SITE_URL = Deno.env.get('SITE_URL') || 'https://prevx.be';

// De basis van de bevestig- en uitschrijflinks. Standaard de functie-URL zelf.
// Wil je later nettere links (prevx.be/n/...) dan zet je hier die basis en laat
// je Cloudflare Pages doorsturen -- een supabase.co-adres in een nieuwsbrief
// oogt niet als jouw huis, en dat scheelt in vertrouwen en in spamscore.
const LINK_BASIS = Deno.env.get('NIEUWSBRIEF_LINK_BASIS') || `${SUPABASE_URL}/functions/v1/nieuwsbrief`;

const TOEGELATEN_HERKOMST = [
  'https://prevx.be',
  'https://www.prevx.be'
];

function corsHeaders(req) {
  const herkomst = req.headers.get('origin') || '';
  return {
    'Access-Control-Allow-Origin': TOEGELATEN_HERKOMST.includes(herkomst) ? herkomst : TOEGELATEN_HERKOMST[0],
    'Access-Control-Allow-Headers': 'content-type',
    'Access-Control-Allow-Methods': 'POST, GET, OPTIONS'
  };
}

// Genoeg om vingerfouten tegen te houden. Strenger valideren heeft geen zin --
// de bevestigingsmail is de echte controle: een adres dat niet bestaat,
// bevestigt nooit.
function lijktOpEmail(waarde) {
  return typeof waarde === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(waarde.trim());
}

function ontsnap(tekst) {
  return String(tekst == null ? '' : tekst)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ---------------------------------------------------------------------------
// Waarom deze functie geen pagina teruggeeft maar doorstuurt
// ---------------------------------------------------------------------------
// Supabase weigert HTML te serveren vanaf functions/v1 op het gedeelde
// supabase.co-domein: het overschrijft Content-Type naar text/plain en zet er
// X-Content-Type-Options: nosniff bij. Een pagina teruggeven kan hier dus
// niet -- de bezoeker krijgt de broncode als kale tekst te zien. Dat is geen
// bug maar beleid: een gedeeld domein waarop iedereen willekeurige pagina's
// kan hosten, is precies wat phishers zoeken.
//
// Dus doet deze functie het databankwerk en stuurt ze de bezoeker daarna door
// naar een gewone pagina op prevx.be. Dat is meer dan een omweg om een
// beperking: de bezoeker ziet nu prevx.be in zijn adresbalk in plaats van een
// supabase.co-adres, en dat is precies wat je wil bij een link uit een mail.
//
// LET OP: de one-click-POST van Gmail en Outlook krijgt GEEN omleiding. Die
// verwacht een kale 200 en volgt niets -- zie uitschrijven(..., stil).
function naarPagina(pad) {
  return new Response(null, { status: 302, headers: { Location: `${SITE_URL}/${pad}` } });
}

function json(req, data, status) {
  return new Response(JSON.stringify(data), {
    status: status || 200,
    headers: { 'Content-Type': 'application/json', ...corsHeaders(req) }
  });
}

// ---------------------------------------------------------------------------
// Aanmelden
// ---------------------------------------------------------------------------
async function aanmelden(req, sb) {
  let body;
  try { body = await req.json(); } catch (e) { body = {}; }

  // Meteen naar kleine letters, en zo gaat het ook de databank in. Migratie
  // 0089 legt dat met een check-constraint vast, zodat de vergelijking
  // hieronder een gewone gelijkheid kan zijn.
  //
  // Uitdrukkelijk GEEN ilike gebruiken om hoofdletterongevoelig te zoeken: in
  // een ilike-patroon is _ een jokerteken, en onderstrepingstekens zitten in
  // echte e-mailadressen. "ja_@x.be" zou dan de rij van "jan@x.be" opleveren,
  // en die van iemand anders overschrijven.
  const email = String(body.email || '').trim().toLowerCase();
  if (!lijktOpEmail(email)) {
    return json(req, { error: 'Vul een geldig e-mailadres in.' }, 400);
  }

  const naam = body.naam ? String(body.naam).slice(0, 120) : null;
  const bedrijfsnaam = body.bedrijfsnaam ? String(body.bedrijfsnaam).slice(0, 160) : null;
  const bron = body.bron ? String(body.bron).slice(0, 60) : 'website';

  // Eén antwoord voor alle gevallen hieronder. Wie het adres van een ander
  // invult, mag niet kunnen afleiden of dat adres al in de lijst stond.
  const antwoord = json(req, {
    ok: true,
    boodschap: 'Bijna klaar. We stuurden een bevestigingsmail — klik de link erin om je inschrijving af te ronden.'
  });

  const { data: bestaand } = await sb
    .from('nieuwsbrief_abonnees')
    .select('id,status,bevestiging_gestuurd_op')
    .eq('email', email)
    .maybeSingle();

  // Een spamklacht is een zwaarder signaal dan een formulier. Wie ons ooit als
  // spam markeerde, halen we niet terug met een invulveld -- dat moet dan maar
  // handmatig, met iemand die het echt gevraagd heeft.
  if (bestaand && bestaand.status === 'klacht') return antwoord;

  // Al bevestigd: niets doen. Opnieuw een bevestigingsmail sturen naar iemand
  // die al abonnee is, is precies de mail die niemand wil.
  if (bestaand && bestaand.status === 'aangemeld') return antwoord;

  // De rem. Dit formulier staat open op het internet: zonder deze controle kan
  // iemand het adres van een ander in een lus indienen en zo diens mailbox
  // vullen met onze bevestigingsmails. Binnen het venster doen we niets -- de
  // vorige link is nog geldig en ligt al in zijn inbox.
  if (bestaand && bestaand.bevestiging_gestuurd_op &&
      Date.now() - new Date(bestaand.bevestiging_gestuurd_op).getTime() < 10 * 60 * 1000) {
    return antwoord;
  }

  const token = crypto.randomUUID().replace(/-/g, '') + crypto.randomUUID().replace(/-/g, '');
  const verlooptOp = new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString();

  if (bestaand) {
    // Ook wie eerder uitschreef of bouncete mag opnieuw beginnen: een nieuwe,
    // uitdrukkelijke aanmelding overstemt een oude uitschrijving. De
    // bevestigingsstap zorgt dat dat echt van hem komt.
    const { error } = await sb.from('nieuwsbrief_abonnees').update({
      naam: naam, bedrijfsnaam: bedrijfsnaam, bron: bron,
      status: 'bevestiging_open',
      bevestig_token: token,
      bevestig_verloopt_op: verlooptOp,
      bevestiging_gestuurd_op: new Date().toISOString(),
      afgemeld_op: null
    }).eq('id', bestaand.id);
    if (error) { console.error('Bijwerken abonnee faalde:', error); return json(req, { error: 'Er ging iets mis.' }, 500); }
  } else {
    const { error } = await sb.from('nieuwsbrief_abonnees').insert({
      email: email, naam: naam, bedrijfsnaam: bedrijfsnaam, bron: bron,
      status: 'bevestiging_open',
      bevestig_token: token,
      bevestig_verloopt_op: verlooptOp,
      bevestiging_gestuurd_op: new Date().toISOString()
    });
    if (error) { console.error('Toevoegen abonnee faalde:', error); return json(req, { error: 'Er ging iets mis.' }, 500); }
  }

  await stuurBevestiging(email, naam, token);
  return antwoord;
}

async function stuurBevestiging(email, naam, token) {
  const link = `${LINK_BASIS}?actie=bevestigen&token=${token}`;
  const aanhef = naam ? `Hallo ${ontsnap(naam)},` : 'Hallo,';

  const html = `
  <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
    <div style="background:#003366;padding:18px 24px"><span style="color:#fff;font-weight:800;font-size:16px;letter-spacing:0.5px">NIEUWSBRIEF PREVX</span></div>
    <div style="padding:20px 24px;color:#334155;font-size:14px;line-height:1.6">
      <p>${aanhef}</p>
      <p>Je schreef je in op de nieuwsbrief van PrevX. Eén klik nog, dan is het in orde:</p>
      <p style="margin:22px 0"><a href="${link}" style="background:#E97F02;color:#fff;text-decoration:none;padding:11px 22px;border-radius:8px;font-weight:600;display:inline-block">Mijn inschrijving bevestigen</a></p>
      <p style="font-size:12px;color:#94a3b8">Werkt de knop niet? Plak deze link in je browser:<br>${link}</p>
      <p style="font-size:12px;color:#94a3b8">Heb je je niet ingeschreven? Doe dan niets — zonder die klik sturen we je geen nieuwsbrief. Deze link vervalt na zeven dagen.</p>
    </div>
  </div>`;

  const tekst = `${naam ? 'Hallo ' + naam : 'Hallo'},

Je schreef je in op de nieuwsbrief van PrevX. Bevestig je inschrijving via deze link:

${link}

Heb je je niet ingeschreven? Doe dan niets. De link vervalt na zeven dagen.`;

  const bericht = {
    from: AFZENDER,
    to: [email],
    subject: 'Bevestig je inschrijving op de PrevX-nieuwsbrief',
    html: html,
    text: tekst
  };
  if (ANTWOORD_AAN) bericht.reply_to = ANTWOORD_AAN;

  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(bericht)
  });

  // Defensief parsen, zoals in send-inspectie-email: geeft Resend geen geldige
  // JSON terug, dan crashte een kale .json() de hele functie.
  if (!resp.ok) {
    const ruw = await resp.text();
    console.error('Bevestigingsmail vertrok niet:', resp.status, ruw);
  }
}

// ---------------------------------------------------------------------------
// Bevestigen
// ---------------------------------------------------------------------------
async function bevestigen(req, sb, token) {
  const { data: abonnee } = await sb
    .from('nieuwsbrief_abonnees')
    .select('id,status,bevestig_verloopt_op')
    .eq('bevestig_token', token)
    .maybeSingle();

  if (!abonnee) {
    // Ook het normale geval: iemand klikt de link een tweede keer. Het token is
    // dan al gewist, dus we komen hier. Geen foutmelding tonen aan wie gewoon
    // twee keer duwde -- zeggen wat er aan de hand is volstaat.
    return naarPagina('nieuwsbrief-link');
  }

  if (abonnee.bevestig_verloopt_op && new Date(abonnee.bevestig_verloopt_op) < new Date()) {
    return naarPagina('nieuwsbrief-link');
  }

  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || null;

  const { error } = await sb.from('nieuwsbrief_abonnees').update({
    status: 'aangemeld',
    toestemming_op: new Date().toISOString(),
    toestemming_bewijs: ip,
    bevestig_token: null,
    bevestig_verloopt_op: null
  }).eq('id', abonnee.id);

  if (error) {
    console.error('Bevestigen faalde:', error);
    return naarPagina('nieuwsbrief-fout');
  }

  return naarPagina('nieuwsbrief-bevestigd');
}

// ---------------------------------------------------------------------------
// Uitschrijven
// ---------------------------------------------------------------------------
// Twee ingangen naar dezelfde handeling:
//
//   GET  -- iemand klikt de link onderaan de mail.
//   POST -- de knop "Uitschrijven" van Gmail of Outlook zelf. Die werkt via
//           List-Unsubscribe-Post (RFC 8058): de mailclient doet in stilte een
//           POST en verwacht enkel een 200, geen pagina. Dat is het verschil
//           tussen iemand die uitschrijft en iemand die op spam duwt -- die
//           knop aanbieden is dus geen beleefdheid maar reputatiebeheer.
async function uitschrijven(req, sb, token, stil) {
  const { data: abonnee } = await sb
    .from('nieuwsbrief_abonnees')
    .select('id,status')
    .eq('token', token)
    .maybeSingle();

  if (!abonnee) {
    if (stil) return new Response('ok', { status: 200 });
    return naarPagina('nieuwsbrief-link');
  }

  // Wie al afgemeld is nog eens afmelden hoeft niet, maar mag ook geen fout
  // geven: dubbel klikken is normaal gedrag.
  if (abonnee.status !== 'afgemeld') {
    const { error } = await sb.from('nieuwsbrief_abonnees').update({
      status: 'afgemeld',
      afgemeld_op: new Date().toISOString()
    }).eq('id', abonnee.id);

    if (error) {
      console.error('Uitschrijven faalde:', error);
      if (stil) return new Response('fout', { status: 500 });
      return naarPagina('nieuwsbrief-fout');
    }
  }

  if (stil) return new Response('ok', { status: 200 });
  return naarPagina('nieuwsbrief-uitgeschreven');
}

// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('nieuwsbrief crashte:', e && e.stack ? e.stack : e);
    return new Response(JSON.stringify({ error: 'Er ging iets mis' }), { status: 500 });
  }
});

async function verwerk(req) {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const url = new URL(req.url);
  const actie = url.searchParams.get('actie');
  const token = url.searchParams.get('token');

  if (actie === 'bevestigen') {
    if (!token) return naarPagina('nieuwsbrief-link');
    return await bevestigen(req, sb, token);
  }

  if (actie === 'uitschrijven') {
    if (!token) return naarPagina('nieuwsbrief-link');
    return await uitschrijven(req, sb, token, req.method === 'POST');
  }

  if (req.method === 'POST') return await aanmelden(req, sb);

  return new Response('Niet gevonden', { status: 404 });
}
