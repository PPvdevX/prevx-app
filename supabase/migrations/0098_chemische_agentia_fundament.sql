-- ===========================================================================
-- 0098_chemische_agentia_fundament.sql
-- De inventaris van gevaarlijke producten, en wat het systeem eruit afleidt
-- ===========================================================================
-- Vierde module, en de eerste die niet over een handeling gaat (een inspectie,
-- een vergunning, een LMRA) maar over een voorraad: welke producten staan er,
-- wat zit erin, en waar.
--
-- WAAROM DIT MEER IS DAN EEN LIJST
-- Een productlijst op zich is een spreadsheet met een databank eronder. De
-- waarde zit in twee dingen die een map in het rek niet kan:
--
--   1. Het systeem leidt zelf af of een product onder titel 2 van boek VI valt
--      -- het strengere regime. Dat oordeel hoeft dan niet elke keer opnieuw
--      geveld te worden door wie toevallig kijkt.
--   2. Het veiligheidsinformatieblad hangt aan het product en is op de vloer
--      te openen, op de gsm, terwijl iemand met de bus in zijn hand staat.
--
-- HOE HET SYSTEEM DAT OORDEEL VELT -- en waarom niet met pictogrammen
-- Nagelezen bij FOD WASO (21 aug 2026): of iets onder titel 2 valt, blijkt uit
-- het etiket en het VIB via de GEVARENAANDUIDING, niet uit het pictogram.
-- Datzelfde doodshoofd-op-torso staat namelijk ook op producten met andere
-- gezondheidsschade. De H-zin geeft uitsluitsel:
--
--   H340  mutageen 1A/1B      kan genetische schade veroorzaken
--   H350  kankerverwekkend 1A/1B
--   H360  reprotoxisch 1A/1B  vruchtbaarheid of ongeboren kind
--   EUH380 / EUH381           hormoonontregelaar categorie 1 / 2
--
-- Let op het onderscheid met categorie 2: H341, H351 en H361 ("verdacht van")
-- vallen NIET onder titel 2, wel onder titel 1. Eén cijfer verschil in de code,
-- een heel ander regime. Precies daarom hoort die toets in de databank en niet
-- in het hoofd van wie het formulier invult.
--
-- Hormoonontregelaars hebben nog GEEN pictogram. Een module die op pictogrammen
-- leunt, mist die categorie volledig -- de nieuwste en de minst bekende.
--
-- GRENSWAARDEN STAAN HIER NIET IN, EN DAT IS EEN KEUZE
-- Het KB van 25 mei 2026 (BS 3 juni) verlaagde de grenswaarden voor lood en
-- diisocyanaten, en verlaagt diezelfde waarden opnieuw op 1 januari 2029. Een
-- getal per stof zou dus drie jaar lang fout staan en daar niets over zeggen.
-- Wie grenswaarden wil, bouwt ze zoals keuringen: een waarde met een
-- geldigheidsdatum. Dat is een eigen migratie waard, niet een kolom hier.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. De codelijst met gevarenaanduidingen
-- ---------------------------------------------------------------------------
-- Platformbreed, zoals keuring_types en lmra_risicos: de betekenis van H350 is
-- bij elke klant dezelfde.
--
-- BEWUST MAAR VIJF RIJEN GESEED. Dit zijn de vijf waarvan ik de officiële
-- formulering letterlijk heb nagelezen bij FOD WASO. De andere honderd H-zinnen
-- ken ik uit het hoofd, en dat is precies niet goed genoeg voor tekst die in een
-- klantdossier belandt. Vul aan via Codelijsten; het scherm toont een code
-- waarvan de tekst nog ontbreekt gewoon als code, en dat is eerlijker dan een
-- vertaling die er net naast zit.
create table if not exists gevaarzinnen (
  code text primary key,
  tekst text not null,
  -- true = deze aanduiding brengt het product onder titel 2 van boek VI.
  -- Enkel de categorieën 1A/1B en de twee EUH-codes voor hormoonontregelaars.
  titel2 boolean not null default false,
  volgorde int not null default 0,
  actief boolean not null default true
);

alter table gevaarzinnen enable row level security;

create policy select_gevaarzinnen on gevaarzinnen
  for select to authenticated using (true);

create policy superbeheerder_schrijf_gevaarzinnen on gevaarzinnen
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

