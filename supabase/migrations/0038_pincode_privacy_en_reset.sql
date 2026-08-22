-- Pincode/e-mail écht afschermen (de vorige "toon"-knop in portaal.html was
-- puur cosmetisch: laadGebruikers() haalde de echte waarden via select('*')
-- gewoon naar de browser, ongeacht de UI) + een veilige zelfbediening-reset
-- voor chauffeurs, die geen Supabase Auth-sessie hebben (auth_user_id blijft
-- voor hen altijd null, zie 0001_gebruikers_auth_link.sql) en dus nooit
-- kunnen "inloggen om hun pincode te bekijken" -- vandaar reset via e-mail,
-- zelfde principe als een wachtwoord-reset.
--
-- rpc_login_chauffeur (0006_driver_rpc_functions.sql) matcht pincodes
-- company-breed (geen bedrijf_id-filter) -- elke nieuwe/gereset pincode moet
-- dus ook company-breed uniek blijven, niet enkel binnen één bedrijf.

create table if not exists pincode_reset_codes (
  id uuid primary key default gen_random_uuid(),
  gebruiker_id uuid not null references gebruikers(id),
  code text not null,
  aangemaakt_op timestamptz not null default now(),
  verloopt_op timestamptz not null,
  gebruikt boolean not null default false
);

alter table pincode_reset_codes enable row level security;
-- Bewust geen policies: enkel de security definer-RPC's hieronder raken deze
-- tabel aan, fail-closed voor anon/authenticated (zelfde patroon als de
-- portaal_gebruikers-Security-Advisor-fix in 0020).

-- Checkt enkel of een pincode al bestaat, zonder ooit een echte waarde terug
-- te geven -- vervangt de blote select('pincode') die de portal vandaag bij
-- bulk-import gebruikt om dubbels te detecteren.
create or replace function public.rpc_pincode_bestaat(p_pincode text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from gebruikers where pincode = p_pincode and actief = true);
$$;

grant execute on function public.rpc_pincode_bestaat(text) to authenticated;

-- Stap 1 van de "pincode vergeten"-flow: matcht op naam + e-mailadres (geen
-- sessie beschikbaar). Geeft bewust enkel true/false terug, nooit het
-- gebruiker_id, zodat er niets lekt tussen aanvraag- en bevestigingsstap.
create or replace function public.rpc_pincode_reset_aanvragen(p_naam text, p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gebruiker_id uuid;
  v_code text;
begin
  select id into v_gebruiker_id
  from gebruikers
  where actief = true
    and lower(trim(naam)) = lower(trim(p_naam))
    and email is not null
    and lower(trim(email)) = lower(trim(p_email))
  limit 1;

  if v_gebruiker_id is null then
    return false;
  end if;

  v_code := lpad(floor(random() * 1000000)::text, 6, '0');

  insert into pincode_reset_codes (gebruiker_id, code, verloopt_op)
  values (v_gebruiker_id, v_code, now() + interval '15 minutes');

  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-pincode-reset-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '<stond hier; sinds migratie 0055 komt de sleutel uit Vault en is deze waarde vervangen>'
    ),
    body := jsonb_build_object('gebruiker_id', v_gebruiker_id, 'code', v_code)
  );

  return true;
end;
$$;

grant execute on function public.rpc_pincode_reset_aanvragen(text, text) to anon;

-- Stap 2: matcht opnieuw op naam + e-mail (i.p.v. een tussentijds id te
-- bewaren aan de client-kant), controleert de meest recente niet-verlopen/
-- niet-gebruikte code, en de company-brede uniciteit van de nieuwe pincode.
create or replace function public.rpc_pincode_reset_bevestigen(
  p_naam text, p_email text, p_code text, p_nieuwe_pincode text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gebruiker_id uuid;
  v_reset_id uuid;
begin
  if not p_nieuwe_pincode ~ '^\d{4}$' then
    raise exception 'Nieuwe pincode moet exact 4 cijfers zijn';
  end if;

  select id into v_gebruiker_id
  from gebruikers
  where actief = true
    and lower(trim(naam)) = lower(trim(p_naam))
    and email is not null
    and lower(trim(email)) = lower(trim(p_email))
  limit 1;

  if v_gebruiker_id is null then
    raise exception 'Geen match gevonden';
  end if;

  select id into v_reset_id
  from pincode_reset_codes
  where gebruiker_id = v_gebruiker_id
    and code = p_code
    and gebruikt = false
    and verloopt_op > now()
  order by aangemaakt_op desc
  limit 1;

  if v_reset_id is null then
    raise exception 'Code is ongeldig of verlopen';
  end if;

  if exists (select 1 from gebruikers where pincode = p_nieuwe_pincode and id <> v_gebruiker_id and actief = true) then
    raise exception 'Deze pincode is al in gebruik, kies een andere';
  end if;

  update gebruikers set pincode = p_nieuwe_pincode where id = v_gebruiker_id;
  update pincode_reset_codes set gebruikt = true where id = v_reset_id;

  return true;
end;
$$;

grant execute on function public.rpc_pincode_reset_bevestigen(text, text, text, text) to anon;
