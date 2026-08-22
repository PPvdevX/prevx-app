-- ===========================================================================
-- 0104_register_feiten_van_derden.sql -- artikel I.3-3 van de codex
-- ===========================================================================
-- Een werkgever wiens werknemers bij hun werk in contact komen met andere
-- personen -- klanten, patiënten, leerlingen, leveranciers, een stem aan de
-- telefoon -- moet een register bijhouden van de feiten van geweld, pesterijen
-- of ongewenst seksueel gedrag die door die derden veroorzaakt worden.
--
-- Nagelezen op 21 aug 2026 in de codex over het welzijn op het werk, boek I
-- titel 3, artikel I.3-3, en in fiche 15 "Register van feiten door derden" van
-- de FOD Werkgelegenheid (D/2020/1205/36). Wat daar staat en hier verwerkt is:
--
--   * de verklaring bevat een BESCHRIJVING van de feiten en de DATA ervan;
--   * ze vermeldt de identiteit van de werknemer NIET, tenzij die daarmee
--     instemt -- de wet zegt dat met zoveel woorden;
--   * alleen de werkgever, de preventieadviseur psychosociale aspecten, de
--     vertrouwenspersoon en de preventieadviseur die de interne dienst leidt
--     hebben toegang;
--   * het register wordt bijgehouden door de vertrouwenspersoon of de
--     preventieadviseur psychosociale aspecten;
--   * de verklaringen worden vijf jaar bewaard, te rekenen vanaf de dag dat de
--     werknemer ze heeft laten optekenen;
--   * de feiten in het register wegen mee in de jaarlijkse evaluatie van de
--     preventiemaatregelen (art. I.3-6, § 2, derde lid, 5°);
--   * de STATISTISCHE gegevens gaan eenmaal per jaar naar de preventieadviseur
--     psychosociale aspecten (art. I.3-65).
--
-- ---------------------------------------------------------------------------
-- DE BELANGRIJKSTE KEUZE: PREVX KAN DIT NIET LEZEN
-- ---------------------------------------------------------------------------
-- Elke andere tabel in dit portaal heeft een regel die de superbeheerder
-- doorlaat. Deze niet, en dat is geen vergetelheid.
--
-- De wet somt vier functies op die toegang hebben, en "de externe dienst die
-- het portaal levert" staat daar niet bij. Wie preventieadviseur psychosociale
-- aspecten is, wordt bij de klant aangewezen; dat is een aparte specialisatie
-- en niet iets wat volgt uit het leveren van software. Zolang dat niet
-- uitdrukkelijk zo geregeld is, hoort PrevX de tekst van een verklaring niet
-- te zien.
--
-- Wat PrevX wél krijgt, is precies wat de wet voorziet: de cijfers, via
-- rpc_feiten_derden_statistiek. Aantallen per jaar en per soort, nooit een zin
-- uit een verklaring.
--
-- Eerlijk erbij gezegd, want een klant zou het kunnen vragen: dit maakt het
-- niet technisch onmogelijk. Peter beheert de databank en kan er langs die weg
-- altijd bij. Wat dit wel doet, is het onmogelijk maken per ongeluk -- geen
-- scherm, geen lijst, geen zoekresultaat waarin die tekst opduikt. Wil een
-- klant een harde garantie, dan hoort dit register niet in software van zijn
-- externe dienst thuis en zeg je dat beter meteen.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. Wie mag erbij?
-- ---------------------------------------------------------------------------
-- De vertrouwenspersoon is een functie, geen portaalrol: iemand kan
-- vertrouwenspersoon zijn zonder het dossier te beheren, en omgekeerd. Vandaar
-- een eigen vlag naast dossier_rol.
alter table gebruikers
  add column if not exists vertrouwenspersoon boolean not null default false;

comment on column gebruikers.vertrouwenspersoon is
  'Aangewezen als vertrouwenspersoon in de zin van boek I titel 3. Geeft toegang tot het register van feiten van derden.';

create or replace function public.is_vertrouwenspersoon()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from gebruikers
    where auth_user_id = auth.uid()
      and actief = true
      and vertrouwenspersoon = true
  );
$$;

revoke execute on function public.is_vertrouwenspersoon() from public;
grant execute on function public.is_vertrouwenspersoon() to authenticated;


