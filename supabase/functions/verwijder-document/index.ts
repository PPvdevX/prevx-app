// Supabase Edge Function: verwijdert een document -- eerst het bestand via de
// Storage-API, dan de rij.
//
// Waarom een functie en niet gewoon een delete vanuit het portaal: de rij mag de
// superbeheerder al weghalen (policy uit 0023), maar het bestand in Storage niet.
// Rechtstreeks vanuit de browser werkt de Storage-API op dit project niet -- de
// JWT-signing-key is ooit naar ECC gedraaid en Storage verwerkt dat niet, wat de
// reden is dat ook uploaden via een Edge Function loopt. Zonder deze functie zou
// je de rij verwijderen en het bestand laten staan, zonder pad om het nog terug
// te vinden.
//
// Volgorde: eerst het bestand, dan de rij. Het pad staat ín de rij; verdwijnt die
// eerst, dan is een achtergebleven bestand niet meer te vinden. Andersom is de
// slechtste uitkomst een rij die naar een verdwenen bestand wijst -- zichtbaar en
// op te lossen.
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt), zoals bij de andere
// functies hier. De aanroeper wordt zelf geverifieerd, met zijn eigen token.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const ANON_KEY = Deno.env.get('ANON_KEY');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type'
};

function antwoord(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('verwijder-document crashte:', e && e.stack ? e.stack : e);
    return antwoord({ error: String((e && e.message) || e) }, 500);
  }
});

async function verwerk(req) {
  const { document_id, access_token } = await req.json();
  if (!document_id || !access_token) {
    return antwoord({ error: 'document_id en access_token zijn verplicht' }, 400);
  }

  const alsGebruiker = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } }
  });

  const { data: isSuper, error: superErr } = await alsGebruiker.rpc('is_superbeheerder');
  if (superErr || isSuper !== true) {
    return antwoord({ error: 'Niet geautoriseerd' }, 401);
  }

  const dienst = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: doc } = await dienst
    .from('documenten')
    .select('id,bedrijf_id,code,titel,bestand_url')
    .eq('id', document_id)
    .maybeSingle();

  if (!doc) {
    return antwoord({ error: 'Document niet gevonden' }, 404);
  }

  // Het pad uit de opgeslagen URL halen. Staat er geen bestand (upload ooit
  // mislukt), dan is er niets te wissen en gaat de rij gewoon weg.
  if (doc.bestand_url) {
    const m = /\/storage\/v1\/object\/(?:public\/|sign\/)?documenten\/([^?]+)/.exec(doc.bestand_url);
    if (m) {
      const pad = decodeURIComponent(m[1]);
      const { error: wisErr } = await dienst.storage.from('documenten').remove([pad]);
      if (wisErr) {
        // Niets verwijderd: veilig om opnieuw te proberen.
        console.error('Bestand wissen mislukt voor', document_id, wisErr);
        return antwoord({ error: 'Het bestand kon niet verwijderd worden: ' + wisErr.message }, 500);
      }
    } else {
      console.error('Kon geen pad afleiden uit bestand_url van', document_id);
    }
  }

  // Een afspraak kan naar dit document wijzen (planning.document_id, 0024). Die
  // verwijzing heeft geen on delete-afspraak, dus de databank weigert het
  // document weg te gooien zolang ze bestaat -- met een foutmelding waar niemand
  // iets aan heeft.
  //
  // De verwijzing losmaken en de afspraak laten staan is hier het juiste: het
  // bezoek heeft plaatsgevonden, alleen het verslag verdwijnt. De afspraak zelf
  // wissen zou geschiedenis vernietigen die niets met dit document te maken
  // heeft.
  const { error: losErr } = await dienst
    .from('planning')
    .update({ document_id: null })
    .eq('document_id', document_id);
  if (losErr) {
    console.error('Afspraak losmaken faalde voor', document_id, losErr);
    return antwoord({ error: 'De gekoppelde afspraak kon niet losgemaakt worden: ' + losErr.message }, 500);
  }

  // De rij wordt met het token van de aanroeper verwijderd, niet met de
  // service-rol: zo blijft de policy uit 0023 bepalen wie dit mag, en niet deze
  // functie.
  const { error: rijErr } = await alsGebruiker.from('documenten').delete().eq('id', document_id);
  if (rijErr) {
    // Ook in error, niet alleen in waarschuwing: de aanroeper toont dat veld bij
    // een mislukking, en zonder dit stond er enkel 'verwijderen mislukt'.
    return antwoord({
      ok: false,
      error: 'Het bestand is verwijderd, maar de rij niet: ' + rijErr.message,
      waarschuwing: 'Het bestand is verwijderd, maar de rij niet: ' + rijErr.message
    }, 500);
  }

  return antwoord({ ok: true, code: doc.code, titel: doc.titel }, 200);
}
