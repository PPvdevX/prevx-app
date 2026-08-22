-- ===========================================================================
-- 0105_melden_feit_van_derde_vanaf_de_vloer.sql
-- ===========================================================================
-- Artikel I.3-3 zegt dat de werknemer een verklaring moet kunnen laten
-- optekenen. Dat kon al: hij spreekt de vertrouwenspersoon aan. Maar precies
-- bij dit soort feiten is die stap de drempel -- je moet iemand opzoeken, in
-- een gang gaan staan en het hardop zeggen. Vanaf de gsm kan het in de
-- kleedkamer.
--
-- ---------------------------------------------------------------------------
-- WAT ANONIEM BETEKENT, EN WAT NIET
-- ---------------------------------------------------------------------------
-- De app weet wie er inlogt. Anoniem melden betekent hier dus niet "wij weten
-- het niet", maar "wij gooien het weg voor er iets opgeslagen wordt". Concreet:
--
--   1. p_gebruiker_id komt binnen om het bedrijf te vinden en verdwijnt daarna.
--      Er is geen kolom waar het in terechtkomt en er is geen tweede tabel die
--      meekijkt. De verklaring draagt geen enkele verwijzing naar een persoon.
--
--   2. aangemaakt_op wordt op de dag afgerond. Een tijdstip op de seconde is in
--      een ploeg van vijf een aanwijzing: wie was er om 14u07 binnen? Dat is
--      geen naam, maar het is genoeg om te gaan raden, en raden is hier al
--      schadelijk.
--
--   3. opgetekend_door wordt 'Gemeld via de app'. Geen naam, en meteen
--      zichtbaar in het register waar deze verklaring vandaan komt.
--
--   4. De app houdt geen lijst bij van wat jij gemeld hebt. Dat is geen
--      vergetelheid maar een gevolg: zo'n lijst zou een koppeling vereisen, en
--      dan is punt 1 gelogen. Wie na het versturen zijn eigen melding wil
--      terugzien, kan dat dus niet -- en dat staat op het scherm.
--
--   5. De naam kan er wel in, maar alleen als de werknemer daar zelf om vraagt.
--      Dan pas leest de functie de naam op. Staat het vinkje niet aan, dan
--      wordt de naam niet opgehaald -- niet opgehaald en weggegooid, maar
--      nooit aangeraakt.
--
-- Wat dit NIET afdekt, en dat hoort erbij: het verzoek zelf reist met het
-- gebruiker-id erin. Zet iemand statement logging aan op de databank, dan staat
-- dat id in dat logboek. Supabase doet dat standaard niet en wij zetten het niet
-- aan, maar een garantie die op een instelling steunt is geen garantie. Voor wie
-- dat niet genoeg is, blijft de weg op papier naar de vertrouwenspersoon bestaan
-- -- en dat mag een klant gerust weten.
-- ===========================================================================


-- Waar de verklaring vandaan komt. Nuttig in het register en verraadt niemand:
-- het zegt alleen dat het niet aan een bureau opgetekend is.
alter table feiten_van_derden
  add column if not exists via_app boolean not null default false;

comment on column feiten_van_derden.via_app is
  'True wanneer de verklaring vanaf de gsm gemeld is. De melder is dan niet gekend, tenzij hij zijn naam heeft laten opnemen.';


