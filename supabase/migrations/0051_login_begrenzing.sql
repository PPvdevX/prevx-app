-- rpc_login_chauffeur (0006) kende geen enkele begrenzing op mislukte
-- pogingen: vier cijfers, platformbreed uniek gematcht, aanroepbaar door anon.
-- De volledige sleutelruimte (10.000) was daarmee in minuten af te lopen, en
-- een treffer geeft meteen toegang tot een willekeurige klant. Dat raakt wat
-- vandaag al live staat; met de vuurvergunning-module erachter wordt het
-- ernstiger, want dan hangt er ook een goedkeuringshandeling aan.
--
-- Tweede gat, meteen meegenomen: rpc_pincode_bestaat (0038) geeft voor elke
-- willekeurige pincode true/false terug en is gegrant aan `authenticated`. Een
-- ingelogde portaalgebruiker kon daarmee de hele sleutelruimte aflopen en
-- geldige pincodes van ANDERE klanten vinden -- de match is immers
-- platformbreed. Dezelfde begrenzing geldt nu ook daar.
--
-- Wat dit NIET oplost: een aanvaller die over veel IP-adressen beschikt. De
-- structurele oplossing is een langere code of een pincode die per bedrijf
-- geldt i.p.v. platformbreed; dat is een productbeslissing met gevolgen voor de
-- gebruikers, bewust niet in deze migratie.

create table if not exists login_pogingen (
  id uuid primary key default gen_random_uuid(),
  ip text not null,
  bron text not null default 'login',
  gelukt boolean not null,
  geblokkeerd boolean not null default false,
  tijdstip timestamptz not null default now()
);

create index if not exists idx_login_pogingen_ip_tijd on login_pogingen (ip, tijdstip desc);

alter table login_pogingen enable row level security;

-- Schrijven gebeurt uitsluitend vanuit de security definer-functies hieronder.
-- Enkel de superbeheerder mag meekijken, om een "ik raak niet binnen"-melding
-- te kunnen verklaren.
create policy superbeheerder_select_login_pogingen on login_pogingen for select to authenticated
  using (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- Hulpfuncties
-- ---------------------------------------------------------------------------
-- PostgREST geeft de verzoek-headers door via request.headers. Buiten een
-- HTTP-context (bv. de SQL-editor) bestaat die niet; dan vallen we terug op
-- één gedeelde emmer i.p.v. de begrenzing te laten wegvallen.
create or replace function public.verzoek_ip()
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_headers json;
  v_ip text;
begin
  begin
    v_headers := current_setting('request.headers', true)::json;
  exception when others then
    return 'onbekend';
  end;
  if v_headers is null then
    return 'onbekend';
  end if;

  v_ip := nullif(btrim(coalesce(v_headers ->> 'cf-connecting-ip', '')), '');
  if v_ip is null then
    v_ip := nullif(btrim(split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1)), '');
  end if;
  if v_ip is null then
    v_ip := nullif(btrim(coalesce(v_headers ->> 'x-real-ip', '')), '');
  end if;

  return coalesce(v_ip, 'onbekend');
end;
$$;

