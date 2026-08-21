// Supabase Edge Function: verwittigt PrevX zodra een klant een vraag stelt in
// het portaal. Wordt intern aangeroepen vanuit de trigger op de tabel vragen
// (migratie 0100) via pg_net, niet rechtstreeks vanaf het internet -- vandaar
// dezelfde controle op de gedeelde sleutel uit Vault als bij de andere
// interne functies, en JWT-verificatie van de gateway uit.
//
// Waarom er überhaupt een bericht nodig is: zonder mail ligt een vraag te
// wachten tot iemand toevallig het scherm opent, en dan is schriftelijk vragen
// trager dan bellen. Precies het omgekeerde van wat dit moet oplossen.
//
// De mail gaat naar één adres, niet naar de klant. De klant heeft zijn antwoord
// in het portaal staan; dit bericht is er alleen om PrevX wakker te maken.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const AFZENDER = Deno.env.get('AFZENDER_EMAIL') || 'rapporten@prevx.be';
const ONTVANGER = Deno.env.get('VRAGEN_EMAIL') || 'account@prevx.be';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-webhook-secret'
};

async function isGeautoriseerd(req, sb) {
  const meegestuurd = req.headers.get('x-webhook-secret');
  if (!meegestuurd) return false;

  const { data: verwacht, error } = await sb.rpc('rpc_webhook_secret');
  if (error || !verwacht) {
    console.error('Kon de webhook-sleutel niet uit Vault lezen:', error);
    return false;
  }
  return meegestuurd === verwacht;
}

function veilig(t) {
  return String(t == null ? '' : t)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  if (!(await isGeautoriseerd(req, sb))) {
    return new Response(JSON.stringify({ error: 'Niet geautoriseerd' }), { status: 401, headers: CORS_HEADERS });
  }

  const { vraag_id } = await req.json();
  if (!vraag_id) {
    return new Response(JSON.stringify({ error: 'vraag_id ontbreekt' }), { status: 400, headers: CORS_HEADERS });
  }

  const { data: v, error } = await sb
    .from('vragen')
    .select('vraag, gesteld_door, gesteld_op, bedrijven(naam)')
    .eq('id', vraag_id)
    .maybeSingle();

  if (error || !v) {
    return new Response(JSON.stringify({ error: 'Onbekende vraag' }), { status: 404, headers: CORS_HEADERS });
  }

  const bedrijf = (v.bedrijven && v.bedrijven.naam) || 'een klant';

  // Sober gehouden: dit is een intern bericht, geen klantcommunicatie. De vraag
  // staat er wel volledig in -- zo kan er al over nagedacht worden zonder eerst
  // in te loggen.
  const html = `
    <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#0f1826;line-height:1.6">
      <p style="margin:0 0 14px"><strong>${veilig(bedrijf)}</strong> stelde een vraag in het portaal.</p>
      <blockquote style="margin:0 0 16px;padding:12px 16px;background:#f1f5f9;border-left:3px solid #003366">
        ${veilig(v.vraag).replace(/\n/g, '<br>')}
      </blockquote>
      <p style="margin:0 0 6px;color:#64748b">Gesteld door ${veilig(v.gesteld_door)}</p>
      <p style="margin:0 0 20px;color:#64748b">De klant ziet uw antwoord zodra u het in het portaal invult.</p>
      <a href="https://prevx.be/account" style="display:inline-block;background:#003366;color:#fff;text-decoration:none;padding:10px 18px;border-radius:8px">Openen in Mijn PrevX</a>
    </div>`;

  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: AFZENDER,
      to: [ONTVANGER],
      subject: `Vraag van ${bedrijf}`,
      html
    })
  });

  if (!resp.ok) {
    const details = await resp.text();
    console.error('Resend weigerde de mail:', resp.status, details);
    return new Response(JSON.stringify({ error: 'Verzenden mislukt', status: resp.status }), {
      status: 502, headers: CORS_HEADERS
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' }
  });
});
