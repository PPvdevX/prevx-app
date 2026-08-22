-- Fase A van de module Digitale Vuurvergunning: modulecatalogus, werktypes en
-- het vragenbeheer. De vergunningen zelf (aanvraag, goedkeuring, nazorg) komen
-- in 0051; deze migratie legt enkel vast wát er gevraagd wordt.
--
-- Twee afwijkingen t.o.v. het concept-document, bewust:
--
-- 1) GEEN aparte sectietabel. Het document groepeert de vragen enkel per fase
--    (voor/tijdens/na) en kent binnen een fase geen subgroepen. Een
--    sectielaag toevoegen "omdat de pre-inspectiechecklist er een heeft" zou
--    structuur bouwen die niemand vraagt. De fase staat dus rechtstreeks op
--    de vraag.
--
-- 2) NIET elke genummerde regel uit §5.1 wordt een checklistvraag. Vragen 1
--    (werktype), 2 (locatie), 3 (uitvoerders), 8 (bewakingsagent), 13
--    (geldigheidsduur) en 14 (goedkeuring) zijn eigenschappen van de
--    vergunning zelf, geen vragen met een antwoord -- die worden kolommen op
--    de vergunning in 0051. Wat overblijft zijn de echte vaststellingen.
--
-- Nieuw t.o.v. de pre-inspectiechecklist: een vraag kan BLOKKEREND zijn. Het
-- document schrijft bij "brandbare stoffen verwijderd" en "blustoestellen
-- aanwezig" voor dat de vergunning bij NOK niet eens ter goedkeuring mag
-- worden aangeboden. Dat is een eigenschap van de vraag, niet van de UI.

-- ---------------------------------------------------------------------------
-- Modulecatalogus
-- ---------------------------------------------------------------------------
-- Enkel de catalogus (naam, volgorde). Welke klant welke module heeft, staat
-- al in bedrijf_modules (0019) en dat mechanisme blijft ongewijzigd.
create table if not exists modules (
  key text primary key,
  naam text not null,
  volgorde int not null default 0,
  actief boolean not null default true
);

alter table modules enable row level security;

-- Iedereen die ingelogd is mag de catalogus lezen; beheren doet de superbeheerder.
create policy portal_select_modules on modules for select to authenticated using (true);
create policy superbeheerder_all_modules on modules for all to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());
-- De chauffeurs-app heeft geen sessie en leest de catalogus via rpc_modules().

insert into modules (key, naam, volgorde) values
  ('preinspecties', 'Pre-inspectie', 1),
  ('vuurvergunning', 'Vuurvergunning', 2)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Werktypes
-- ---------------------------------------------------------------------------
-- Standaardsjabloon (PrevX-breed) en de kopie per klant. Bewust twee tabellen
-- i.p.v. één tabel met een nullable bedrijf_id: dan blijft "not null"
-- afdwingbaar op de klantrijen en kan een bug nooit per ongeluk een
-- sjabloonrij aanmaken.
create table if not exists werktype_standaard (
  key text primary key,
  naam text not null,
  toelichting text,
  volgorde int not null default 0
);

insert into werktype_standaard (key, naam, toelichting, volgorde) values
  ('elektrisch_lassen', 'Elektrisch lassen', 'Booglassen en aanverwante technieken.', 1),
  ('gaslassen', 'Gaslassen / snijbranden', 'Werken met acetyleen- of propaanbranders, snijbranden van metaal.', 2),
  ('slijpen', 'Slijp- en snijwerkzaamheden', 'Doorslijpen, haakse slijper, snijschijven -- vonkvorming.', 3),
  ('dakwerken', 'Dakwerken met open vlam', 'Roofing- en dakdichtingswerken met brander.', 4),
  ('ontdooien', 'Ontdooien met brander', 'Ontdooien van leidingen of installaties met een open vlam.', 5),
  ('overig', 'Overig heet werk', 'Solderen en andere werkzaamheden met vlam, hitte of vonkvorming.', 6)
on conflict (key) do nothing;

create table if not exists werktypes (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  key text not null,
  naam text not null,
  toelichting text,
  volgorde int not null default 0,
  actief boolean not null default true,
  unique (bedrijf_id, key)
);

alter table werktypes enable row level security;

create policy portal_select_werktypes on werktypes for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());
create policy portal_write_werktypes on werktypes for insert to authenticated
  with check (bedrijf_id = public.huidig_bedrijf_id());
create policy portal_update_werktypes on werktypes for update to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id())
  with check (bedrijf_id = public.huidig_bedrijf_id());
