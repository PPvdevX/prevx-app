-- Brandpreventiedossier: geen nieuwe opslag, wel een overzicht.
--
-- Het dossier bestaat uit elf onderdelen (fiche FOD WASO, titel 3 van boek III
-- van de codex). Tien daarvan liggen al ergens in dit portaal: negen als
-- document, één als keuringen. Er komt dus géén twaalfde module en géén nieuwe
-- bucket -- enkel wat nodig is om die elf naast elkaar te tonen en te kunnen
-- zeggen of ze nog kloppen.
--
-- Twee dingen ontbraken.

-- ---------------------------------------------------------------------------
-- 1. Welke keuringen horen in het dossier
-- ---------------------------------------------------------------------------
-- Onderdeel 8 van de fiche is breder dan brand: naast de beschermingsmiddelen
-- vallen ook de gas-, verwarmings-, airconditioning- en elektrische installaties
-- eronder. Het keuringsverslag van de elektrische installatie hoort dus in het
-- brandpreventiedossier, en zit daar bij de meeste bedrijven niet in.
--
-- Die vlag hoort op het TYPE, niet op de keuring. Zelfde reden als bij
-- wettelijke_basis in 0074: het volgt uit de soort keuring, niet uit het
-- toestel. Zet je hem per keuring, dan vinkt iemand hem twintig keer aan en
-- vergeet hem de eenentwintigste keer. Zet je hem per type, dan duidt de
-- superbeheerder hem één keer aan en klopt hij bij elke klant.
alter table keuring_types
  add column if not exists in_brandpreventiedossier boolean not null default false;

comment on column keuring_types.in_brandpreventiedossier is
  'Telt mee voor onderdeel 8 van het brandpreventiedossier: controles en onderhoud van beschermingsmiddelen, gas, verwarming, airco en elektrische installaties.';

-- ---------------------------------------------------------------------------
-- 2. De stempel "nagekeken op"
-- ---------------------------------------------------------------------------
-- De fiche legt geen enkele termijn op. Over het bijhouden zegt ze precies één
-- ding: het dossier "wordt bijgewerkt". Alleen de evacuatieoefening heeft een
-- eigen wettelijke termijn (jaarlijks), en de controles onder punt 8 volgen elk
-- hun eigen regelgeving -- die periodiciteit staat al per keuring.
--
-- Voor de negen andere onderdelen bestaat er dus geen wettelijke vervaldatum.
-- Een aftelklok tonen zou een uitspraak zijn die de wet niet doet en die dit
-- systeem niet kan onderbouwen: het ziet wel dát een interventiedossier van
-- maart 2024 dateert, niet óf het nog klopt. Dat blijft een oordeel van de
-- preventieadviseur, en dan hoort het zichtbaar te zijn als oordeel -- met een
-- naam en een datum eronder.
--
-- hertermijn_maanden staat per rij en niet als vaste waarde: hoe lang een
-- evacuatieplan mag staan hangt af van hoe vaak de klant verbouwt.
create table if not exists brandpreventie_status (
  bedrijf_id uuid not null references bedrijven(id),
  -- vaste codes uit de fiche; de labels staan in de app
  onderdeel text not null check (onderdeel in (
    'risicoanalyse', 'brandbestrijdingsdienst', 'procedures', 'evacuatieplan',
    'interventiedossier', 'oefeningen', 'beschermingsmiddelen', 'controles',
    'afwijkingen', 'adviezen', 'hulpdiensten'
  )),
  nagekeken_op date,
  door text,
  hertermijn_maanden integer not null default 12,
  opmerking text,
  bijgewerkt_op timestamptz not null default now(),
  primary key (bedrijf_id, onderdeel)
);

alter table brandpreventie_status enable row level security;

-- Lezen mag wie bij het bedrijf hoort, plus de superbeheerder. Schrijven is
-- uitsluitend de superbeheerder: het dossier is een dienst die PrevX levert,
-- en een stempel die de klant zelf kan zetten bewijst niets.
create policy portal_select_brandpreventie_status on brandpreventie_status
  for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_brandpreventie_status on brandpreventie_status
  for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_brandpreventie_status on brandpreventie_status
  for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_brandpreventie_status on brandpreventie_status
  for delete to authenticated
  using (public.is_superbeheerder());

-- Wordt altijd per bedrijf in zijn geheel opgehaald; elf rijen is niets, maar
-- de index kost ook niets en de query wordt bij elk bezoek aan het scherm
-- gedraaid.
create index if not exists idx_brandpreventie_status_bedrijf
  on brandpreventie_status(bedrijf_id);
