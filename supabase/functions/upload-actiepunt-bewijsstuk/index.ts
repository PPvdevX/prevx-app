// Supabase Edge Function: uploadt een bewijsstuk (foto/factuur) bij een
// actiepunt naar Storage met de service_role-sleutel, om dezelfde kapotte
// gebruikers-JWT-verificatie in de Storage-service te omzeilen als bij
// upload-bedrijfsmiddel-foto/index.ts (zie die functie voor de volledige
// achtergrond: ECC/P-256 JWT-signing-keys die Storage niet correct verwerkt).
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt bij deploy). De
// caller wordt hieronder zelf geverifieerd via het bewezen-werkende
// PostgREST/RPC-pad (huidig_bedrijf_id). De eigenlijke statusovergang
// (open -> ter_validatie) gebeurt via rpc_actiepunt_bewijs_opladen, met de
// eigen sessie van de aanroeper — zo blijft de validatielogica op één plek.

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
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const form = await req.formData();
  const accessToken = form.get('access_token');
  const actiepuntId = form.get('actiepunt_id');
  const file = form.get('file');

  if (!accessToken || !actiepuntId || !file) {
    return new Response(JSON.stringify({ error: 'access_token, actiepunt_id en file zijn verplicht' }), { status: 400, headers: CORS_HEADERS });
  }

  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } }
  });
  const { data: bedrijfId, error: bedrijfErr } = await callerClient.rpc('huidig_bedrijf_id');
  if (bedrijfErr || !bedrijfId) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: actiepunt, error: actiepuntErr } = await sb
    .from('actiepunten')
    .select('id')
    .eq('id', actiepuntId)
    .eq('bedrijf_id', bedrijfId)
    .maybeSingle();
  if (actiepuntErr || !actiepunt) {
    return new Response(JSON.stringify({ error: 'Dit actiepunt hoort niet bij uw bedrijf' }), { status: 403, headers: CORS_HEADERS });
  }

  const ext = (file.name.split('.').pop() || 'jpg').toLowerCase();
  const pad = `${bedrijfId}/${actiepuntId}.${ext}`;

  const { error: uploadErr } = await sb.storage
    .from('actiepunt-bewijsstukken')
    .upload(pad, file, { contentType: file.type || 'application/octet-stream', upsert: true });
  if (uploadErr) {
    return new Response(JSON.stringify({ error: 'Upload mislukt', details: uploadErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const { data: publicUrl } = sb.storage.from('actiepunt-bewijsstukken').getPublicUrl(pad);

  const { error: rpcErr } = await callerClient.rpc('rpc_actiepunt_bewijs_opladen', {
    p_actiepunt_id: actiepuntId,
    p_bewijsstuk_url: publicUrl.publicUrl
  });
  if (rpcErr) {
    return new Response(JSON.stringify({ error: 'Bewijsstuk-status bijwerken mislukt', details: rpcErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  return new Response(JSON.stringify({ url: publicUrl.publicUrl }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