-- ---------------------------------------------------------------------------
-- 2. Het register
-- ---------------------------------------------------------------------------
-- De velden volgen het formulier van de FOD, in dezelfde volgorde, zodat een
-- afdruk uit het portaal naast hun blad gelegd kan worden.
create table if not exists feiten_van_derden (
  id uuid primary key default gen_random_uuid(),
  -- on delete cascade, anders dan bij de andere tabellen: de opkuisfunctie van
  -- 0082 kent dit register niet, en zou dus blijven hangen op de foreign key.
  -- Haar laatste regel is delete from bedrijven, en daarmee gaat dit vanzelf
  -- mee. Een vergeten regel in die functie mag hier niet betekenen dat
  -- verklaringen achterblijven bij een bedrijf dat niet meer bestaat.
  bedrijf_id uuid not null references bedrijven(id) on delete cascade,

  -- De dag waarop de verklaring werd opgetekend. Hiervan lopen de vijf jaar.
  datum_verklaring date not null default current_date,

  -- De wet vraagt "de data van die feiten", meervoud. Eén datum volstaat vaak
  -- niet: bij een klant die elke week terugkomt is het patroon het feit. Vandaar
  -- een datum en een vrij veld ernaast.
  datum_feiten date,
  periode_feiten text,

  plaats text,
  -- Gebruiker, klant, patiënt, leerling, werknemer van een extern bedrijf...
  -- Geen keuzelijst: de wet vraagt de hoedanigheid, niet een categorie uit een
  -- lijst die wij verzinnen.
  hoedanigheid_derde text,

  -- geweld / pesterijen / ongewenst_seksueel_gedrag. De drie uit de wet; er kan
  -- meer dan een tegelijk spelen.
  soort text[] not null default '{}',

  beschrijving text not null,

  -- De identiteit van de werknemer staat er NIET in, tenzij hij daarmee
  -- instemt. Twee kolommen en geen een: zonder die uitdrukkelijke vlag zou een
  -- leeg naamveld ook "niet ingevuld" kunnen betekenen, en dan weet niemand
  -- later nog of er toestemming gevraagd is.
  aangever text,
  naam_met_instemming boolean not null default false,

  -- Wie de verklaring optekende. Dat is de vertrouwenspersoon of de
  -- preventieadviseur, en dat is iets anders dan de aangever.
  opgetekend_door text,

  -- Wat er met de melding gebeurd is. Niet wettelijk verplicht, wel het enige
  -- wat een register van een archief onderscheidt.
  gevolg text,
  afgehandeld boolean not null default false,

  aangemaakt_op timestamptz not null default now(),
  bijgewerkt_op timestamptz not null default now(),

  -- Vijf jaar vanaf het optekenen. Opgeslagen en niet berekend bij het tonen,
  -- zodat je erop kan sorteren en filteren.
  bewaren_tot date generated always as (((datum_verklaring + interval '5 years'))::date) stored,

  constraint beschrijving_niet_leeg check (btrim(beschrijving) <> '')
);

create index if not exists feiten_van_derden_bedrijf_idx
  on feiten_van_derden (bedrijf_id, datum_verklaring desc);

comment on table feiten_van_derden is
  'Register van feiten van derden (codex boek I titel 3, art. I.3-3). Vertrouwelijk: alleen werkgever, vertrouwenspersoon en preventieadviseur psychosociale aspecten. Bewust GEEN toegang voor de superbeheerder.';


-- ---------------------------------------------------------------------------
-- 3. De afscherming
-- ---------------------------------------------------------------------------
-- Een policy, voor alles tegelijk. Splitsen in lezen en schrijven zou hier
-- suggereren dat er iemand is die wel mag lezen en niet schrijven, en dat is
-- niet zo: je hoort er helemaal bij of helemaal niet.
alter table feiten_van_derden enable row level security;

create policy toegang_feiten_van_derden on feiten_van_derden
  for all to authenticated
  using (
    bedrijf_id = public.huidig_bedrijf_id()
    and (public.is_klant_beheerder() or public.is_vertrouwenspersoon())
  )
  with check (
    bedrijf_id = public.huidig_bedrijf_id()
    and (public.is_klant_beheerder() or public.is_vertrouwenspersoon())
  );

create or replace function public.zet_bijgewerkt_op_feiten()
returns trigger
language plpgsql
as $$
begin
  new.bijgewerkt_op := now();
  return new;
end;
$$;

drop trigger if exists trg_feiten_bijgewerkt on feiten_van_derden;
create trigger trg_feiten_bijgewerkt before update on feiten_van_derden
  for each row execute function public.zet_bijgewerkt_op_feiten();