insert into gevaarzinnen (code, tekst, titel2, volgorde) values
  ('H340',   'Kan genetische schade veroorzaken', true, 10),
  ('H350',   'Kan kanker veroorzaken', true, 20),
  ('H360',   'Kan de vruchtbaarheid of het ongeboren kind schaden', true, 30),
  ('EUH380', 'Kan hormoonontregeling bij de mens veroorzaken', true, 40),
  ('EUH381', 'Wordt ervan verdacht hormoonontregeling bij de mens te veroorzaken', true, 50)
on conflict (code) do nothing;


-- ---------------------------------------------------------------------------
-- 2. Valt dit product onder titel 2?
-- ---------------------------------------------------------------------------
-- Immutable, want ze wordt hieronder in een gegenereerde kolom gebruikt: het
-- antwoord mag enkel van de meegegeven codes afhangen, van niets anders.
--
-- Daarom staat de lijst hier letterlijk en niet als een select op gevaarzinnen.
-- Dat is dubbel, en dat is de bedoeling: een gegenereerde kolom die naar een
-- andere tabel kijkt, laat Postgres niet toe -- en terecht, want dan zou het
-- oordeel over een product stilletjes veranderen wanneer iemand een codelijst
-- aanpast. De vlag titel2 in gevaarzinnen dient om het in een scherm te tonen;
-- deze functie beslist.
--
-- H350i (kankerverwekkend bij inademing) en de varianten van H360 (H360F, H360D,
-- H360FD, H360Fd, H360Df) horen er ook bij; vandaar de prefixvergelijking in
-- plaats van gelijkheid. H341, H351 en H361 -- categorie 2, "verdacht van" --
-- mogen er juist NIET onder vallen, en die beginnen met een andere code.
create or replace function public.valt_onder_titel2(p_codes text[])
returns boolean
language sql
immutable
as $$
  select coalesce(bool_or(
    upper(btrim(c)) like 'H340%'
    or upper(btrim(c)) like 'H350%'
    or upper(btrim(c)) like 'H360%'
    or upper(btrim(c)) in ('EUH380', 'EUH381')
  ), false)
  from unnest(coalesce(p_codes, '{}'::text[])) as c;
$$;

comment on function public.valt_onder_titel2(text[]) is
  'Bepaalt uit de gevarenaanduidingen of een product onder titel 2 van boek VI van de codex valt (kankerverwekkend, mutageen of reprotoxisch 1A/1B, of hormoonontregelaar). Categorie 2 -- H341, H351, H361 -- valt er bewust buiten.';


-- ---------------------------------------------------------------------------
-- 3. De producten van één klant
-- ---------------------------------------------------------------------------
create table if not exists chemische_producten (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),

  naam text not null,
  leverancier text,
  -- Waarvoor het gebruikt wordt. Niet het procedé in wettelijke zin, wel wat
  -- iemand op de vloer zegt: "ontvetten voor het lassen".
  toepassing text,
  locatie text,
  hoeveelheid text,

  -- De gevarenaanduidingen van het etiket / VIB rubriek 2. Codes, geen zinnen:
  -- de tekst hangt in gevaarzinnen en kan aangevuld worden zonder dat er aan de
  -- producten geraakt wordt.
  h_zinnen text[] not null default '{}',
  -- Enkel om te tonen. GHS01..GHS09. Het oordeel hangt aan de H-zinnen.
  pictogrammen text[] not null default '{}',

  -- Het veiligheidsinformatieblad zelf, plus de datum die er op rubriek 16 van
  -- staat. Niet de uploaddatum: een blad van 2018 dat vorige week geüpload werd,
  -- is nog altijd een blad van 2018.
  vib_url text,
  vib_datum date,

  opmerking text,
  actief boolean not null default true,

  toegevoegd_door text,
  aangemaakt_op timestamptz not null default now(),
  bijgewerkt_op timestamptz not null default now(),

  -- Het oordeel staat opgeslagen, niet berekend bij het tonen. Zo kan je erop
  -- filteren en sorteren, en blijft het staan zoals het gold.
  onder_titel2 boolean generated always as (public.valt_onder_titel2(h_zinnen)) stored,

  constraint naam_niet_leeg check (btrim(naam) <> '')
);

create index if not exists idx_chemische_producten_bedrijf
  on chemische_producten (bedrijf_id) where actief;

-- Zoeken op naam gebeurt op de vloer, op een gsm, met halve woorden.
create index if not exists idx_chemische_producten_naam
  on chemische_producten (bedrijf_id, lower(naam));

