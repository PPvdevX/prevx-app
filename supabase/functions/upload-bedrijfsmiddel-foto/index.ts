// Supabase Edge Function: uploadt een bedrijfsmiddel-foto naar Storage met de
// service_role-sleutel, om de kapotte gebruikers-JWT-verificatie in de
// Storage-service te omzeilen (dit project gebruikt sinds ~4 maanden ECC/P-256
// als JWT-signing-key; de gewone database-API verwerkt dat correct, Storage
// blijkbaar niet — platform-side incompatibiliteit, geen RLS-/policy-fout).
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt bij deploy), net
// als bij send-inspectie-email/index.ts — de caller wordt hieronder zelf
// geverifieerd via het bewezen-werkende PostgREST/RPC-pad (huidig_bedrijf_id),
// niet via de kapotte Storage-JWT-check.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const ANON_KEY = Deno.env.get('ANON_KEY');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type'
};

Deno.serve(async (req) => {
  // Cross-origin fetch() vanuit portaal.html stuurt eerst een lege OPTIONS-
  // preflight; die heeft geen body/content-type en mag nooit als upload
  // verwerkt worden.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const form = await req.formData();
  const accessToken = form.get('access_token');
  const voertuigId = form.get('voertuig_id');
  const file = form.get('file');

  if (!accessToken || !voertuigId || !file) {
    return new Response(JSON.stringify({ error: 'access_token, voertuig_id en file zijn verplicht' }), { status: 400, headers: CORS_HEADERS });
  }

  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } }
  });
  const { data: bedrijfId, error: bedrijfErr } = await callerClient.rpc('huidig_bedrijf_id');
  if (bedrijfErr || !bedrijfId) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: voertuig, error: voertuigErr } = await sb
    .from('voertuigen')
    .select('id')
    .eq('id', voertuigId)
    .eq('bedrijf_id', bedrijfId)
    .maybeSingle();
  if (voertuigErr || !voertuig) {
    return new Response(JSON.stringify({ error: 'Dit bedrijfsmiddel hoort niet bij uw bedrijf' }), { status: 403, headers: CORS_HEADERS });
  }

  const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
  const pad = `${bedrijfId}/${voertuigId}.${ext}`;

  const { error: uploadErr } = await sb.storage
    .from('bedrijfsmiddel-fotos')
    .upload(pad, file, { contentType: file.type || 'application/octet-stream', upsert: true });
  if (uploadErr) {
    return new Response(JSON.stringify({ error: 'Upload mislukt', details: uploadErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const { data: publicUrl } = sb.storage.from('bedrijfsmiddel-fotos').getPublicUrl(pad);
  return new Response(JSON.stringify({ url: publicUrl.publicUrl }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
