// Supabase Edge Function: uploadt een document (RIS/ADV/AUD_RPT/GPP/JAP) naar
// Storage met de service_role-sleutel, om dezelfde kapotte gebruikers-JWT-
// verificatie in de Storage-service te omzeilen als bij de vorige
// upload-functies (zie upload-bedrijfsmiddel-foto/index.ts voor de volledige
// achtergrond).
//
// Verschil t.o.v. de vorige twee upload-functies: enkel de Superbeheerder mag
// hier uploaden (niet gebonden aan één bedrijf), dus de caller wordt
// geverifieerd via is_superbeheerder() i.p.v. huidig_bedrijf_id(), en
// bedrijf_id wordt expliciet door de client meegegeven.
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
  const bedrijfId = form.get('bedrijf_id');
  const type = form.get('type');
  const titel = form.get('titel');
  const versie = form.get('versie');
  const file = form.get('file');

  if (!accessToken || !bedrijfId || !type || !titel || !file) {
    return new Response(JSON.stringify({ error: 'access_token, bedrijf_id, type, titel en file zijn verplicht' }), { status: 400, headers: CORS_HEADERS });
  }

  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } }
  });
  const { data: isSuperbeheerder, error: authErr } = await callerClient.rpc('is_superbeheerder');
  if (authErr || isSuperbeheerder !== true) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Documentcode volgens PX-ADM-PRO-001, met de klantcode ervoor:
  // EU3T8U-PX-RPT-001. De teller zit in de databank (volgend_documentcode) en
  // niet hier -- twee gelijktijdige uploads zouden anders hetzelfde nummer
  // krijgen, en een dossier met twee keer PX-RPT-014 is geen dossier meer.
  const { data: code, error: codeErr } = await sb.rpc('volgend_documentcode', {
    p_bedrijf_id: bedrijfId,
    p_type: type
  });
  if (codeErr) {
    return new Response(JSON.stringify({ error: 'Code aanmaken mislukt', details: codeErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const { data: doc, error: insertErr } = await sb
    .from('documenten')
    .insert({ bedrijf_id: bedrijfId, type, titel, versie: versie || null, code })
    .select()
    .single();
  if (insertErr) {
    return new Response(JSON.stringify({ error: 'Aanmaken mislukt', details: insertErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const ext = (file.name.split('.').pop() || 'pdf').toLowerCase();
  const pad = `${bedrijfId}/${doc.id}.${ext}`;

  const { error: uploadErr } = await sb.storage
    .from('documenten')
    .upload(pad, file, { contentType: file.type || 'application/octet-stream', upsert: true });
  if (uploadErr) {
    return new Response(JSON.stringify({ error: 'Upload mislukt', details: uploadErr.message }), { status: 500, headers: CORS_HEADERS });
  }

  const { data: publicUrl } = sb.storage.from('documenten').getPublicUrl(pad);
  await sb.from('documenten').update({ bestand_url: publicUrl.publicUrl }).eq('id', doc.id);

  return new Response(JSON.stringify({ url: publicUrl.publicUrl, id: doc.id }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