alter table chemische_producten enable row level security;

create policy portal_select_chemische_producten on chemische_producten
  for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

-- Schrijven volgt de lijn van 0092: PrevX, of de klant-beheerder van dat
-- bedrijf. Een productlijst die enkel de adviseur kan bijwerken, veroudert
-- tussen twee bezoeken door -- en dan is ze erger dan geen lijst, want ze wekt
-- vertrouwen dat ze niet verdient.
create policy beheer_insert_chemische_producten on chemische_producten
  for insert to authenticated
  with check (
    public.is_superbeheerder()
    or (bedrijf_id = public.huidig_bedrijf_id() and public.is_klant_beheerder())
  );

create policy beheer_update_chemische_producten on chemische_producten
  for update to authenticated
  using (
    public.is_superbeheerder()
    or (bedrijf_id = public.huidig_bedrijf_id() and public.is_klant_beheerder())
  )
  with check (
    public.is_superbeheerder()
    or (bedrijf_id = public.huidig_bedrijf_id() and public.is_klant_beheerder())
  );

-- Definitief wissen blijft bij PrevX, zoals bij assets (0040) en gebruikers
-- (0092). Een product dat niet meer gebruikt wordt, zet je op inactief: dat het
-- er ooit stond, is zelf informatie -- zeker bij een stof onder titel 2.
create policy superbeheerder_delete_chemische_producten on chemische_producten
  for delete to authenticated
  using (public.is_superbeheerder());

create or replace function public.zet_chemisch_product_bijgewerkt()
returns trigger
language plpgsql
as $$
begin
  new.bijgewerkt_op := now();
  return new;
end;
$$;

drop trigger if exists trg_chemisch_product_bijgewerkt on chemische_producten;
create trigger trg_chemisch_product_bijgewerkt
  before update on chemische_producten
  for each row execute function public.zet_chemisch_product_bijgewerkt();


-- ---------------------------------------------------------------------------
-- 4. De module zelf
-- ---------------------------------------------------------------------------
-- in_app = true: dit is de eerste dossiermodule die óók op de vloer staat. De
-- app toont enkel opzoeken en het VIB openen; beheren gebeurt in het portaal.
insert into modules (key, naam, volgorde, actief, in_app)
values ('chemie', 'Chemische agentia', 90, true, true)
on conflict (key) do update set naam = excluded.naam, in_app = true;


