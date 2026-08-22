-- LMRA: laatste-minuut-risicoanalyse, de derde module naast pre-inspectie en
-- vuurvergunning.
--
-- Waar de andere twee over een asset of over een vergunning gaan, gaat deze over
-- de taak zelf -- en daarmee over iedereen die iets uitvoert. Dat maakt hem
-- commercieel de sterkste van de drie: pre-inspectie is dagelijks voor wie een
-- machine bedient, een vuurvergunning is af en toe, een LMRA is dagelijks voor
-- iedereen.
--
-- HET ONTWERPPROBLEEM, EN WAAROM HET HIER IN DE TABELLEN ZIT:
--
-- Van alle veiligheidsinstrumenten is de LMRA het gemakkelijkst tot afvinken te
-- herleiden. Hij duurt een minuut en gebeurt meermaals per dag. Wordt het vijf
-- tikjes, dan krijg je vijf tikjes -- en dan is het resultaat ERGER dan papier,
-- want je produceert een overtuigend bewijsstuk van nadenken dat niet gebeurd is.
-- Drie keuzes in dit model werken daartegen:
--
--   1. `eigen_vaststelling` en `foto_url` -- er moet altijd iets van de gebruiker
--      zelf bij. Een foto van de werkplek kan je niet maken waar je niet staat.
--   2. `gestart_op` en `afgerond_op` -- de duur wordt gemeten. Een LMRA van vier
--      seconden is geen LMRA, en de Rapportages-tab herkent zulke patronen al
--      voor pre-inspecties.
--   3. `soort` -- de eerste van de dag is volledig, daarna volstaat een korte
--      bevestiging zolang dezelfde persoon hetzelfde werk op dezelfde plek doet.
--      Zonder dat onderscheid wordt de tiende van de dag even lang als de eerste,
--      en dan klikt iedereen alles weg.
--
-- STOPPEN IS HET HART VAN DE MODULE. Een LMRA bestaat om iemand toestemming te
-- geven om NIET te beginnen. Daarom mag wie stopt ook zelf hervatten: elke
-- drempel op stoppen is een reden om niet te stoppen, en een procedure die het
-- gedrag onderdrukt dat ze moet aanmoedigen is erger dan geen procedure. Wat we
-- wel vragen is `hervat_reden` -- zeggen wat er veranderd is kost vijf seconden
-- en levert een eerlijker spoor op dan een vrijgave die iemand van op afstand
-- aanklikt zonder gekeken te hebben.

-- ---------------------------------------------------------------------------
-- 1. Risicobibliotheek: gedeeld, met een keuze per klant
-- ---------------------------------------------------------------------------
-- Zelfde opzet als de kennisbank (0025): een gedeelde lijst die de superbeheerder
-- beheert, en per klant welke ervan gelden. Zou elke klant zijn eigen lijst
-- krijgen, dan onderhoud je hem twintig keer; zou iedereen alles zien, dan wordt
-- de LMRA een lijst van veertig vinkjes en haalt niemand die halve minuut.

create table if not exists lmra_risicos (
  id uuid primary key default gen_random_uuid(),
  naam text not null,
  categorie text,
  toelichting text,
  volgorde int not null default 0,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now(),
  unique (naam)
);

create table if not exists bedrijf_lmra_risicos (
  bedrijf_id uuid not null references bedrijven(id),
  risico_id uuid not null references lmra_risicos(id) on delete cascade,
  primary key (bedrijf_id, risico_id)
);

alter table lmra_risicos enable row level security;
alter table bedrijf_lmra_risicos enable row level security;

create policy select_lmra_risicos on lmra_risicos for select to authenticated
  using (true);
create policy superbeheerder_insert_lmra_risicos on lmra_risicos for insert to authenticated
  with check (public.is_superbeheerder());
create policy superbeheerder_update_lmra_risicos on lmra_risicos for update to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());

create policy portal_select_bedrijf_lmra_risicos on bedrijf_lmra_risicos for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());
create policy superbeheerder_alles_bedrijf_lmra_risicos on bedrijf_lmra_risicos for all to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- 2. De LMRA zelf
-- ---------------------------------------------------------------------------
create table if not exists lmras (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  gebruiker_id uuid not null references gebruikers(id),
  taak text not null,
  locatie text not null,
  -- Optioneel: soms hoort de taak bij een machine of voertuig, vaak niet.
  -- Zelfde afweging als bij keuringen (0073).
  voertuig_id uuid references voertuigen(id) on delete set null,
  soort text not null default 'volledig' check (soort in ('volledig','bevestiging')),
  status text not null default 'veilig' check (status in ('veilig','gestopt')),
  eigen_vaststelling text,
  foto_url text,
  stop_reden text,
  hervat_op timestamptz,
  hervat_reden text,
  gestart_op timestamptz not null default now(),
  afgerond_op timestamptz,
  -- Een gestopte LMRA hoort een reden te hebben, en een hervatting hoort te
  -- zeggen wat er veranderd is. In de databank, niet alleen in de app: anders
  -- staat er over een jaar "gestopt" zonder dat iemand nog weet waarom.
  check (status <> 'gestopt' or btrim(coalesce(stop_reden,'')) <> ''),
  check (hervat_op is null or btrim(coalesce(hervat_reden,'')) <> '')
);

