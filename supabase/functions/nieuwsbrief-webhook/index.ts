// Supabase Edge Function: ontvangt de gebeurtenissen die Resend terugstuurt
// over verzonden nieuwsbriefmail -- vooral bounces en spamklachten. Hoort bij
// migratie 0089.
//
// ---------------------------------------------------------------------------
// Waarom dit geen bijzaak is
// ---------------------------------------------------------------------------
// Zonder deze functie blijft de lijst stilzwijgend rotten: adressen die niet
// meer bestaan worden elke maand opnieuw aangeschreven, en mensen die ons als
// spam markeerden krijgen gewoon de volgende nieuwsbrief. Beide zijn precies de
// signalen waarop Gmail en Outlook een afzender beoordelen. Wie ze negeert,
// merkt dat niet aan de nieuwsbrief maar aan de rest: op een dag komt een
// inspectierapport in de map Ongewenst terecht en weet niemand waarom.
//
// ---------------------------------------------------------------------------
// Afscherming
// ---------------------------------------------------------------------------
// Resend kan geen Supabase-JWT meesturen en kent onze Vault-sleutel niet, dus
// het patroon van de andere functies gaat hier niet op. In de plaats komt de
// handtekening die Resend zelf zet (via Svix): elke aanroep draagt svix-id,
// svix-timestamp en svix-signature, en die laatste is een HMAC over de eerste
// twee plus de ruwe body. Klopt de handtekening niet, dan doen we niets --
// fail closed, zoals overal hier.
//
// Het geheim komt uit het functie-geheim RESEND_WEBHOOK_SECRET (de whsec_-waarde
// die Resend toont bij het aanmaken van de webhook). Bewust niet uit Vault: dit
// geheim is van Resend, niet van ons, en de databank heeft het nergens voor
// nodig.
//
// Verify JWT moet UIT staan, anders raakt Resend nooit binnen:
//
//   supabase functions deploy nieuwsbrief-webhook --no-verify-jwt

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const WEBHOOK_SECRET = Deno.env.get('RESEND_WEBHOOK_SECRET') || '';

// Vijf minuten speling. Zonder deze controle kan iemand die ooit een geldige
// aanroep onderschepte, die jaren later opnieuw afspelen.
const SPELING_SECONDEN = 5 * 60;

function base64NaarBytes(waarde) {
  const ruw = atob(waarde);
  const bytes = new Uint8Array(ruw.length);
  for (let i = 0; i < ruw.length; i++) bytes[i] = ruw.charCodeAt(i);
  return bytes;
}

function bytesNaarBase64(bytes) {
  let s = '';
  const arr = new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) s += String.fromCharCode(arr[i]);
  return btoa(s);
}

// Even lang vergelijken ongeacht waar het verschil zit. Een gewone === lekt via
// het tijdsverschil hoeveel tekens er klopten, en dat is genoeg om een
// handtekening teken per teken te raden.
function gelijkInVasteTijd(a, b) {
  if (a.length !== b.length) return false;
  let verschil = 0;
  for (let i = 0; i < a.length; i++) verschil |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return verschil === 0;
}

async function handtekeningKlopt(req, ruweBody) {
  if (!WEBHOOK_SECRET) {
    console.error('RESEND_WEBHOOK_SECRET ontbreekt -- alles wordt geweigerd.');
    return false;
  }

  const id = req.headers.get('svix-id');
  const tijdstempel = req.headers.get('svix-timestamp');
  const handtekeningen = req.headers.get('svix-signature');
  if (!id || !tijdstempel || !handtekeningen) return false;

  const leeftijd = Math.abs(Math.floor(Date.now() / 1000) - parseInt(tijdstempel, 10));
  if (!isFinite(leeftijd) || leeftijd > SPELING_SECONDEN) {
    console.error('Aanroep te oud of tijdstempel onleesbaar:', tijdstempel);
    return false;
  }

  const sleutel = await crypto.subtle.importKey(
    'raw',
    base64NaarBytes(WEBHOOK_SECRET.replace(/^whsec_/, '')),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const berekend = bytesNaarBase64(
    await crypto.subtle.sign('HMAC', sleutel, new TextEncoder().encode(`${id}.${tijdstempel}.${ruweBody}`))
  );

  // De header kan meerdere handtekeningen bevatten (bij sleutelrotatie), als
  // "v1,<base64> v1,<base64>". Eén die klopt volstaat.
  return handtekeningen.split(' ').some(function (deel) {
    const stuk = deel.split(',');
    return stuk.length === 2 && stuk[0] === 'v1' && gelijkInVasteTijd(stuk[1], berekend);
  });
}

// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('nieuwsbrief-webhook crashte:', e && e.stack ? e.stack : e);
    // Bewust 500: dan probeert Resend het later opnieuw. Een 200 teruggeven op
    // iets dat misging, betekent dat de gebeurtenis voorgoed weg is.
    return new Response('fout', { status: 500 });
  }
});

