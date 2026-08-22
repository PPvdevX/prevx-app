// Supabase Edge Function: uploadt een foto of handtekening vanuit de
// chauffeurs-app (index.html) naar Storage met de service_role-sleutel,
// zelfde patroon als de andere upload-functies (zie
// upload-bedrijfsmiddel-foto/index.ts voor de volledige achtergrond).
//
// Verschil met de portaal-upload-functies: de chauffeurs-app heeft GEEN
// Supabase Auth-sessie (enkel PIN-login via rpc_login_chauffeur), dus er is
// geen access_token om mee te verifiëren. Verificatie loopt hier via
// gebruiker_id zelf -- dezelfde vertrouwensgrens als de bestaande
// chauffeurs-RPC's (rpc_voertuigen, rpc_checklist, rpc_verzend_inspectie):
// een geldig gebruiker_id bewijst een geslaagde PIN-login eerder in de sessie.
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt bij deploy).

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type'
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const form = await req.formData();
  const gebruikerId = form.get('gebruiker_id');
  const file = form.get('file');

  if (!gebruikerId || !file) {
    return new Response(JSON.stringify({ error: 'gebruiker_id en file zijn verplicht' }), { status: 400, headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: gebruiker, error: gebruikerErr } = await sb
    .from('gebruikers')
    .select('bedrijf_id')
    .eq('id', gebruikerId)
    .eq('actief', true)
    .maybeSingle();
  if (gebruikerErr || !gebruiker) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
  const pad = `${gebruiker.bedrijf_id}/${crypto.randomUUID()}.${ext}`;

  const { error: uploadErr } = await sb.storage
    .from('inspectie-media')
    .upload(pad, file, { contentType: file.type || 'application/octet-stream', upsert: true });
  if (uploadErr) {
    return new Response(JSON.stringify({ error: 'Upload mislukt', details: uploadErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const { data: publicUrl } = sb.storage.from('inspectie-media').getPublicUrl(pad);
  return new Response(JSON.stringify({ url: publicUrl.publicUrl }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
