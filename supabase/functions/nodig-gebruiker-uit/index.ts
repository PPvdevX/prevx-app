// Supabase Edge Function: nodigt een gebruiker uit voor Mijn PrevX.
//
// Maakt het Auth-account aan, legt de koppeling met de gebruikersrij en stuurt
// een uitnodigingsmail waarin de persoon zélf zijn wachtwoord kiest.
//
// Er komt hier bewust nergens een wachtwoord voor. Zou het portaal er een
// instellen, dan kent de beheerder het wachtwoord van zijn klant -- en staat
// het onderweg in een mail of een telefoongesprek. De uitnodigingslink van
// Supabase Auth lost dat op: hij is eenmalig, verloopt, en het wachtwoord
// ontstaat pas in de browser van de ontvanger.
//
// Twee voorwaarden, allebei hier afgedwongen en niet enkel in de knop:
//   - een e-mailadres, anders is er niets om naartoe te sturen;
//   - een dossierrol, anders komt de uitgenodigde in een portaal waar niets
//     voor hem in staat en denkt hij dat het stuk is.
//
// JWT-verificatie van de gateway staat UIT (--no-verify-jwt), zoals bij de
// andere functies hier. De aanroeper wordt zelf geverifieerd, met zijn token.

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const ANON_KEY = Deno.env.get('ANON_KEY');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

// Waar de uitnodigingslink op uitkomt. Moet in Supabase bij Authentication →
// URL Configuration als Redirect URL toegelaten zijn, anders weigert Supabase
// de link en belandt de ontvanger op de standaard-site.
const PORTAAL_URL = 'https://prevx.be/account';

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
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('nodig-gebruiker-uit crashte:', e && e.stack ? e.stack : e);
    return antwoord({ error: String((e && e.message) || e) }, 500);
  }
});

async function verwerk(req) {
  const { gebruiker_id, access_token } = await req.json();
  if (!gebruiker_id || !access_token) {
    return antwoord({ error: 'gebruiker_id en access_token zijn verplicht' }, 400);
  }

  const alsGebruiker = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${access_token}` } }
  });

  const { data: isSuper, error: superErr } = await alsGebruiker.rpc('is_superbeheerder');
  if (superErr || isSuper !== true) {
    return antwoord({ error: 'Niet geautoriseerd' }, 401);
  }

  const dienst = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: g } = await dienst
    .from('gebruikers')
    .select('id,naam,email,dossier_rol,auth_user_id,actief,bedrijf_id')
    .eq('id', gebruiker_id)
    .maybeSingle();

  if (!g) return antwoord({ error: 'Gebruiker niet gevonden' }, 404);
  if (!g.actief) return antwoord({ error: g.naam + ' staat op inactief. Zet de gebruiker eerst actief.' }, 400);
  if (!g.email) return antwoord({ error: g.naam + ' heeft geen e-mailadres. Vul dat eerst in.' }, 400);
  if (!g.dossier_rol) {
    return antwoord({ error: g.naam + ' heeft geen dossierrol. Zonder dossierrol ziet hij niets in het portaal.' }, 400);
  }
  if (g.auth_user_id) {
    return antwoord({ error: g.naam + ' heeft al toegang tot Mijn PrevX.' }, 400);
  }

  const email = g.email.trim().toLowerCase();

  // Bestaat er al een Auth-account op dit adres? Dat gebeurt bij iemand die
  // ooit bij een ander bedrijf stond, of bij een tweede poging nadat de
  // koppeling misliep. Opnieuw uitnodigen faalt dan; koppelen is wat er moet
  // gebeuren.
  const bestaande = await zoekAuthGebruiker(dienst, email);

  let authId;
  let opnieuw = false;

  if (bestaande) {
    // Alleen koppelen als dat account nog nergens aan hangt. Zit het al aan een
    // andere gebruikersrij, dan zou koppelen iemand toegang geven tot het
    // dossier van een ander bedrijf.
    const { data: bezet } = await dienst
      .from('gebruikers')
      .select('id,bedrijf_id')
      .eq('auth_user_id', bestaande.id)
      .maybeSingle();

    if (bezet) {
      return antwoord({
        error: 'Er bestaat al een account op ' + email + ', en het hoort bij een andere gebruiker. Kies een ander adres.'
      }, 409);
    }
    authId = bestaande.id;
    opnieuw = true;
  } else {
    const { data: uitnodiging, error: invErr } = await dienst.auth.admin.inviteUserByEmail(email, {
      redirectTo: PORTAAL_URL,
      data: { naam: g.naam }
    });
    if (invErr) {
      console.error('inviteUserByEmail mislukt voor', email, invErr);
      return antwoord({ error: 'Uitnodiging versturen mislukt: ' + invErr.message }, 500);
    }
    authId = uitnodiging.user.id;
  }

  const { error: koppelErr } = await dienst
    .from('gebruikers')
    .update({ auth_user_id: authId })
    .eq('id', gebruiker_id);

  if (koppelErr) {
    // Het account bestaat nu wel. Dat melden is belangrijker dan het stil
    // opruimen: bij een tweede poging vindt de functie het terug en koppelt ze
    // alsnog, zonder een tweede mail.
    console.error('Koppeling mislukt na aanmaken account', authId, koppelErr);
    return antwoord({
      ok: false,
      waarschuwing: 'Het account is aangemaakt, maar de koppeling niet gelegd: ' + koppelErr.message +
        ' Probeer opnieuw uit te nodigen; er gaat geen tweede mail uit.'
    }, 500);
  }

  if (opnieuw) {
    // Er bestond al een account, dus er ging geen uitnodiging uit. Zonder
    // herstelmail zou de persoon niet weten dat hij nu toegang heeft.
    // resetPasswordForEmail en niet admin.generateLink: die laatste geeft een
    // link terug maar verstuurt niets, en dan komt er nooit een mail aan.
    const publiek = createClient(SUPABASE_URL, ANON_KEY);
    const { error: resetErr } = await publiek.auth.resetPasswordForEmail(email, { redirectTo: PORTAAL_URL });
    if (resetErr) console.error('Herstelmail mislukt voor', email, resetErr);
  }

  return antwoord({
    ok: true,
    naam: g.naam,
    email: email,
    gekoppeld_aan_bestaand_account: opnieuw
  }, 200);
}

// De admin-API kent geen "zoek op e-mail"; listUsers pagineert. Bij deze
// aantallen is doorbladeren prima, met een hard plafond zodat een fout in de
// paginering geen eindeloze lus wordt.
async function zoekAuthGebruiker(dienst, email) {
  for (let pagina = 1; pagina <= 20; pagina++) {
    const { data, error } = await dienst.auth.admin.listUsers({ page: pagina, perPage: 200 });
    if (error) throw error;
    const treffer = (data.users || []).find(u => (u.email || '').toLowerCase() === email);
    if (treffer) return treffer;
    if (!data.users || data.users.length < 200) return null;
  }
  return null;
}
