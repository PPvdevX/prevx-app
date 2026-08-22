// Supabase Edge Function: stuurt een pushmelding naar alle toestellen van één
// gebruiker. Bewust algemeen gehouden -- de VAPID-sleutels en de omgang met
// dode abonnementen horen op één plaats te staan, niet in elke functie die
// toevallig iets wil melden.
//
// Eerste gebruiker: de beslissing over een vuurvergunning (migratie 0077). De
// nazorgherinnering heeft nog zijn eigen kopie; die kan hier later naartoe.
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt), zoals bij de
// andere functies. De aanroeper wordt geverifieerd met de webhook-sleutel uit
// Vault -- dezelfde weg als send-inspectie-email.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

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
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('send-push crashte:', e && e.stack ? e.stack : e);
    return new Response(JSON.stringify({ error: String((e && e.message) || e) }), { status: 500 });
  }
});

async function verwerk(req) {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  if (!(await isGeautoriseerd(req, sb))) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const { gebruiker_id, titel, tekst, tag, url } = await req.json();
  if (!gebruiker_id || !titel || !tekst) {
    return new Response(JSON.stringify({ error: 'gebruiker_id, titel en tekst zijn verplicht' }), { status: 400 });
  }

  const { data: cfg } = await sb.rpc('rpc_vapid_config');
  const vapid = Array.isArray(cfg) ? cfg[0] : cfg;
  if (!vapid || !vapid.prive_sleutel || !vapid.publieke_sleutel) {
    console.error('VAPID-sleutels ontbreken in Vault; push overgeslagen.');
    return new Response(JSON.stringify({ skipped: 'geen vapid-sleutels' }), { status: 200 });
  }
  webpush.setVapidDetails(vapid.onderwerp, vapid.publieke_sleutel, vapid.prive_sleutel);

  const { data: abos } = await sb
    .from('push_abonnementen')
    .select('id,endpoint,p256dh,auth')
    .eq('gebruiker_id', gebruiker_id);

  if (!abos || !abos.length) {
    // Geen fout: niet iedereen zet meldingen aan. Wel loggen, want "hij kreeg
    // niets" is anders niet te onderscheiden van een kapotte verzending.
    console.log('Geen pushabonnement voor gebruiker', gebruiker_id);
    return new Response(JSON.stringify({ verstuurd: 0, reden: 'geen abonnement' }), { status: 200 });
  }

  const lading = JSON.stringify({ titel, tekst, tag: tag || 'prevx', url: url || '/app' });

  let verstuurd = 0;
  let opgeruimd = 0;
  for (const a of abos) {
    try {
      await webpush.sendNotification(
        { endpoint: a.endpoint, keys: { p256dh: a.p256dh, auth: a.auth } },
        lading
      );
      verstuurd++;
      await sb.from('push_abonnementen')
        .update({ laatst_gelukt_op: new Date().toISOString(), laatste_fout: null }).eq('id', a.id);
    } catch (e) {
      const status = e && e.statusCode;
      // 404/410: de pushdienst kent dit endpoint niet meer -- app verwijderd of
      // meldingen uitgezet. Opruimen, anders blijven we naar een dood toestel
      // sturen.
      if (status === 404 || status === 410) {
        await sb.from('push_abonnementen').delete().eq('id', a.id);
        opgeruimd++;
      } else {
        console.error('Push mislukt voor abonnement', a.id, status, e && e.body ? e.body : String(e));
        await sb.from('push_abonnementen')
          .update({ laatste_fout: String(status || (e && e.message) || e).slice(0, 300) }).eq('id', a.id);
      }
    }
  }

  return new Response(JSON.stringify({ verstuurd, opgeruimd }), { status: 200 });
}