async function verwerk(req) {
  if (req.method !== 'POST') return new Response('Niet gevonden', { status: 404 });

  // De ruwe tekst, niet het geparste object: de handtekening staat over de
  // bytes zoals ze binnenkwamen. JSON.parse en dan weer stringify geeft een
  // andere tekst en dus een andere handtekening.
  const ruweBody = await req.text();

  if (!(await handtekeningKlopt(req, ruweBody))) {
    return new Response('Unauthorized', { status: 401 });
  }

  let gebeurtenis;
  try { gebeurtenis = JSON.parse(ruweBody); } catch (e) {
    console.error('Onleesbare body:', ruweBody.slice(0, 500));
    return new Response('ok', { status: 200 }); // opnieuw sturen heeft geen zin
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const soort = gebeurtenis.type;
  const data = gebeurtenis.data || {};
  const resendId = data.email_id || null;
  const ontvanger = Array.isArray(data.to) && data.to.length ? String(data.to[0]).toLowerCase() : null;

  if (soort === 'email.bounced') {
    // Onderscheid tussen hard en zacht is hier het hele punt. Een volle mailbox
    // of een server die even plat ligt is geen reden om iemand uit de lijst te
    // gooien; een adres dat niet bestaat wel.
    //
    // Het veld heet data.bounce.type en draagt de SES-woordenschat ('Permanent',
    // 'Transient'). Ontbreekt het, dan blijft de abonnee staan en markeren we
    // enkel deze ene verzending -- liever een keer te weinig geschrapt. De ruwe
    // gebeurtenis gaat dan naar de logs: kijk bij de eerste echte bounce even
    // na of het veld er staat zoals hier verondersteld.
    const soortBounce = (data.bounce && data.bounce.type) || null;
    const blijvend = soortBounce === 'Permanent';
    if (!soortBounce) console.warn('Bounce zonder type-veld:', JSON.stringify(gebeurtenis).slice(0, 800));

    await markeerVerzending(sb, resendId, 'bounce', (data.bounce && data.bounce.message) || soortBounce || 'bounce');
    if (blijvend) await markeerAbonnee(sb, ontvanger, 'bounce');
    return new Response('ok', { status: 200 });
  }

  if (soort === 'email.complained') {
    // Geen nuance nodig: wie op "spam" duwt, is klaar met ons. Meteen uit de
    // lijst, en anders dan bij een uitschrijving komt hij er via het formulier
    // niet vanzelf weer in (zie de edge-functie 'nieuwsbrief').
    await markeerVerzending(sb, resendId, 'klacht', 'spamklacht');
    await markeerAbonnee(sb, ontvanger, 'klacht');
    return new Response('ok', { status: 200 });
  }

  // email.sent, email.delivered, email.delivery_delayed en de rest: niets te
  // doen. De verzendfunctie zet de status al bij het versturen, en een aparte
  // 'bezorgd'-status voegt niets toe zolang niemand ernaar kijkt.
  return new Response('ok', { status: 200 });
}

async function markeerVerzending(sb, resendId, status, fout) {
  if (!resendId) return;
  const { error } = await sb
    .from('nieuwsbrief_verzendingen')
    .update({ status: status, fout: fout })
    .eq('resend_id', resendId);
  if (error) console.error('Verzending bijwerken faalde:', error);
}

async function markeerAbonnee(sb, email, status) {
  if (!email) return;

  // Enkel wie nu nog mail zou krijgen. Wie zelf uitschreef staat op 'afgemeld',
  // en dat is waardevoller om te bewaren dan 'bounce': het zegt dat hij het
  // gevraagd heeft, niet dat de post terugkwam.
  const { error } = await sb
    .from('nieuwsbrief_abonnees')
    .update({ status: status })
    .eq('email', email)
    .in('status', ['aangemeld', 'bevestiging_open']);
  if (error) console.error('Abonnee bijwerken faalde:', error);
}