create policy superbeheerder_all_werktypes on werktypes for all to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- Vragen
-- ---------------------------------------------------------------------------
-- antwoordtype als text met CHECK i.p.v. een echte enum: zelfde huisstijl als
-- inspectie_punten.niveau (0004), en later uitbreiden vraagt geen ALTER TYPE.
create table if not exists vergunning_standaardvragen (
  id uuid primary key default gen_random_uuid(),
  fase text not null check (fase in ('voor','tijdens','na')),
  vraagtekst text not null,
  antwoordtype text not null check (antwoordtype in
    ('ok_nok','ok_nok_nvt','ok_nok_afwijking','ok_nok_nvt_afwijking','ja_nee','tekst','foto')),
  verplicht boolean not null default true,
  blokkerend boolean not null default false,
  toelichting text,
  -- Leeg = geldt voor elk werktype; anders enkel voor deze werktype-keys.
  -- Zelfde "leeg = gedeeld"-conventie als inspectie_sectie_types (0048).
  werktype_keys text[] not null default '{}',
  volgorde int not null default 0
);

create table if not exists vergunning_vragen (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  fase text not null check (fase in ('voor','tijdens','na')),
  vraagtekst text not null,
  antwoordtype text not null check (antwoordtype in
    ('ok_nok','ok_nok_nvt','ok_nok_afwijking','ok_nok_nvt_afwijking','ja_nee','tekst','foto')),
  verplicht boolean not null default true,
  blokkerend boolean not null default false,
  toelichting text,
  volgorde int not null default 0,
  actief boolean not null default true
);

create table if not exists vergunning_vraag_werktypes (
  vraag_id uuid not null references vergunning_vragen(id) on delete cascade,
  werktype_id uuid not null references werktypes(id),
  primary key (vraag_id, werktype_id)
);

alter table vergunning_vragen enable row level security;
alter table vergunning_vraag_werktypes enable row level security;

create policy portal_select_vergunning_vragen on vergunning_vragen for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());
create policy portal_write_vergunning_vragen on vergunning_vragen for insert to authenticated
  with check (bedrijf_id = public.huidig_bedrijf_id());
create policy portal_update_vergunning_vragen on vergunning_vragen for update to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id())
  with check (bedrijf_id = public.huidig_bedrijf_id());
create policy superbeheerder_all_vergunning_vragen on vergunning_vragen for all to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());

create policy portal_all_vraag_werktypes on vergunning_vraag_werktypes for all to authenticated
  using (exists (
    select 1 from vergunning_vragen v
    where v.id = vergunning_vraag_werktypes.vraag_id and v.bedrijf_id = public.huidig_bedrijf_id()
  ))
  with check (exists (
    select 1 from vergunning_vragen v
    where v.id = vergunning_vraag_werktypes.vraag_id and v.bedrijf_id = public.huidig_bedrijf_id()
  ));
