// Supabase Edge Function: voegt een nieuw item toe aan de gedeelde
// Kennisbank-bibliotheek, met de service_role-sleutel om de kapotte
// gebruikers-JWT-verificatie in Storage te omzeilen (zie
// upload-bedrijfsmiddel-foto/index.ts voor de volledige achtergrond).
//
// Enkel de Superbeheerder mag dit -- geen bedrijf_id in het pad, want dit is
// gedeelde content, nog niet aan een specifiek bedrijf toegewezen.
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const form = await req.formData();
  const accessToken = form.get('access_token');
  const titel = form.get('titel');
  const categorie = form.get('categorie');
  const file = form.get('file');

  if (!accessToken || !titel || !file) {
    return new Response(JSON.stringify({ error: 'access_token, titel en file zijn verplicht' }), { status: 400, headers: CORS_HEADERS });
  }

  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } }
  });
  const { data: isSuperbeheerder, error: authErr } = await callerClient.rpc('is_superbeheerder');
  if (authErr || isSuperbeheerder !== true) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: item, error: insertErr } = await sb
    .from('kennisbank_items')
    .insert({ titel, categorie: categorie || null })
    .select()
    .single();
  if (insertErr) {
    return new Response(JSON.stringify({ error: 'Aanmaken mislukt', details: insertErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const ext = (file.name.split('.').pop() || 'pdf').toLowerCase();
  const pad = `${item.id}.${ext}`;

  const { error: uploadErr } = await sb.storage
    .from('kennisbank')
    .upload(pad, file, { contentType: file.type || 'application/octet-stream', upsert: true });
  if (uploadErr) {
    return new Response(JSON.stringify({ error: 'Upload mislukt', details: uploadErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const { data: publicUrl } = sb.storage.from('kennisbank').getPublicUrl(pad);
  await sb.from('kennisbank_items').update({ bestand_url: publicUrl.publicUrl }).eq('id', item.id);

  return new Response(JSON.stringify({ url: publicUrl.publicUrl, id: item.id }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