-- ---------------------------------------------------------------------------
-- 4. De cijfers, en alleen de cijfers
-- ---------------------------------------------------------------------------
-- Dit is wat er volgens artikel I.3-65 eenmaal per jaar naar de
-- preventieadviseur psychosociale aspecten gaat, en het is ook alles wat PrevX
-- van dit register te zien krijgt.
--
-- Security definer, want de aanroeper mag de tabel zelf niet lezen. De functie
-- geeft daarom nooit een tekstveld terug -- geen beschrijving, geen naam, geen
-- plaats. Alleen tellingen. Wie deze functie leest, moet in één oogopslag
-- kunnen zien dat er geen weg is waarlangs een zin naar buiten lekt.
create or replace function public.rpc_feiten_derden_statistiek(p_bedrijf_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mag boolean;
begin
  v_mag := public.is_superbeheerder()
        or (p_bedrijf_id = public.huidig_bedrijf_id()
            and (public.is_klant_beheerder() or public.is_vertrouwenspersoon()));
  if not v_mag then
    raise exception 'Geen toegang';
  end if;

  return jsonb_build_object(
    'totaal', (select count(*) from feiten_van_derden where bedrijf_id = p_bedrijf_id),
    'laatste_12_maanden', (
      select count(*) from feiten_van_derden
      where bedrijf_id = p_bedrijf_id
        and datum_verklaring > current_date - 365),
    'open', (
      select count(*) from feiten_van_derden
      where bedrijf_id = p_bedrijf_id and not afgehandeld),
    'te_verwijderen', (
      select count(*) from feiten_van_derden
      where bedrijf_id = p_bedrijf_id and bewaren_tot < current_date),
    'per_jaar', coalesce((
      select jsonb_agg(jsonb_build_object('jaar', j.jaar, 'aantal', j.aantal) order by j.jaar desc)
      from (select extract(year from datum_verklaring)::int as jaar, count(*) as aantal
            from feiten_van_derden where bedrijf_id = p_bedrijf_id
            group by 1) j), '[]'::jsonb),
    'per_soort', coalesce((
      select jsonb_object_agg(s.soort, s.aantal)
      from (select unnest(soort) as soort, count(*) as aantal
            from feiten_van_derden where bedrijf_id = p_bedrijf_id
            group by 1) s), '{}'::jsonb)
  );
end;
$$;

revoke execute on function public.rpc_feiten_derden_statistiek(uuid) from public;
grant execute on function public.rpc_feiten_derden_statistiek(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 5. De module
-- ---------------------------------------------------------------------------
-- Achter de dossiermodules, voor de app-modules. Niet in de app: dit register
-- wordt opgetekend door de vertrouwenspersoon, niet ingevuld op de vloer.
insert into modules (key, naam, volgorde, actief) values
  ('feiten_derden', 'Register van feiten van derden', 55, true)
on conflict (key) do nothing;

update modules set in_app = false where key = 'feiten_derden';


-- ---------------------------------------------------------------------------
-- 6. Het demobedrijf
-- ---------------------------------------------------------------------------
-- Twee verklaringen, want een leeg register toont niets. Verzonnen voorvallen
-- die in een metaalbedrijf met een onthaal en leveringen kunnen gebeuren, en
-- allebei zonder naam -- zo staat het scherm meteen op de manier waarop het
-- hoort te staan.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
begin
  if not exists (select 1 from bedrijven where id = v_bedrijf) then
    raise notice 'Demobedrijf bestaat niet; geen verklaringen toegevoegd.';
    return;
  end if;

  delete from feiten_van_derden where bedrijf_id = v_bedrijf;

  insert into feiten_van_derden
    (bedrijf_id, datum_verklaring, datum_feiten, periode_feiten, plaats,
     hoedanigheid_derde, soort, beschrijving, naam_met_instemming,
     opgetekend_door, gevolg, afgehandeld)
  values
    (v_bedrijf, current_date - 40, current_date - 42, null, 'Onthaal',
     'Chauffeur van een transportfirma', array['geweld'],
     'De chauffeur werd verbaal agressief toen bleek dat zijn levering niet '
     'meteen kon gelost worden. Hij heeft geroepen, met een klembord op de '
     'balie geslagen en gedreigd "de volgende keer zelf naar binnen te gaan". '
     'De werknemer aan het onthaal voelde zich bedreigd en heeft de poort '
     'gesloten.', false, 'Sofie Delaere',
     'Transportfirma aangeschreven. Afspraak gemaakt dat leveringen voortaan '
     'aangemeld worden. Bordje met de gangbare wachttijd aan de balie.', true),

    (v_bedrijf, current_date - 11, null, 'Drie keer in de loop van juli en augustus',
     'Werkplaats, bij de draaibank', 'Klant die zijn stuk komt ophalen',
     array['pesterijen'],
     'Dezelfde klant maakt bij elk bezoek opmerkingen over het uiterlijk en de '
     'herkomst van een van de operatoren. Hij noemt het zelf grappen. De '
     'werknemer heeft gevraagd of hij dat wil laten; het is daarna nog twee '
     'keer gebeurd.', false, 'Sofie Delaere', null, false);

  raise notice 'Twee verklaringen toegevoegd aan het demoregister.';
end
$$;


notify pgrst, 'reload schema';
