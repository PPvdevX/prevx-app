-- Type keuring als beheerde codelijst, met de wettelijke basis erop.
--
-- Waarom de wettelijke basis op het TYPE staat en niet op de keuring zelf: hij
-- volgt uit de soort keuring, niet uit het toestel. Zet je hem per keuring,
-- dan typt iemand hem twintig keer over en staat hij na een jaar in twintig
-- varianten in je databank. Klopt hij een keer niet, dan corrigeer je nu één
-- rij en niet twintig.
--
-- `domein` scheidt arbeidsveiligheid van milieu. Dat is geen etiket maar een
-- echt onderscheid: andere wetgeving, andere keurders, vaak een andere
-- contactpersoon bij de klant. In de vervalkalender wil je erop kunnen filteren.
--
-- Zelfde opzet als sector_codes (0032): één gedeelde lijst, geen bedrijf_id,
-- toevoegen en archiveren door de superbeheerder, nooit hard verwijderen --
-- een type dat al aan keuringen hangt moet leesbaar blijven nadat het uit de
-- keuzelijst gehaald is.

create table if not exists keuring_types (
  id uuid primary key default gen_random_uuid(),
  naam text not null,
  domein text not null default 'veiligheid',
  wettelijke_basis text,
  standaard_periodiciteit_maanden integer,
  volgorde int not null default 0,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now(),
  unique (naam)
);

alter table keuring_types enable row level security;

create policy select_keuring_types on keuring_types for select to authenticated
  using (true);

create policy superbeheerder_insert_keuring_types on keuring_types for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_keuring_types on keuring_types for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- Koppeling op de keuring
-- ---------------------------------------------------------------------------
alter table keuringen
  add column if not exists keuring_type_id uuid references keuring_types(id);

-- `categorie` (0072) deed twee dingen tegelijk -- soort keuring én onderwerp --
-- en wordt vervangen door keuring_type_id. Wat er al in staat gaat naar
-- opmerking i.p.v. verloren: de tabel is één dag oud, maar "waarschijnlijk leeg"
-- is geen reden om iets weg te gooien.
update keuringen
set opmerking = trim(both ' ' from coalesce(opmerking,'') || ' ' || categorie)
where categorie is not null and btrim(categorie) <> '';

alter table keuringen drop column if exists categorie;

-- ---------------------------------------------------------------------------
-- Startlijst
-- ---------------------------------------------------------------------------
-- LET OP: dit is een vertrekpunt, geen geverifieerde lijst. Periodiciteiten en
-- wettelijke verwijzingen hangen af van indeling, vermogen, capaciteit en
-- gewest -- VLAREM geldt in Vlaanderen. Loop ze na en pas ze aan; daarvoor is
-- het een beheerde lijst. Zelfde voorbehoud als bij de NACE-codes (0032).
insert into keuring_types (naam,domein,wettelijke_basis,standaard_periodiciteit_maanden,volgorde) values
  ('Periodieke keuring hefwerktuigen','veiligheid','KB Arbeidsmiddelen — keuring door EDTC',12,10),
  ('Keuring hijs- en hefgereedschap','veiligheid','KB Arbeidsmiddelen',12,20),
  ('Keuring ladders en steigers','veiligheid','KB Arbeidsmiddelen',12,30),
  ('Keuring valbeveiliging en ankerpunten','veiligheid','KB PBM',12,40),
  ('Periodieke controle elektrische installatie (laagspanning)','veiligheid','AREI',60,50),
  ('Periodieke controle elektrische installatie (hoogspanning)','veiligheid','AREI',12,60),
  ('Controle brandblusapparaten','veiligheid','NBN S21-050',12,70),
  ('Controle brandhaspels en blusleidingen','veiligheid','NBN EN 671-3',12,80),
  ('Keuring poorten en laadbruggen','veiligheid','KB Arbeidsmiddelen',12,90),
  ('Keuring drukapparatuur en drukvaten','veiligheid','KB Drukapparatuur',12,100),
  ('Keuring gasinstallatie','veiligheid','KB Gasinstallaties',24,110),
  ('Onderhoud en keuring stookinstallatie','veiligheid','Regionale stookolie-/gaswetgeving',12,120),
  ('Bijscholing hulpverleners (EHBO)','veiligheid','KB EHBO',12,130),
  ('Periodieke controle stookolietank','milieu','VLAREM II',12,200),
  ('Lekdichtheidscontrole koelinstallatie (F-gassen)','milieu','F-gassenverordening (EU) 517/2014',12,210),
  ('Emissiemeting lucht','milieu','VLAREM II',12,220),
  ('Analyse afvalwater','milieu','VLAREM II',12,230),
  ('Controle KWS-afscheider','milieu','VLAREM II',6,240),
  ('Periodiek bodemonderzoek risico-inrichting','milieu','Bodemdecreet',120,250),
  ('Keuring hemelwater- en septische installatie','milieu','VLAREM II',60,260)
on conflict (naam) do nothing;