-- ---------------------------------------------------------------------------
-- 5. Wat de app mag opvragen
-- ---------------------------------------------------------------------------
-- Zelfde patroon als de rest van de chauffeurs-app: geen sessie, dus geen
-- tabeltoegang, wel security definer-functies die zelf de koppeling
-- gebruiker -> bedrijf verifiëren.
create or replace function public.rpc_chemie_zoek(p_gebruiker_id uuid, p_zoek text)
returns table(
  id uuid, naam text, leverancier text, locatie text,
  h_zinnen text[], pictogrammen text[], onder_titel2 boolean, heeft_vib boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf uuid;
begin
  select bedrijf_id into v_bedrijf
  from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf is null then
    return;
  end if;

  return query
    select p.id, p.naam, p.leverancier, p.locatie,
           p.h_zinnen, p.pictogrammen, p.onder_titel2, (p.vib_url is not null)
    from chemische_producten p
    where p.bedrijf_id = v_bedrijf
      and p.actief
      and (
        coalesce(btrim(p_zoek), '') = ''
        or lower(p.naam) like '%' || lower(btrim(p_zoek)) || '%'
        or lower(coalesce(p.leverancier, '')) like '%' || lower(btrim(p_zoek)) || '%'
      )
    order by p.naam
    limit 100;
end;
$$;

grant execute on function public.rpc_chemie_zoek(uuid, text) to anon, authenticated;

-- Eén product, met de tekst bij de codes. De app toont die tekst; ontbreekt ze
-- in de codelijst, dan blijft de code staan.
create or replace function public.rpc_chemie_product(p_gebruiker_id uuid, p_product_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf uuid;
  v_p record;
begin
  select bedrijf_id into v_bedrijf
  from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  select * into v_p from chemische_producten
  where id = p_product_id and bedrijf_id = v_bedrijf and actief;
  if not found then
    raise exception 'Onbekend product';
  end if;

  return jsonb_build_object(
    'id', v_p.id,
    'naam', v_p.naam,
    'leverancier', v_p.leverancier,
    'toepassing', v_p.toepassing,
    'locatie', v_p.locatie,
    'hoeveelheid', v_p.hoeveelheid,
    'pictogrammen', to_jsonb(v_p.pictogrammen),
    'onder_titel2', v_p.onder_titel2,
    'vib_url', v_p.vib_url,
    'vib_datum', v_p.vib_datum,
    'opmerking', v_p.opmerking,
    -- left join, geen join: een code waarvan de tekst nog niet in de codelijst
    -- staat, moet gewoon als code verschijnen. Weglaten zou erger zijn -- dan
    -- toont de app een product als ongevaarlijk omdat wij een zin missen.
    'gevaren', coalesce((
      select jsonb_agg(jsonb_build_object('code', t.code, 'tekst', g.tekst,
                                          'titel2', coalesce(g.titel2, false))
             order by t.code)
      from unnest(v_p.h_zinnen) as t(code)
      left join gevaarzinnen g on g.code = upper(btrim(t.code))
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.rpc_chemie_product(uuid, uuid) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 6. Meenemen in het verwijderen van een bedrijf
-- ---------------------------------------------------------------------------
-- Eén regel erbij in de cascade van 0082; de rest is ongewijzigd. Vergeten we
-- dit, dan blijft een verwijderd bedrijf achter met zijn productlijst en faalt
-- de cascade op de foreign key.
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_ids uuid[];
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  select coalesce(array_agg(g.auth_user_id), '{}')
    into v_auth_ids
  from gebruikers g
  where g.bedrijf_id = p_bedrijf_id and g.auth_user_id is not null;

  delete from vergunning_herinneringen
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_goedkeuring_codes
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_antwoorden
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vuurvergunningen where bedrijf_id = p_bedrijf_id;
  delete from vergunning_nummers where bedrijf_id = p_bedrijf_id;

  delete from vergunning_vraag_werktypes
    where vraag_id in (select id from vergunning_vragen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_vragen where bedrijf_id = p_bedrijf_id;
  delete from werktypes where bedrijf_id = p_bedrijf_id;

  delete from pincode_reset_codes
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id);

  delete from inspectie_resultaten
    where inspectie_id in (select id from inspecties where bedrijf_id = p_bedrijf_id);
  delete from inspecties where bedrijf_id = p_bedrijf_id;

  delete from inspectie_punt_types
    where punt_id in (
      select p.id from inspectie_punten p
      join inspectie_secties s on s.id = p.sectie_id
      where s.bedrijf_id = p_bedrijf_id);
  delete from inspectie_sectie_types
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from samenwerking where bedrijf_id = p_bedrijf_id;
  delete from lmra_risico_antwoorden
    where lmra_id in (select id from lmras where bedrijf_id = p_bedrijf_id);
  delete from lmras where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_lmra_risicos where bedrijf_id = p_bedrijf_id;
  delete from chemische_producten where bedrijf_id = p_bedrijf_id;
  delete from keuringen where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from document_nummers where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from brandpreventie_status where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;

  if array_length(v_auth_ids, 1) is not null then
    delete from auth.users where id = any (v_auth_ids);
  end if;
end;
$$;

revoke execute on function public.rpc_verwijder_bedrijf_cascade(uuid) from public;
grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 7. Korte controle
-- ---------------------------------------------------------------------------
do $$
begin
  raise notice 'Module chemie aangemaakt. Toets op titel 2:';
  raise notice '  H315 (huidirritatie)          -> %', public.valt_onder_titel2(array['H315']);
  raise notice '  H351 (verdacht, categorie 2)  -> %', public.valt_onder_titel2(array['H351']);
  raise notice '  H350 (kankerverwekkend 1A/1B) -> %', public.valt_onder_titel2(array['H350']);
  raise notice '  H360FD                        -> %', public.valt_onder_titel2(array['H360FD']);
  raise notice '  EUH380 (hormoonontregelaar)   -> %', public.valt_onder_titel2(array['EUH380']);
  raise notice ' ';
  raise notice 'De codelijst gevaarzinnen bevat nu % rijen -- enkel de vijf die titel 2 bepalen.', (select count(*) from gevaarzinnen);
  raise notice 'Vul de overige H-zinnen aan in Codelijsten wanneer je hun officiele tekst bij de hand hebt.';
end
$$;
