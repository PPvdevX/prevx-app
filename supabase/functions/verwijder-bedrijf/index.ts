// Supabase Edge Function: verwijdert een bedrijf volledig -- eerst de rijen via
// rpc_verwijder_bedrijf_cascade, daarna de bestanden via de Storage-API.
//
// Waarom deze functie bestaat: de cascade deed het opruimen van bestanden
// eerst zelf, met een rechtstreekse delete op storage.objects (migratie 0069).
// Supabase weigert dat sinds kort -- "Direct deletion from storage tables is
// not allowed. Use the Storage API instead." -- waardoor de hele verwijdering
// afbrak. De databank raakt storage nu niet meer aan (0076) en dat werk gebeurt
// hier, langs de weg die Supabase wél toelaat.
//
// Volgorde: eerst de rijen, dan de bestanden. Andersom zou betekenen dat bij
// een mislukte cascade een bestaand bedrijf zijn bestanden kwijt is. Nu is de
// slechtste uitkomst dat er bestanden achterblijven -- vervelend, maar ze
// staan onder een pad dat met het bedrijf_id begint, dus ze zijn terug te
// vinden en alsnog op te ruimen. Dat verschil wordt ook zo gemeld.
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt), zoals bij de
// andere functies hier. De aanroeper wordt hieronder zelf geverifieerd: het
// verwijderen loopt via zijn eigen token, zodat is_superbeheerder() in de
// cascade zijn werk doet. De service-rol wordt alleen voor Storage gebruikt.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const ANON_KEY = Deno.env.get('ANON_KEY');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const BUCKETS = [
  'inspectie-media',
  'documenten',
  'kennisbank',
  'bedrijfsmiddel-fotos',
  'actiepunt-bewijsstukken'
];

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
    console.error('verwijder-bedrijf crashte:', e && e.stack ? e.stack : e);
    return antwoord({ error: String((e && e.message) || e) }, 500);
  }
});

async function verwerk(req) {
  const { bedrijf_id, access_token } = await req.json();
  if (!bedrijf_id || !access_token) {
    return antwoord({ error: 'bedrijf_id en access_token zijn verplicht' }, 400);
  }

  // Alles wat de aanroeper mag, gebeurt met zijn eigen token. Zou ik hier de
  // service-rol gebruiken, dan valt auth.uid() weg en geeft is_superbeheerder()
  // in de cascade false -- of erger, ik zou die controle moeten overslaan en
  // dan bepaalt deze functie wie een bedrijf mag wissen i.p.v. de databank.
  const alsGebruiker = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } }
  });

  const { data: isSuper, error: superErr } = await alsGebruiker.rpc('is_superbeheerder');
  if (superErr || isSuper !== true) {
    return antwoord({ error: 'Niet geautoriseerd' }, 401);
  }

  const { error: cascadeErr } = await alsGebruiker.rpc('rpc_verwijder_bedrijf_cascade', {
    p_bedrijf_id: bedrijf_id
  });
  if (cascadeErr) {
    // Niets verwijderd, niets opgeruimd: veilig om opnieuw te proberen.
    console.error('Cascade mislukt voor', bedrijf_id, cascadeErr);
    return antwoord({ error: cascadeErr.message }, 400);
  }

  const dienst = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  let verwijderd = 0;
  const mislukt = [];

  for (const bucket of BUCKETS) {
    const { data: bestanden, error: lijstErr } = await dienst.storage.from(bucket).list(bedrijf_id, { limit: 1000 });
    if (lijstErr) { mislukt.push(bucket + ': ' + lijstErr.message); continue; }
    if (!bestanden || !bestanden.length) continue;

    const paden = bestanden.map((b) => `${bedrijf_id}/${b.name}`);
    const { error: wisErr } = await dienst.storage.from(bucket).remove(paden);
    if (wisErr) { mislukt.push(bucket + ': ' + wisErr.message); continue; }
    verwijderd += paden.length;
  }

  if (mislukt.length) {
    // De rijen zijn weg, dus dit is geen fout die je kan terugdraaien -- maar
    // het mag ook niet stilzwijgend voorbijgaan: er staan dan nog bestanden van
    // een verwijderde klant. Het pad staat erbij zodat het op te ruimen valt.
    console.error('Bestanden niet opgeruimd voor', bedrijf_id, mislukt);
    return antwoord({
      ok: true,
      verwijderd,
      waarschuwing: 'Het bedrijf is verwijderd, maar niet alle bestanden konden opgeruimd worden. Ze staan onder pad ' +
        bedrijf_id + '/ in: ' + mislukt.join(', ')
    }, 200);
  }

  return antwoord({ ok: true, verwijderd }, 200);
}