-- Tien mislukte pogingen per kwartier per IP. Ruim genoeg voor een chauffeur
-- die zich vertypt of zijn code even kwijt is, en het beperkt één IP tot zo'n
-- 40 gokken per uur -- de volledige sleutelruimte aflopen duurt dan dagen
-- i.p.v. minuten.
create or replace function public.login_begrenzing_overschreden(p_ip text, p_bron text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select count(*) >= 10
  from login_pogingen
  where ip = p_ip and bron = p_bron and gelukt = false
    and tijdstip > now() - interval '15 minutes';
$$;

create or replace function public.noteer_login_poging(p_ip text, p_bron text, p_gelukt boolean, p_geblokkeerd boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into login_pogingen (ip, bron, gelukt, geblokkeerd)
  values (p_ip, p_bron, p_gelukt, p_geblokkeerd);

  -- Af en toe opruimen, zodat hier geen pg_cron voor nodig is.
  if random() < 0.01 then
    delete from login_pogingen where tijdstip < now() - interval '30 days';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- rpc_login_chauffeur met begrenzing
-- ---------------------------------------------------------------------------
-- Argumentenlijst en returntype blijven exact gelijk aan 0042, enkel de taal
-- (sql -> plpgsql) en de body wijzigen. Daarom volstaat create or replace en is
-- er geen drop nodig zoals in 0042/0047.
create or replace function public.rpc_login_chauffeur(p_pincode text)
returns table(id uuid, naam text, rol text, bedrijf_id uuid, rol_label text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
begin
  v_ip := public.verzoek_ip();

  if public.login_begrenzing_overschreden(v_ip, 'login') then
    perform public.noteer_login_poging(v_ip, 'login', false, true);
    raise exception 'Te veel mislukte pogingen. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
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
    where g.pincode = p_pincode and g.actief = true
    limit 1;

  -- FOUND is na "return query" waar zodra er minstens één rij is teruggegeven;
  -- de uitvoering loopt gewoon door, return query beëindigt de functie niet.
  perform public.noteer_login_poging(v_ip, 'login', found, false);
  return;
end;
$$;

grant execute on function public.rpc_login_chauffeur(text) to anon;

-- ---------------------------------------------------------------------------
-- Het orakel rpc_pincode_bestaat wordt afgeschaft
-- ---------------------------------------------------------------------------
-- Die functie gaf voor élke willekeurige pincode true/false terug aan elke
-- ingelogde portaalgebruiker. Daarmee kon een klantbeheerder de volledige
-- sleutelruimte aflopen en geldige pincodes van ANDERE klanten vinden -- de
-- login matcht immers platformbreed. Een begrenzing zou dat enkel vertragen;
-- hier is de vraag zelf het probleem, dus verdwijnt ze.
--
-- In de plaats komen twee functies die hetzelfde doel dienen zonder iets prijs
-- te geven over pincodes die de aanvrager niet al kent.

drop function if exists public.rpc_pincode_bestaat(text);

-- Genereert server-side een vrije pincode. De aanvrager leert niets over
-- andere codes: hij krijgt er één die hij meteen zelf in gebruik neemt.
--
-- LET OP: de versie hieronder gebruikt gen_random_bytes() uit pgcrypto, en die
-- extensie staat op dit project niet op het zoekpad -- de functie wordt wel
-- aangemaakt maar faalt bij de eerste aanroep met "function gen_random_bytes
-- does not exist". Migratie 0052 vervangt ze door een versie die enkel
-- kernfuncties gebruikt. Deze migratie blijft ongewijzigd staan als logboek;
-- niet hier repareren maar 0052 uitvoeren.
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

    -- gen_random_bytes i.p.v. random(): dat laatste is een per-sessie geseede
    -- PRNG en geen veilige bron voor iets dat toegang verleent.
    v_code := lpad(((get_byte(gen_random_bytes(2), 0) * 256 + get_byte(gen_random_bytes(2), 1)) % 10000)::text, 4, '0');

    exit when not exists (select 1 from gebruikers where pincode = v_code and actief = true);
  end loop;

  return v_code;
end;
$$;

grant execute on function public.rpc_genereer_pincode() to authenticated;

-- Voor de voorbeeldweergave bij bulk-import: controleert enkel pincodes die de
-- gebruiker zélf heeft aangeleverd in zijn bestand, in één oproep. Geeft geen
-- losse vragen meer toe, en is begrensd op de omvang van een redelijke import.
create or replace function public.rpc_pincodes_controleren(p_pincodes text[])
returns table(pincode text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
begin
  if public.huidig_bedrijf_id() is null and not public.is_superbeheerder() then
    raise exception 'Niet geautoriseerd';
  end if;

  if array_length(p_pincodes, 1) > 500 then
    raise exception 'Te veel pincodes in één keer (max 500).';
  end if;

  v_ip := public.verzoek_ip();
  if public.login_begrenzing_overschreden(v_ip, 'pincode_check') then
    raise exception 'Te veel controles na elkaar. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
  end if;
  perform public.noteer_login_poging(v_ip, 'pincode_check', false, false);

  return query
    select g.pincode from gebruikers g
    where g.actief = true and g.pincode = any (p_pincodes);
end;
$$;

grant execute on function public.rpc_pincodes_controleren(text[]) to authenticated;