create index if not exists idx_lmras_bedrijf_tijd on lmras (bedrijf_id, gestart_op desc);
create index if not exists idx_lmras_gebruiker on lmras (gebruiker_id, gestart_op desc);

create table if not exists lmra_risico_antwoorden (
  id uuid primary key default gen_random_uuid(),
  lmra_id uuid not null references lmras(id) on delete cascade,
  risico_id uuid not null references lmra_risicos(id),
  in_orde boolean not null,
  opmerking text,
  -- Wie een risico als niet in orde aanduidt, moet zeggen wat er aan de hand is.
  check (in_orde or btrim(coalesce(opmerking,'')) <> '')
);

create index if not exists idx_lmra_antwoorden_lmra on lmra_risico_antwoorden (lmra_id);

alter table lmras enable row level security;
alter table lmra_risico_antwoorden enable row level security;

-- Lezen: de klant zijn eigen dossier, de superbeheerder alles. Schrijven gebeurt
-- vanuit de app zonder sessie, dus uitsluitend via security definer-RPC's --
-- die komen in de volgende migratie, samen met de app.
create policy portal_select_lmras on lmras for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy portal_select_lmra_antwoorden on lmra_risico_antwoorden for select to authenticated
  using (exists (
    select 1 from lmras l
    where l.id = lmra_id
      and (l.bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder())
  ));

-- ---------------------------------------------------------------------------
-- 3. Startlijst met risico's
-- ---------------------------------------------------------------------------
-- Bewust kort en algemeen: dit zijn de risico's die in vrijwel elke sector
-- terugkomen. Per klant kies je eruit wat geldt. Vul aan waar jouw praktijk om
-- vraagt -- daarvoor is het een beheerde lijst.
insert into lmra_risicos (naam, categorie, toelichting, volgorde) values
  ('Vallen van hoogte','Val en struikel','Ladders, steigers, randen, openingen',10),
  ('Struikelen, uitglijden','Val en struikel','Losse kabels, gladde of bezaaide vloer',20),
  ('Aanrijding door voertuig','Verkeer en transport','Heftrucks, vrachtwagens, manoeuvreerzones',30),
  ('Vallende of kantelende last','Verkeer en transport','Hijsen, stapelen, instabiele lading',40),
  ('Bewegende machinedelen','Machines','Onafgeschermde delen, onverwacht opstarten',50),
  ('Elektrocutie','Energie','Spanning, beschadigde kabels, natte omgeving',60),
  ('Onder druk of onder spanning','Energie','Leidingen, veren, opgeslagen energie',70),
  ('Brand of explosie','Brand','Ontstekingsbronnen, brandbare stoffen',80),
  ('Gevaarlijke stoffen','Chemisch','Inademen, huidcontact, verkeerde opslag',90),
  ('Verstikking of zuurstoftekort','Besloten ruimte','Putten, tanks, kruipruimten',100),
  ('Lawaai','Fysisch','Langdurig of piekgeluid',110),
  ('Handling en houding','Ergonomie','Tillen, duwen, langdurig gebogen werken',120),
  ('Warmte of koude','Fysisch','Hitte, vorst, werken buiten',130),
  ('Alleen werken','Organisatie','Geen zicht of gehoor van collega''s',140),
  ('Derden in de zone','Organisatie','Bezoekers, andere aannemers, publiek',150)
on conflict (naam) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Meenemen in het verwijderen van een bedrijf
-- ---------------------------------------------------------------------------
-- Alleen de drie LMRA-regels zijn nieuw; de rest is 0076 ongewijzigd.
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
  where g.bedrijf_id = p_bedrijf_id
    and g.auth_user_id is not null;


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
      where s.bedrijf_id = p_bedrijf_id
    );
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
  delete from keuringen where bedrijf_id = p_bedrijf_id;
  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;

  delete from auth.users u
  where u.id = any(v_auth_ids)
    and not exists (select 1 from gebruikers g where g.auth_user_id = u.id)
    and not exists (select 1 from superbeheerders s where s.auth_user_id = u.id);
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