create policy superbeheerder_all_vraag_werktypes on vergunning_vraag_werktypes for all to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- Standaardvragen (ANPI-basis uit het conceptdocument)
-- ---------------------------------------------------------------------------
insert into vergunning_standaardvragen (fase, vraagtekst, antwoordtype, verplicht, blokkerend, toelichting, werktype_keys, volgorde) values
  ('voor','Zijn brandbare stoffen binnen 10 m verwijderd, beschermd of afgedekt met een aangepast scherm?','ok_nok_afwijking',true,true,'10 m is een richtafstand uit de ANPI-sectornorm, geen wettelijke afstand. Bij een afwijking is een motivering en compenserende maatregel verplicht.','{}',1),
  ('voor','Zijn openingen, spleten en scheuren in wanden binnen 10 m afgedicht of afgedekt?','ok_nok_nvt_afwijking',true,false,'Zelfde richtafstand en logica als de vorige vraag.','{}',2),
  ('voor','Zijn draagbare blustoestellen (poeder of water) aanwezig binnen bereik?','ok_nok',true,true,null,'{}',3),
  ('voor','Is een brandhaspel of hydrant beschikbaar in de onmiddellijke nabijheid?','ok_nok_nvt',false,false,null,'{}',4),
  ('voor','Zijn recipiënten en leidingen die ontvlambare stoffen bevatten geledigd en ontgast?','ok_nok_nvt',true,false,null,'{}',5),
  ('voor','Vinden de werken plaats binnen 2 uur vóór bedrijfssluiting?','ja_nee',true,false,'Bij ja: extra aandacht voor de nazorg vereist.','{}',6),
  ('voor','Zijn de betrokken werknemers ingelicht over de risico''s?','ja_nee',true,false,null,'{}',7),
  ('voor','Foto van de werkzone vóór aanvang','foto',true,false,'Automatisch tijdgestempeld.','{}',8),

  ('voor','Is voldoende ventilatie voorzien tegen lasrook?','ok_nok',true,false,null,'{elektrisch_lassen}',20),
  ('voor','Is de aardklem correct en dicht bij het werkpunt aangesloten?','ok_nok',true,false,null,'{elektrisch_lassen}',21),
  ('voor','Draagt de lasser aangepaste PBM (lasscherm, lasgamaschen, moeilijk ontvlambare kledij)?','ok_nok',true,false,null,'{elektrisch_lassen}',22),
  ('voor','Staan de gasflessen rechtop, bevestigd en op veilige afstand van de warmtebron?','ok_nok',true,false,null,'{gaslassen}',23),
  ('voor','Zijn de vlamterugslagbeveiligingen aanwezig en functioneel op fles en brander?','ok_nok',true,false,null,'{gaslassen}',24),
  ('voor','Zijn slangen en aansluitingen gecontroleerd op lekken?','ok_nok',true,false,'Bijvoorbeeld met een zeepoplossing.','{gaslassen}',25),
  ('voor','Is de beschermkap van het toestel aanwezig en correct gemonteerd?','ok_nok',true,false,null,'{slijpen}',26),
  ('voor','Wordt gewerkt met een vonkenvanger of -scherm richting brandbare omgeving?','ok_nok_nvt',true,false,null,'{slijpen}',27),
  ('voor','Is stofafzuiging voorzien indien relevant?','ok_nok_nvt',false,false,'Bijvoorbeeld bij metaalstof in een gesloten ruimte.','{slijpen}',28),
  ('voor','Is de dakopbouw gecontroleerd op brandbaarheid en doorlekgevaar naar onderliggende ruimtes?','ok_nok',true,false,null,'{dakwerken}',29),
  ('voor','Is een extra blusmiddel geschikt voor bitumen-/gasbranden aanwezig?','ok_nok',true,false,null,'{dakwerken}',30),
  ('voor','Is de onderliggende ruimte (zolder, technische ruimte) mee gecontroleerd vóór en na de werken?','ok_nok',true,false,null,'{dakwerken}',31),
  ('voor','Is de te ontdooien leiding leeggemaakt/drukvrij, indien van toepassing?','ok_nok_nvt',true,false,null,'{ontdooien}',32),
  ('voor','Bevindt zich geen isolatiemateriaal of andere brandbare bekleding in de directe omgeving?','ok_nok',true,false,null,'{ontdooien}',33),
  ('voor','Is voldoende ventilatie voorzien bij gebruik van vloeimiddelen/soldeerrook?','ok_nok',true,false,null,'{overig}',34),
  ('voor','Is een geschikt onbrandbaar werkoppervlak voorzien?','ok_nok',true,false,null,'{overig}',35),

  ('tijdens','Zijn de gebruikte toestellen en uitrusting in perfecte staat van werking?','ok_nok',true,false,null,'{}',1),
  ('tijdens','Blijven aangestoken branders / soldeerlampen steeds onder rechtstreeks toezicht?','ja_nee',true,false,null,'{}',2),
  ('tijdens','Worden gloeiende vonken en verhitte metaalonderdelen actief opgevolgd?','ok_nok',false,false,'Steekproefsgewijze controle door de bewakingsagent.','{}',3),
  ('tijdens','Worden hete voorwerpen enkel op isolerende, onbrandbare draagvlakken geplaatst?','ok_nok',false,false,null,'{}',4),
  ('tijdens','Worden hete resten (bv. elektroderesten) in een geschikte, onbrandbare recipiënt geworpen?','ok_nok',false,false,null,'{}',5),
  ('tijdens','Foto van de tussentijdse controle','foto',false,false,'Kan meermaals per werkfase geregistreerd worden.','{}',6),

  ('na','Zijn de werkplek en de aangrenzende, verborgen en technische ruimten zorgvuldig onderzocht?','ok_nok',true,false,null,'{}',1),
  ('na','Is toezicht voorzien gedurende minstens 2 uur na beëindiging van de werken?','ja_nee',true,false,'De app start automatisch een timer van 2 uur bij het afsluiten van de tijdens-fase.','{}',2),
  ('na','Zijn de bewakers ingelicht voor een opvolgcontrole tot 24 uur na de werken?','ja_nee',true,false,'De app plant automatisch een herinnering na 24 uur.','{}',3),
  ('na','Worden verplaatste voorwerpen pas ten vroegste 24 uur na beëindiging teruggeplaatst?','ja_nee',false,false,null,'{}',4),
  ('na','Eventuele opmerkingen of vastgestelde incidenten','tekst',false,false,null,'{}',5);

