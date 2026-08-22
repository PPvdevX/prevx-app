-- Pincodes waren platformbreed uniek: rpc_login_chauffeur matchte zonder
-- bedrijfsfilter. Wie een geldige code raadde kwam binnen bij ÉÉN of andere
-- klant, niet noodzakelijk zijn eigen -- de schade van één geraden code was dus
-- je hele klantenbestand. Daarnaast liep je vast op 10.000 gebruikers in
-- totaal, en konden twee klanten niet allebei "1234" gebruiken.
--
-- Vanaf nu identificeert de chauffeur zich met een KLANTCODE + zijn pincode.
-- De klantcode voert hij één keer in; de app onthoudt hem op het toestel.
--
-- ROLLOUT IN TWEE STAPPEN -- belangrijk:
--   Stap 1 (deze migratie): de nieuwe functie rpc_login_chauffeur_klant komt
--     erbij; de oude rpc_login_chauffeur blijft ongemoeid bestaan. Op het moment
--     dat deze migratie draait, hebben chauffeurs immers nog de oude app in hun
--     scherm staan -- die mag niet stilvallen midden in een shift.
--   Stap 2 (migratie 0053, pas nadat de nieuwe app een paar dagen live staat):
--     de oude rpc_login_chauffeur verwijderen. PAS DAN is het gat dicht.
-- Laat stap 2 dus niet liggen: tot dan bestaat de platformbrede ingang nog.

alter table bedrijven add column if not exists klantcode text;

create unique index if not exists idx_bedrijven_klantcode on bedrijven (upper(klantcode));

-- Willekeur uit gen_random_uuid(): dat zit sinds Postgres 13 in de kern en is
-- cryptografisch sterk. Bewust NIET gen_random_bytes() -- dat komt uit de
-- pgcrypto-extensie, die hier niet op het zoekpad staat (en die afhankelijkheid
-- is niet nodig). random() zou wél verkeerd zijn: dat is een per-sessie geseede
-- PRNG, geen bron voor iets dat toegang verleent.
--
-- decode(..., 'hex') en get_byte() zijn eveneens kernfuncties.
create or replace function public.willekeurige_byte()
returns int
language sql
volatile
as $$
  select get_byte(decode(substr(replace(gen_random_uuid()::text, '-', ''), 1, 2), 'hex'), 0);
$$;

-- Postgres geeft EXECUTE standaard aan PUBLIC bij het aanmaken van een functie;
-- intrekken zoals in 0020. De security definer-functies hieronder roepen ze
-- aan als hun eigen eigenaar, dus die blijven werken.
revoke execute on function public.willekeurige_byte() from public;

-- Alfabet zonder verwarrende tekens (geen I/O/0/1), want deze code wordt
-- doorgegeven op papier en door de telefoon.
create or replace function public.genereer_klantcode()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alfabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_poging int := 0;
  i int;
begin
  loop
    v_poging := v_poging + 1;
    if v_poging > 100 then
      raise exception 'Kon geen vrije klantcode genereren';
    end if;

    v_code := '';
    for i in 1..6 loop
      -- 32 tekens in het alfabet en 256 mogelijke bytewaarden: 256 is deelbaar
      -- door 32, dus deze modulo geeft geen vertekening.
      v_code := v_code || substr(v_alfabet, (public.willekeurige_byte() % 32) + 1, 1);
    end loop;

    exit when not exists (select 1 from bedrijven where upper(klantcode) = v_code);
  end loop;

  return v_code;
end;
$$;

-- Zelfde correctie voor de pincodegenerator uit 0051: die is aangemaakt met
-- gen_random_bytes en zou pas gefaald zijn bij de eerste "Reset pincode".
create or replace function public.rpc_genereer_pincode()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_poging int := 0;
begin
  if public.huidig_bedrijf_id() is null and not public.is_superbeheerder() then
    raise exception 'Niet geautoriseerd';
  end if;

  loop
    v_poging := v_poging + 1;
    if v_poging > 200 then
      raise exception 'Geen vrije pincode gevonden; de voorraad van 4 cijfers raakt op.';
    end if;

    -- Twee bytes geven 0..65535; de rest na deling door 10000 is licht
    -- vertekend richting de lage cijfers. Verwaarloosbaar voor een pincode die
    -- toch al maar 4 cijfers heeft, en de lus hieronder vangt botsingen op.
    v_code := lpad(((public.willekeurige_byte() * 256 + public.willekeurige_byte()) % 10000)::text, 4, '0');

    exit when not exists (select 1 from gebruikers where pincode = v_code and actief = true);
  end loop;

  return v_code;
