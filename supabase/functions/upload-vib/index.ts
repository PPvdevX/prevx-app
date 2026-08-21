// Supabase Edge Function: uploadt een veiligheidsinformatieblad en hangt het aan
// een product uit chemische_producten.
//
// Zelfde reden als bij de andere upload-functies om met de service_role te
// werken: de Storage-service verwerkt de door dit project ondertekende
// gebruikers-JWT's niet (zie upload-bedrijfsmiddel-foto/index.ts voor de
// volledige achtergrond).
//
// Verschil met upload-document: daar mag enkel de superbeheerder uploaden. Hier
// mag ook de klant-beheerder van het bedrijf in kwestie, want een productlijst
// die enkel de adviseur kan bijwerken veroudert tussen twee bezoeken door. De
// controle daarop gebeurt hieronder langs de kant van de aanroeper, met zijn
// eigen token -- niet met de service-role, die alles zou mogen.
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt bij deploy).

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const ANON_KEY = Deno.env.get('ANON_KEY');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type'
};

// Een VIB is een pdf. Andere types weigeren scheelt een bestand dat in de app
// niet opengaat, en het is de goedkoopste controle die er is.
const TOEGELATEN = ['application/pdf'];

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const form = await req.formData();
  const accessToken = form.get('access_token');
  const productId = form.get('product_id');
  const file = form.get('file');

  if (!accessToken || !productId || !file) {
    return new Response(JSON.stringify({ error: 'access_token, product_id en file zijn verplicht' }), {
      status: 400, headers: CORS_HEADERS
    });
  }

  if (file.type && !TOEGELATEN.includes(file.type)) {
    return new Response(JSON.stringify({ error: 'Enkel een pdf-bestand' }), {
      status: 400, headers: CORS_HEADERS
    });
  }

  // De aanroeper met zijn EIGEN token: wat hij mag zien en wijzigen, bepalen de
  // policies uit 0098. Lukt de select niet, dan hoort dit product niet bij hem.
  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } }
  });

  const { data: product, error: leesErr } = await callerClient
    .from('chemische_producten')
    .select('id,bedrijf_id')
    .eq('id', productId)
    .maybeSingle();

  if (leesErr || !product) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd of onbekend product' }), {
      status: 401, headers: CORS_HEADERS
    });
  }

  // Mag hij ook schrijven? Een lege update op zijn eigen rij is de eerlijkste
  // toets: ze loopt door dezelfde policy als de echte wijziging straks. Een
  // klant-medewerker leest het product wel, maar raakt hier niet voorbij.
  const { error: schrijfErr } = await callerClient
    .from('chemische_producten')
    .update({ bijgewerkt_op: new Date().toISOString() })
    .eq('id', productId)
    .select('id')
    .maybeSingle();

  if (schrijfErr) {
    return new Response(JSON.stringify({ error: 'Geen schrijfrecht op dit product' }), {
      status: 403, headers: CORS_HEADERS
    });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Pad: bedrijf/product.pdf -- twee UUID's, dus niet te raden, en meteen
  // duidelijk van wie het is wanneer je in de opslag kijkt.
  const pad = `${product.bedrijf_id}/${product.id}.pdf`;

  const { error: uploadErr } = await sb.storage
    .from('vib')
    .upload(pad, file, { contentType: 'application/pdf', upsert: true });

  if (uploadErr) {
    return new Response(JSON.stringify({ error: 'Upload mislukt', details: uploadErr.message }), {
      status: 500, headers: CORS_HEADERS
    });
  }

  const { data: publicUrl } = sb.storage.from('vib').getPublicUrl(pad);

  // Cachebuster: het pad blijft gelijk wanneer iemand een nieuwere versie van
  // het blad oplaadt (upsert). Zonder dit zou de browser -- en erger, de app op
  // de vloer -- het oude blad blijven tonen.
  const url = `${publicUrl.publicUrl}?v=${Date.now()}`;

  const { error: bijwerkErr } = await sb
    .from('chemische_producten')
    .update({ vib_url: url })
    .eq('id', product.id);

  if (bijwerkErr) {
    return new Response(JSON.stringify({ error: 'Opslaan van de link mislukt', details: bijwerkErr.message }), {
      status: 500, headers: CORS_HEADERS
    });
  }

  return new Response(JSON.stringify({ url }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
