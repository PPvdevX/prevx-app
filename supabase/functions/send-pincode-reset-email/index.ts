// Supabase Edge Function: stuurt een pincode-resetcode naar een chauffeur die
// zijn pincode vergeten is. Wordt intern aangeroepen vanuit
// rpc_pincode_reset_aanvragen (via pg_net), niet rechtstreeks vanaf het
// internet -- vandaar de check op een gedeelde sleutel i.p.v. gewone
// JWT-verificatie (die staat voor deze functie uit, zie deploy-instructies
// van send-inspectie-email, zelfde patroon).
//
// Die sleutel komt sinds migratie 0056 uit Vault, niet meer uit een
// functie-geheim: anders moest dezelfde waarde op twee plaatsen staan en viel
// alle mail stil zodra die uit elkaar liepen.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const AFZENDER = Deno.env.get('AFZENDER_EMAIL') || 'rapporten@prevx.be';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

// Faalt de opvraging, dan weigeren we -- fail closed: liever geen mail dan een
// functie die openstaat voor het internet.
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

Deno.serve(async (req) => {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  if (!(await isGeautoriseerd(req, sb))) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const { gebruiker_id, code } = await req.json();
  if (!gebruiker_id || !code) {
    return new Response(JSON.stringify({ error: 'gebruiker_id of code ontbreekt' }), { status: 400 });
  }

  const { data: gebruiker, error: gErr } = await sb
    .from('gebruikers')
    .select('naam,email')
    .eq('id', gebruiker_id)
    .single();
  if (gErr || !gebruiker || !gebruiker.email) {
    return new Response(JSON.stringify({ error: 'Gebruiker niet gevonden of geen e-mailadres' }), { status: 404 });
  }

  const html = `
  <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
    <div style="background:#003366;padding:18px 24px"><span style="color:#fff;font-weight:800;font-size:16px;letter-spacing:0.5px">PINCODE RESETTEN</span></div>
    <div style="padding:20px 24px;color:#334155;font-size:14px">
      <p>Hallo ${gebruiker.naam},</p>
      <p>Je hebt een reset van je pincode aangevraagd voor de PrevX chauffeurs-app. Gebruik onderstaande code (geldig 15 minuten) om een nieuwe pincode in te stellen:</p>
      <div style="font-family:monospace;font-size:28px;font-weight:800;letter-spacing:4px;background:#f1f5f9;padding:14px 20px;border-radius:8px;text-align:center;margin:16px 0">${code}</div>
      <p style="font-size:12px;color:#94a3b8">Heb je dit niet zelf aangevraagd? Dan kan je deze e-mail negeren.</p>
    </div>
  </div>`;

  const emailResp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: AFZENDER,
      to: [gebruiker.email],
      subject: 'Je pincode-resetcode',
      html
    })
  });

  const emailBody = await emailResp.json();
  return new Response(JSON.stringify({ ok: emailResp.ok, resend: emailBody }), {
    status: emailResp.ok ? 200 : 502
  });
});