-- ---------------------------------------------------------------------------
-- De melding zelf
-- ---------------------------------------------------------------------------
-- Security definer, want de app heeft geen sessie en de tabel is afgeschermd
-- voor iedereen behalve de werkgever en de vertrouwenspersoon. Dit is de enige
-- weg naar binnen, en ze schrijft alleen -- ze geeft niets terug van wat er al
-- staat. Een melder kan langs deze functie dus niet lezen wat een collega
-- gemeld heeft.
create or replace function public.rpc_meld_feit_van_derde(
  p_gebruiker_id uuid,
  p_datum_feiten date,
  p_periode text,
  p_plaats text,
  p_hoedanigheid text,
  p_soort text[],
  p_beschrijving text,
  p_naam_erbij boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf uuid;
  v_naam text;
begin
  if p_beschrijving is null or btrim(p_beschrijving) = '' then
    raise exception 'Zonder beschrijving heeft een verklaring geen inhoud';
  end if;

  -- Het bedrijf opzoeken is het enige waarvoor het gebruiker-id dient. De naam
  -- wordt alleen gelezen wanneer de melder daar uitdrukkelijk om vraagt.
  select bedrijf_id, case when p_naam_erbij then naam else null end
    into v_bedrijf, v_naam
  from gebruikers
  where id = p_gebruiker_id and actief = true;

  if v_bedrijf is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  insert into feiten_van_derden
    (bedrijf_id, datum_verklaring, datum_feiten, periode_feiten, plaats,
     hoedanigheid_derde, soort, beschrijving,
     aangever, naam_met_instemming, opgetekend_door, via_app, aangemaakt_op)
  values
    (v_bedrijf, current_date, p_datum_feiten, nullif(btrim(coalesce(p_periode,'')),''),
     nullif(btrim(coalesce(p_plaats,'')),''), nullif(btrim(coalesce(p_hoedanigheid,'')),''),
     coalesce(p_soort, '{}'), btrim(p_beschrijving),
     v_naam, coalesce(p_naam_erbij, false), 'Gemeld via de app', true,
     -- Op de dag afgerond. Zie de uitleg bovenaan: een tijdstip op de seconde
     -- is in een kleine ploeg een aanwijzing.
     date_trunc('day', now()));

  -- Geen id terug. Er is niets om later mee op te halen, en dat is de bedoeling.
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.rpc_meld_feit_van_derde(uuid, date, text, text, text, text[], text, boolean) from public;
grant execute on function public.rpc_meld_feit_van_derde(uuid, date, text, text, text, text[], text, boolean) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- De module verschijnt op de gsm
-- ---------------------------------------------------------------------------
-- In 0104 stond in_app op false, omdat het register aan een bureau wordt
-- bijgehouden. Dat klopt nog steeds voor het register; wat er nu bij komt is de
-- weg naartoe. De tegel op de gsm meldt, ze toont niets.
update modules set in_app = true where key = 'feiten_derden';


-- ---------------------------------------------------------------------------
-- Het demobedrijf
-- ---------------------------------------------------------------------------
-- De twee bestaande verklaringen zijn aan een bureau opgetekend. Er komt er een
-- bij die van de vloer komt, zodat het verschil in het register te zien is.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
begin
  -- De module aanzetten voor de demo, anders verschijnt de tegel niet op de
  -- gsm. Staat ook in 0091, voor wie dat script opnieuw draait.
  insert into bedrijf_modules (bedrijf_id, module_key, actief)
  values (v_bedrijf, 'feiten_derden', true)
  on conflict (bedrijf_id, module_key) do update set actief = true;

  if not exists (select 1 from feiten_van_derden where bedrijf_id = v_bedrijf) then
    raise notice 'Geen demoregister gevonden; niets toegevoegd.';
    return;
  end if;

  delete from feiten_van_derden where bedrijf_id = v_bedrijf and via_app;

  -- Zaaien mag geen mail versturen. De trigger komt pas met 0106, dus bij de
  -- eerste uitvoering bestaat hij nog niet -- maar wie dit script later opnieuw
  -- draait, zou anders de vertrouwenspersoon een bericht sturen over een
  -- verzonnen voorval.
  if exists (select 1 from pg_trigger where tgname = 'trg_meld_feit_van_derde') then
    alter table feiten_van_derden disable trigger trg_meld_feit_van_derde;
  end if;

  insert into feiten_van_derden
    (bedrijf_id, datum_verklaring, datum_feiten, plaats, hoedanigheid_derde,
     soort, beschrijving, naam_met_instemming, opgetekend_door, via_app, aangemaakt_op)
  values
    (v_bedrijf, current_date - 4, current_date - 4, 'Parking, bij het einde van de shift',
     'Bezoeker', array['ongewenst_seksueel_gedrag'],
     'Een bezoeker die op de parking stond te wachten maakte opmerkingen over '
     'het lichaam van een werkneemster en bleef naast haar lopen tot aan haar '
     'auto. Ze is blijven staan tot hij wegreed en is daarna pas vertrokken.',
     false, 'Gemeld via de app', true, date_trunc('day', now()) - interval '4 days');

  if exists (select 1 from pg_trigger where tgname = 'trg_meld_feit_van_derde') then
    alter table feiten_van_derden enable trigger trg_meld_feit_van_derde;
  end if;

  raise notice 'Een verklaring vanaf de vloer toegevoegd aan het demoregister.';
end
$$;


notify pgrst, 'reload schema';