-- ---------------------------------------------------------------------------
-- Activatie: standaardset naar een klant kopiëren
-- ---------------------------------------------------------------------------
-- Idempotent: al bestaande werktypes/vragen worden niet overschreven, zodat
-- een tweede aanroep de aanpassingen van de klant niet wegvaagt.
create or replace function public.rpc_vuurvergunning_activeren(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_std record;
  v_vraag_id uuid;
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder kan deze module activeren';
  end if;

  insert into werktypes (bedrijf_id, key, naam, toelichting, volgorde)
  select p_bedrijf_id, key, naam, toelichting, volgorde from werktype_standaard
  on conflict (bedrijf_id, key) do nothing;

  -- Enkel seeden als er nog niets staat: anders zou een tweede activatie de
  -- door de klant verwijderde standaardvragen opnieuw laten opduiken.
  if exists (select 1 from vergunning_vragen where bedrijf_id = p_bedrijf_id) then
    return;
  end if;

  for v_std in select * from vergunning_standaardvragen order by fase, volgorde loop
    insert into vergunning_vragen (bedrijf_id, fase, vraagtekst, antwoordtype, verplicht, blokkerend, toelichting, volgorde)
    values (p_bedrijf_id, v_std.fase, v_std.vraagtekst, v_std.antwoordtype, v_std.verplicht, v_std.blokkerend, v_std.toelichting, v_std.volgorde)
    returning id into v_vraag_id;

    if array_length(v_std.werktype_keys, 1) is not null then
      insert into vergunning_vraag_werktypes (vraag_id, werktype_id)
      select v_vraag_id, w.id
      from werktypes w
      where w.bedrijf_id = p_bedrijf_id and w.key = any (v_std.werktype_keys);
    end if;
  end loop;

  insert into bedrijf_modules (bedrijf_id, module_key, actief)
  values (p_bedrijf_id, 'vuurvergunning', true)
  on conflict (bedrijf_id, module_key) do update set actief = true;
end;
$$;

grant execute on function public.rpc_vuurvergunning_activeren(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Ontbrekende bedrijf_modules-rijen dichten
-- ---------------------------------------------------------------------------
-- nieuwBedrijf() in mijn.html maakt een bedrijf aan zonder rijen in
-- bedrijf_modules; de backfills in 0019/0022 dekten enkel de bedrijven die
-- toen bestonden. Het portaal merkt dat niet, want daar leest een ontbrekende
-- rij als "actief" (actieveModules.preinspecties !== false). rpc_modules
-- hieronder joint echter op die tabel, en zou voor zo'n bedrijf NIETS
-- teruggeven -- waardoor een chauffeur zijn app niet meer in raakt.
--
-- Oplossing in de data i.p.v. in nog een tweede laag defaults: bestaande
-- bedrijven bijwerken, en een trigger die het voor nieuwe bedrijven afdwingt
-- ongeacht via welk codepad ze aangemaakt worden.
insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'preinspecties', true from bedrijven
on conflict (bedrijf_id, module_key) do nothing;

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
  return new;
end;
$$;

drop trigger if exists trg_standaard_bedrijf_modules on bedrijven;
create trigger trg_standaard_bedrijf_modules
  after insert on bedrijven
  for each row execute function public.zet_standaard_bedrijf_modules();

-- ---------------------------------------------------------------------------
-- Modulekeuze in de chauffeurs-app
-- ---------------------------------------------------------------------------
-- De app heeft geen Supabase Auth-sessie, dus dit loopt net als de andere
-- driver-RPC's via security definer met de gebruiker-id als bewijs.
create or replace function public.rpc_modules(p_gebruiker_id uuid)
returns table(key text, naam text, volgorde int)
language sql
security definer
set search_path = public
as $$
  select m.key, m.naam, m.volgorde
  from modules m
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true
  join bedrijf_modules bm on bm.bedrijf_id = g.bedrijf_id and bm.module_key = m.key and bm.actief = true
  where m.actief = true
  order by m.volgorde;
$$;

grant execute on function public.rpc_modules(uuid) to anon;

-- ---------------------------------------------------------------------------
-- Cascade bijwerken (zie de waarschuwing in 0043/0049)
-- ---------------------------------------------------------------------------
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

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
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  -- vergunning_vraag_werktypes hangt met on delete cascade aan de vragen, maar
  -- verwijst óók naar werktypes zonder cascade -- de vragen moeten dus weg
  -- vóór de werktypes, anders blokkeert die tweede FK.
  delete from vergunning_vragen where bedrijf_id = p_bedrijf_id;
  delete from werktypes where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