end;
$$;

grant execute on function public.rpc_genereer_pincode() to authenticated;

-- Bestaande bedrijven een code geven.
do $$
declare
  r record;
begin
  for r in select id from bedrijven where klantcode is null loop
    update bedrijven set klantcode = public.genereer_klantcode() where id = r.id;
  end loop;
end;
$$;

-- Nieuwe bedrijven krijgen er automatisch een, net als hun modulerijen (0050).
create or replace function public.zet_standaard_bedrijf_modules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into bedrijf_modules (bedrijf_id, module_key, actief)
  values (new.id, 'preinspecties', true)
  on conflict (bedrijf_id, module_key) do nothing;

  if new.klantcode is null then
    update bedrijven set klantcode = public.genereer_klantcode() where id = new.id;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Klantcode controleren vóór het pincodescherm
-- ---------------------------------------------------------------------------
-- Geeft enkel de bedrijfsnaam terug bij een juiste code, zodat de chauffeur ziet
-- dat hij bij de juiste werkgever zit. Aflopen is onhaalbaar (32^6 ≈ 1 miljard)
-- en valt bovendien onder dezelfde begrenzing als de login (0051).
create or replace function public.rpc_bedrijf_via_klantcode(p_klantcode text)
returns table(bedrijf_id uuid, naam text, logo_url text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
begin
  v_ip := public.verzoek_ip();
  if public.login_begrenzing_overschreden(v_ip, 'klantcode') then
    raise exception 'Te veel pogingen. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
  end if;

  return query
    select b.id, b.naam, b.logo_url
    from bedrijven b
    where upper(b.klantcode) = upper(btrim(p_klantcode))
    limit 1;

  perform public.noteer_login_poging(v_ip, 'klantcode', found, false);
  return;
end;
$$;

grant execute on function public.rpc_bedrijf_via_klantcode(text) to anon;

-- ---------------------------------------------------------------------------
-- Login met klantcode: een APARTE functie, naast de bestaande
-- ---------------------------------------------------------------------------
-- Bewust géén extra parameter op rpc_login_chauffeur met een standaardwaarde.
-- Op het moment dat deze migratie draait, staat er bij chauffeurs nog een app
-- die één argument meestuurt; of PostgREST die dan correct koppelt aan een
-- functie met een default, is gedrag waar ik een live login niet van wil laten
-- afhangen. Een aparte functie maakt de overgang risicoloos:
--
--   nu:            oude app -> rpc_login_chauffeur       (blijft werken)
--                  nieuwe app -> rpc_login_chauffeur_klant
--   migratie 0053: rpc_login_chauffeur verwijderen zodra de nieuwe app
--                  overal draait. PAS DAN is het platformbrede gat dicht.
--
-- Laat die laatste stap niet liggen: tot dan blijft de oude, ongescoopte
-- ingang bestaan.
create or replace function public.rpc_login_chauffeur_klant(p_pincode text, p_klantcode text)
returns table(id uuid, naam text, rol text, bedrijf_id uuid, rol_label text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
  v_bedrijf_id uuid;
begin
  v_ip := public.verzoek_ip();

  if public.login_begrenzing_overschreden(v_ip, 'login') then
    perform public.noteer_login_poging(v_ip, 'login', false, true);
    raise exception 'Te veel mislukte pogingen. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
  end if;

  select b.id into v_bedrijf_id
  from bedrijven b
  where upper(b.klantcode) = upper(btrim(coalesce(p_klantcode, '')))
  limit 1;

  -- Onbekende of ontbrekende klantcode: niets teruggeven. Geen terugval op de
  -- platformbrede match -- dat is precies het gat dat hier dichtgaat.
  if v_bedrijf_id is null then
    perform public.noteer_login_poging(v_ip, 'login', false, false);
    return;
  end if;

  return query
    select g.id, g.naam, g.rol, g.bedrijf_id,
      case g.rol
        when 'chauffeur' then b.rol_label_chauffeur
        when 'leidinggevende' then b.rol_label_leidinggevende
        when 'preventieadviseur' then b.rol_label_preventieadviseur
        when 'beheerder' then b.rol_label_beheerder
      end as rol_label
    from gebruikers g
    join bedrijven b on b.id = g.bedrijf_id
    where g.pincode = p_pincode
      and g.actief = true
      and g.bedrijf_id = v_bedrijf_id
    limit 1;

  perform public.noteer_login_poging(v_ip, 'login', found, false);
  return;
end;
$$;

grant execute on function public.rpc_login_chauffeur_klant(text, text) to anon;
