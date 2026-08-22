-- Pushmeldingen voor de nazorgcontrole na heet werk.
--
-- De herinnering gaat vandaag per e-mail (Edge Function send-nazorg-herinnering).
-- Op een werf werkt dat slecht: de brandwacht kijkt niet in zijn mailbox terwijl
-- hij aan het opruimen is. Push legt het bericht op zijn scherm. De e-mail blijft
-- staan als achtervang naar de verantwoordelijke -- als push faalt of niet
-- aanstaat, mag een nazorgcontrole daar niet stil door wegvallen.
--
-- Deze migratie voegt enkel het kanaal toe. Planning, escalatietermijnen en de
-- regel dat een vergunning pas sluit na twee bevestigde controles (0060) blijven
-- ongewijzigd.

create table if not exists push_abonnementen (
  id uuid primary key default gen_random_uuid(),
  gebruiker_id uuid not null references gebruikers(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  aangemaakt_op timestamptz not null default now(),
  laatst_gelukt_op timestamptz,
  laatste_fout text
);

create index if not exists idx_push_abonnementen_gebruiker on push_abonnementen(gebruiker_id);

-- Fail closed, net als vergunning_goedkeuring_codes (0057): RLS aan, geen enkele
-- policy. Alleen security definer-functies en de service-role van de Edge
-- Function komen erbij. Een endpoint plus zijn sleutels is genoeg om meldingen
-- naar dat toestel te sturen; dat hoort niet leesbaar te zijn via de API.
alter table push_abonnementen enable row level security;
revoke all on push_abonnementen from anon, authenticated;

-- Verwijderen van een bedrijf hoeft hier niets extra te doen: de FK naar
-- gebruikers staat op ON DELETE CASCADE, dus rpc_verwijder_bedrijf_cascade (0064)
-- ruimt deze rijen mee op zodra de gebruikers-rijen weg zijn.

-- ---------------------------------------------------------------------------
-- Abonneren
-- ---------------------------------------------------------------------------
-- Waarom pincode + klantcode en niet gewoon een gebruiker_id: de app heeft geen
-- sessie, dus een RPC die enkel een gebruiker_id vraagt laat iederéén die zo'n
-- id kent zijn eigen toestel onder die persoon inschrijven. Dan krijgt een
-- vreemde de meldingen van een klant op zijn scherm. Daarom dezelfde controle
-- als de login, met dezelfde begrenzing op mislukte pogingen -- in een eigen
-- teller, zodat mislukte abonneerpogingen de login van een werkende chauffeur
-- niet kunnen blokkeren.
--
-- Gevolg voor de app: toestemming vragen moet gebeuren zolang de pincode nog
-- in beeld is, dus meteen na het inloggen.
create or replace function public.rpc_push_abonneren(
  p_pincode text,
  p_klantcode text,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
  v_bedrijf_id uuid;
  v_gebruiker_id uuid;
begin
  v_ip := public.verzoek_ip();

  if public.login_begrenzing_overschreden(v_ip, 'push') then
    perform public.noteer_login_poging(v_ip, 'push', false, true);
    raise exception 'Te veel mislukte pogingen. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
  end if;

  if coalesce(btrim(p_endpoint), '') = ''
     or coalesce(btrim(p_p256dh), '') = ''
     or coalesce(btrim(p_auth), '') = '' then
    raise exception 'Onvolledig abonnement';
  end if;

  select b.id into v_bedrijf_id
  from bedrijven b
  where upper(b.klantcode) = upper(btrim(coalesce(p_klantcode, '')))
  limit 1;

  if v_bedrijf_id is null then
    perform public.noteer_login_poging(v_ip, 'push', false, false);
    return false;
  end if;

  select g.id into v_gebruiker_id
  from gebruikers g
  where g.pincode = p_pincode
    and g.actief = true
    and g.bedrijf_id = v_bedrijf_id
  limit 1;

  perform public.noteer_login_poging(v_ip, 'push', v_gebruiker_id is not null, false);

  if v_gebruiker_id is null then
    return false;
  end if;

  -- Een endpoint is uniek per toestel per installatie. Hetzelfde endpoint dat
  -- opduikt bij een andere gebruiker betekent: gedeeld toestel, iemand anders
  -- is nu ingelogd. Dan hoort het abonnement mee te verhuizen, niet naast het
  -- oude te blijven bestaan -- anders krijgt de vorige gebruiker de meldingen
  -- van zijn opvolger.
  insert into push_abonnementen (gebruiker_id, endpoint, p256dh, auth, user_agent)
  values (v_gebruiker_id, btrim(p_endpoint), btrim(p_p256dh), btrim(p_auth), left(coalesce(p_user_agent, ''), 300))
  on conflict (endpoint) do update set
    gebruiker_id = excluded.gebruiker_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    aangemaakt_op = now(),
    laatste_fout = null;

  return true;
end;
$$;

revoke execute on function public.rpc_push_abonneren(text, text, text, text, text, text) from public;
grant execute on function public.rpc_push_abonneren(text, text, text, text, text, text) to anon;

-- ---------------------------------------------------------------------------
-- Afmelden
-- ---------------------------------------------------------------------------
-- Bewust géén pincode: wie het endpoint kent, heeft het toestel. Afmelden kan
-- alleen maar minder meldingen opleveren, nooit toegang tot iets. Een drempel
-- opwerpen zou enkel betekenen dat een uitgezet abonnement blijft hangen.
create or replace function public.rpc_push_afmelden(p_endpoint text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from push_abonnementen where endpoint = btrim(p_endpoint);
$$;

revoke execute on function public.rpc_push_afmelden(text) from public;
grant execute on function public.rpc_push_afmelden(text) to anon;

-- ---------------------------------------------------------------------------
-- VAPID-sleutels uit Vault
-- ---------------------------------------------------------------------------
-- Zelfde opzet als rpc_webhook_secret (0056): één afgebakende weg per geheim,
-- niet geheim() zelf aan service_role geven. De publieke sleutel staat gewoon
-- in app.html -- die is per definitie niet geheim -- maar wordt hier ook
-- teruggegeven zodat de Edge Function niet met een afwijkende kopie kan werken.
create or replace function public.rpc_vapid_config()
returns table(publieke_sleutel text, prive_sleutel text, onderwerp text)
language sql
stable
security definer
set search_path = public
as $$
  select public.geheim('vapid_public_key'),
         public.geheim('vapid_private_key'),
         coalesce(public.geheim('vapid_subject'), 'mailto:account@prevx.be');
$$;

revoke execute on function public.rpc_vapid_config() from public;
grant execute on function public.rpc_vapid_config() to service_role;
