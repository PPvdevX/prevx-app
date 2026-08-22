-- ===========================================================================
-- 0103_voorzorgsmaatregelen_en_pictogrammen.sql -- de rest van het etiket
-- ===========================================================================
-- Een etiket draagt volgens artikel 17 van CLP zeven dingen: productnaam,
-- leverancier, hoeveelheid, pictogrammen, signaalwoord, gevarenaanduidingen en
-- voorzorgsmaatregelen. Wij toonden er een van.
--
-- En uitgerekend het stuk dat op de vloer telt, ontbrak. H zegt wat er mis is,
-- P zegt wat je moet doen. Iemand die het spul over zijn handen krijgt, heeft
-- niets aan "veroorzaakt huidirritatie" -- die heeft P302+P352 nodig, "bij
-- contact met de huid: met veel water wassen". Het scherm toonde de diagnose
-- zonder het voorschrift.
--
-- Deze migratie voegt twee dingen toe:
--   1. de codelijst met voorzorgsmaatregelen (126 stuks, CLP bijlage IV);
--   2. een kolom p_zinnen op de producten, naast de h_zinnen die er al stonden.
--
-- De pictogrammen hoefden geen kolom: die stond er al sinds 0098, met
-- "Enkel om te tonen" erboven. Ze werd alleen nooit gevuld en nergens getoond.
-- Dat gebeurt nu in het portaal en in de app; hier onderaan worden ze voor het
-- demobedrijf ingevuld.
--
-- ---------------------------------------------------------------------------
-- HERKOMST
-- ---------------------------------------------------------------------------
-- Zelfde bron en zelfde werkwijze als 0102: de geconsolideerde Nederlandse
-- tekst van verordening (EG) nr. 1272/2008, versie 01.02.2025, bijlage IV
-- deel 2, tabellen 1.1 tot 1.5. Opgehaald bij EUR-Lex, per code de Nederlandse
-- regel uit de meertalige tabel.
--
-- Anders dan bij de H-zinnen staan de gecombineerde codes hier WEL in de
-- verordening zelf (P301+P310 en zo'n dertig andere). Ze zijn dus gewoon
-- opgenomen, met de tekst zoals hij daar staat.
--
-- De drie puntjes in bijvoorbeeld P411 "Bij maximaal … °C bewaren" horen bij de
-- tekst: dat is de plaats die de leverancier invult. Weglaten zou de zin
-- veranderen in iets dat de verordening niet zegt.
--
-- ---------------------------------------------------------------------------
-- WAAROM EEN APARTE TABEL EN GEEN VRIJE TEKST PER PRODUCT
-- ---------------------------------------------------------------------------
-- Dezelfde reden als bij de gevaarzinnen: de codes staan bij het product, de
-- zinnen staan een keer. Verandert een formulering, dan verandert ze overal
-- tegelijk. En een lijst met codes laat zich vergelijken tussen producten; een
-- veld met overgetypte zinnen niet.
-- ---------------------------------------------------------------------------

create table if not exists voorzorgsmaatregelen (
  code text primary key,
  tekst text not null,
  -- Algemeen, Preventie, Reactie, Opslag of Verwijdering -- de vijf tabellen
  -- van bijlage IV. De app gebruikt deze indeling: bij een incident wil je
  -- alleen Reactie zien, niet de hele lijst.
  groep text not null,
  volgorde int not null default 0,
  bron text,
  actief boolean not null default true
);

alter table voorzorgsmaatregelen enable row level security;

create policy select_voorzorgsmaatregelen on voorzorgsmaatregelen
  for select to authenticated using (true);

create policy superbeheerder_schrijf_voorzorgsmaatregelen on voorzorgsmaatregelen
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

insert into voorzorgsmaatregelen (code, tekst, groep, volgorde) values
  ('P101', 'Bij het inwinnen van medisch advies, de verpakking of het etiket ter beschikking houden.', 'Algemeen', 10001),
  ('P102', 'Buiten het bereik van kinderen houden.', 'Algemeen', 10002),
  ('P103', 'Alvorens te gebruiken, het etiket lezen.', 'Algemeen', 10003),
  ('P201', 'Alvorens te gebruiken de speciale aanwijzingen raadplegen.', 'Preventie', 20001),
  ('P202', 'Pas gebruiken nadat u alle veiligheidsvoorschriften gelezen en begrepen heeft', 'Preventie', 20002),
  ('P210', 'Verwijderd houden van warmte, hete oppervlakken, vonken, open vuur en andere ontstekingsbronnen. Niet roken.', 'Preventie', 20003),
  ('P211', 'Niet in een open vuur of op andere ontstekingsbronnen spuiten.', 'Preventie', 20004),
  ('P212', 'Vermijd verwarming onder opsluiting of vermindering van de ongevoeligheidsagens.', 'Preventie', 20005),
  ('P220', 'Verwijderd houden van kleding en andere brandbare materialen.', 'Preventie', 20006),
  ('P222', 'Contact met de lucht vermijden.', 'Preventie', 20007),
  ('P223', 'Contact met water vermijden.', 'Preventie', 20008),
  ('P230', 'Vochtig houden met…', 'Preventie', 20009),
  ('P231', 'Inhoud onder inert gas/… gebruiken en bewaren.', 'Preventie', 20010),
  ('P232', 'Tegen vocht beschermen.', 'Preventie', 20011),
  ('P233', 'In goed gesloten verpakking bewaren.', 'Preventie', 20012),
  ('P234', 'Uitsluitend in de oorspronkelijke verpakking bewaren.', 'Preventie', 20013),
  ('P235', 'Koel bewaren.', 'Preventie', 20014),
  ('P240', 'Opslag- en opvangreservoir aarden.', 'Preventie', 20015),
  ('P241', 'Explosieveilige [elektrische/ventilatie-/verlichtings-/…]apparatuur gebruiken.', 'Preventie', 20016),
  ('P242', 'Vonkvrij gereedschap gebruiken.', 'Preventie', 20017),
  ('P243', 'Maatregelen treffen om ontladingen van statische elektriciteit te voorkomen.', 'Preventie', 20018),
  ('P244', 'Houd afsluiters en fittingen vrij van olie en vet.', 'Preventie', 20019),
  ('P250', 'Malen/schokken/wrijving/… vermijden.', 'Preventie', 20020),
  ('P251', 'Ook na gebruik niet doorboren of verbranden.', 'Preventie', 20021),
  ('P260', 'Stof/rook/gas/nevel/damp/spuitnevel niet inademen.', 'Preventie', 20022),
  ('P261', 'Inademing van stof/rook/gas/nevel/damp/spuitnevel vermijden.', 'Preventie', 20023),
  ('P262', 'Contact met de ogen, de huid of de kleding vermijden.', 'Preventie', 20024),
  ('P263', 'Bij zwangerschap of borstvoeding aanraking vermijden.', 'Preventie', 20025),
  ('P264', 'Na het werken met dit product … grondig wassen.', 'Preventie', 20026),
  ('P270', 'Niet eten, drinken of roken tijdens het gebruik van dit product.', 'Preventie', 20027),
  ('P271', 'Alleen buiten of in een goed geventileerde ruimte gebruiken.', 'Preventie', 20028),
  ('P272', 'Verontreinigde werkkleding mag de werkruimte niet verlaten.', 'Preventie', 20029),
  ('P273', 'Voorkom lozing in het milieu.', 'Preventie', 20030),
  ('P280', 'Beschermende handschoenen/beschermende kleding/oogbescherming/gelaatsbescherming dragen.', 'Preventie', 20031),
  ('P282', 'Koude-isolerende handschoenen en hetzij gelaatsbescherming hetzij oogbescherming dragen.', 'Preventie', 20032),
  ('P283', 'Vuurbestendige of vlamvertragende kleding dragen.', 'Preventie', 20033),
  ('P284', '[Bij ontoereikende ventilatie] adembescherming dragen.', 'Preventie', 20034),
  ('P231+P232', 'Inhoud onder inert gas/… gebruiken en bewaren. Tegen vocht beschermen.', 'Preventie', 20035),
  ('P301', 'NA INSLIKKEN:', 'Reactie', 30001),
  ('P302', 'BIJ CONTACT MET DE HUID:', 'Reactie', 30002),
  ('P303', 'BIJ CONTACT MET DE HUID (of het haar):', 'Reactie', 30003),
  ('P304', 'NA INADEMING:', 'Reactie', 30004),
  ('P305', 'BIJ CONTACT MET DE OGEN:', 'Reactie', 30005),
  ('P306', 'NA MORSEN OP KLEDING:', 'Reactie', 30006),
  ('P308', 'NA (mogelijke) blootstelling:', 'Reactie', 30007),
  ('P310', 'Onmiddellijk een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30008),
  ('P311', 'Een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30009),
  ('P312', 'Bij onwel voelen een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30010),
  ('P313', 'Een arts raadplegen.', 'Reactie', 30011),
  ('P314', 'Bij onwel voelen een arts raadplegen.', 'Reactie', 30012),
  ('P315', 'Onmiddellijk een arts raadplegen.', 'Reactie', 30013),
  ('P320', 'Specifieke behandeling dringend vereist (zie … op dit etiket).', 'Reactie', 30014),
  ('P321', 'Specifieke behandeling vereist (zie … op dit etiket).', 'Reactie', 30015),
  ('P330', 'De mond spoelen.', 'Reactie', 30016),
  ('P331', 'GEEN braken opwekken.', 'Reactie', 30017),
  ('P332', 'Bij huidirritatie:', 'Reactie', 30018),
  ('P333', 'Bij huidirritatie of uitslag:', 'Reactie', 30019),
  ('P334', 'In koud water onderdompelen [of nat verband aanbrengen].', 'Reactie', 30020),
  ('P335', 'Losse deeltjes van de huid afvegen.', 'Reactie', 30021),
  ('P336', 'Bevroren lichaamsdelen met lauw water ontdooien. Niet wrijven op de betrokken plaatsen.', 'Reactie', 30022),
  ('P337', 'Bij aanhoudende oogirritatie:', 'Reactie', 30023),
  ('P338', 'Contactlenzen verwijderen, indien mogelijk. Blijven spoelen.', 'Reactie', 30024),
  ('P340', 'De persoon in de frisse lucht brengen en ervoor zorgen dat deze gemakkelijk kan ademen.', 'Reactie', 30025),
  ('P342', 'Bij ademhalingssymptomen:', 'Reactie', 30026),
  ('P351', 'Voorzichtig afspoelen met water gedurende een aantal minuten.', 'Reactie', 30027),
  ('P352', 'Met veel water/… wassen.', 'Reactie', 30028),
  ('P353', 'Huid met water afspoelen [of afdouchen].', 'Reactie', 30029),
  ('P360', 'Verontreinigde kleding en huid onmiddellijk met veel water afspoelen en pas daarna kleding uittrekken.', 'Reactie', 30030),
  ('P361', 'Verontreinigde kleding onmiddellijk uittrekken.', 'Reactie', 30031),
  ('P362', 'Verontreinigde kleding uittrekken.', 'Reactie', 30032),
  ('P363', 'Verontreinigde kleding wassen alvorens deze opnieuw te gebruiken.', 'Reactie', 30033),
  ('P364', 'En wassen alvorens deze opnieuw te gebruiken.', 'Reactie', 30034),
  ('P370', 'In geval van brand:', 'Reactie', 30035),
  ('P371', 'In geval van grote brand en grote hoeveelheden:', 'Reactie', 30036),
  ('P372', 'Ontploffingsgevaar.', 'Reactie', 30037),
  ('P373', 'NIET blussen wanneer het vuur de ontplofbare stoffen bereikt.', 'Reactie', 30038),
  ('P375', 'Op afstand blussen omwille van ontploffingsgevaar.', 'Reactie', 30039),
  ('P376', 'Het lek dichten als dat veilig gedaan kan worden.', 'Reactie', 30040),
  ('P377', 'Brand door lekkend gas: niet blussen, tenzij het lek veilig gedicht kan worden.', 'Reactie', 30041),
  ('P378', 'Blussen met …', 'Reactie', 30042),
  ('P380', 'Evacueren.', 'Reactie', 30043),
  ('P381', 'In geval van lekkage alle ontstekingsbronnen wegnemen.', 'Reactie', 30044),
  ('P390', 'Gelekte/gemorste stof opnemen om materiële schade te vermijden.', 'Reactie', 30045),
  ('P391', 'Gelekte/gemorste stof opruimen.', 'Reactie', 30046),
  ('P301+P310', 'NA INSLIKKEN: onmiddellijk een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30047),
  ('P301+P312', 'NA INSLIKKEN: bij onwel voelen een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30048),
  ('P302+P334', 'BIJ CONTACT MET DE HUID: in koud water onderdompelen of nat verband aanbrengen.', 'Reactie', 30049),
  ('P302+P352', 'BIJ CONTACT MET DE HUID: met veel water/… wassen.', 'Reactie', 30050),
  ('P304+P340', 'NA INADEMING: de persoon in de frisse lucht brengen en ervoor zorgen dat deze gemakkelijk kan ademen.', 'Reactie', 30051),
  ('P306+P360', 'NA MORSEN OP KLEDING: verontreinigde kleding en huid onmiddellijk met veel water afspoelen en pas daarna kleding uittrekken.', 'Reactie', 30052),
  ('P308+P311', 'NA (mogelijke) blootstelling: een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30053),
  ('P308+P313', 'NA (mogelijke) blootstelling: een arts raadplegen.', 'Reactie', 30054),
  ('P332+P313', 'Bij huidirritatie: een arts raadplegen.', 'Reactie', 30055),
  ('P333+P313', 'Bij huidirritatie of uitslag: een arts raadplegen.', 'Reactie', 30056),
  ('P336+P315', 'Bevroren lichaamsdelen met lauw water ontdooien. Niet wrijven. Onmiddellijk een arts raadplegen.', 'Reactie', 30057),
  ('P337+P313', 'Bij aanhoudende oogirritatie: een arts raadplegen.', 'Reactie', 30058),
  ('P342+P311', 'Bij ademhalingssymptomen: een ANTIGIFCENTRUM/arts/… raadplegen.', 'Reactie', 30059),
  ('P361+P364', 'Verontreinigde kleding onmiddellijk uittrekken en wassen alvorens deze opnieuw te gebruiken.', 'Reactie', 30060),
  ('P362+P364', 'Verontreinigde kleding uittrekken en wassen alvorens deze opnieuw te gebruiken.', 'Reactie', 30061),
  ('P370+P376', 'In geval van brand: het lek dichten als dat veilig gedaan kan worden.', 'Reactie', 30062),
  ('P370+P378', 'In geval van brand: blussen met …', 'Reactie', 30063),
  ('P301+P330+P331', 'NA INSLIKKEN: de mond spoelen. GEEN braken opwekken.', 'Reactie', 30064),
  ('P302+P335+P334', 'BIJ CONTACT MET DE HUID: losse deeltjes van de huid afvegen. In koud water onderdompelen [of nat verband aanbrengen].', 'Reactie', 30065),
  ('P303+P361+P353', 'BIJ CONTACT MET DE HUID (of het haar): verontreinigde kleding onmiddellijk uittrekken. Huid met water afspoelen [of afdouchen].', 'Reactie', 30066),
  ('P305+P351+P338', 'BIJ CONTACT MET DE OGEN: voorzichtig afspoelen met water gedurende een aantal minuten; contactlenzen verwijderen, indien mogelijk; blijven spoelen.', 'Reactie', 30067),
  ('P370+P380+P375', 'In geval van brand: evacueren. Op afstand blussen omwille van ontploffingsgevaar.', 'Reactie', 30068),
  ('P371+P380+P375', 'In geval van grote brand en grote hoeveelheden: evacueren. Op afstand blussen omwille van ontploffingsgevaar.', 'Reactie', 30069),
  ('P401', 'Overeenkomstig … bewaren.', 'Opslag', 40001),
  ('P402', 'Op een droge plaats bewaren.', 'Opslag', 40002),
  ('P403', 'Op een goed geventileerde plaats bewaren.', 'Opslag', 40003),
  ('P404', 'In gesloten verpakking bewaren.', 'Opslag', 40004),
  ('P405', 'Achter slot bewaren.', 'Opslag', 40005),
  ('P406', 'In corrosiebestendige/… houder met corrosiebestendige binnenbekleding bewaren.', 'Opslag', 40006),
  ('P407', 'Ruimte laten tussen stapels of pallets.', 'Opslag', 40007),
  ('P410', 'Tegen zonlicht beschermen.', 'Opslag', 40008),
  ('P411', 'Bij maximaal … °C/… °F bewaren.', 'Opslag', 40009),
  ('P412', 'Niet blootstellen aan temperaturen boven 50 °C/122 °F.', 'Opslag', 40010),
  ('P413', 'Bulkmateriaal, indien meer dan … kg/… lbs, bij temperaturen van maximaal … °C bewaren.', 'Opslag', 40011),
  ('P420', 'Gescheiden bewaren.', 'Opslag', 40012),
  ('P402+P404', 'Op een droge plaats bewaren. In gesloten verpakking bewaren.', 'Opslag', 40013),
  ('P403+P233', 'Op een goed geventileerde plaats bewaren. In goed gesloten verpakking bewaren.', 'Opslag', 40014),
  ('P403+P235', 'Op een goed geventileerde plaats bewaren. Koel bewaren.', 'Opslag', 40015),
  ('P410+P403', 'Tegen zonlicht beschermen. Op een goed geventileerde plaats bewaren.', 'Opslag', 40016),
  ('P410+P412', 'Tegen zonlicht beschermen. Niet blootstellen aan temperaturen boven 50 °C/122 °F.', 'Opslag', 40017),
  ('P501', 'Inhoud/verpakking afvoeren naar …', 'Verwijdering', 50001),
  ('P502', 'Raadpleeg fabrikant of leverancier voor informatie over terugwinning of recycling.', 'Verwijdering', 50002)
on conflict (code) do update set
  tekst    = excluded.tekst,
  groep    = excluded.groep,
  volgorde = excluded.volgorde,
  bron     = excluded.bron,
  actief   = true;

update voorzorgsmaatregelen
   set bron = 'CLP bijlage IV, geconsolideerde tekst 01.02.2025'
 where bron is null;


-- ---------------------------------------------------------------------------
-- De codes bij een product
-- ---------------------------------------------------------------------------
-- Naast h_zinnen. Dezelfde vorm, dezelfde afspraak: codes hier, zinnen daar.
alter table chemische_producten
  add column if not exists p_zinnen text[] not null default '{}';

comment on column chemische_producten.p_zinnen is
  'De voorzorgsmaatregelen van het etiket / VIB rubriek 2. Codes, geen zinnen.';


-- ---------------------------------------------------------------------------
-- De tekst bij een P-code opzoeken
-- ---------------------------------------------------------------------------
-- Eenvoudiger dan bij de H-zinnen: de gecombineerde codes staan hier gewoon in
-- de lijst. Enkel de spaties eromheen worden weggehaald, want op een blad staat
-- soms "P301 + P310" en soms "P301+P310".
create or replace function public.voorzorg_tekst(p_code text)
returns text
language sql
stable
set search_path = public
as $$
  select tekst from voorzorgsmaatregelen
  where code = replace(btrim(p_code), ' ', '') and actief;
$$;

grant execute on function public.voorzorg_tekst(text) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- rpc_chemie_product: pictogrammen en voorzorgsmaatregelen erbij
-- ---------------------------------------------------------------------------
-- Alleen het onderste stuk verandert. De rest staat er ongewijzigd, want een
-- create or replace vervangt de hele functie.
--
-- De voorzorgsmaatregelen komen gegroepeerd terug. Bij een incident wil iemand
-- niet de volledige lijst zien maar wat hij nu moet doen; die volgorde zit al
-- in de kolom volgorde en wordt hier aangehouden.
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
    -- Een code waarvan de tekst niet gevonden wordt, blijft als code staan.
    -- Weglaten zou erger zijn: dan toont de app een product als ongevaarlijk
    -- omdat wij een zin missen.
    'gevaren', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code',   t.code,
               'tekst',  public.gevaarzin_tekst(t.code),
               'titel2', public.valt_onder_titel2(array[t.code]))
             order by t.code)
      from unnest(v_p.h_zinnen) as t(code)
    ), '[]'::jsonb),
    'voorzorg', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code',  t.code,
               'tekst', v.tekst,
               'groep', coalesce(v.groep, 'Overig'))
             order by coalesce(v.volgorde, 999999), t.code)
      from unnest(v_p.p_zinnen) as t(code)
      left join voorzorgsmaatregelen v
        on v.code = replace(btrim(t.code), ' ', '') and v.actief
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.rpc_chemie_product(uuid, uuid) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- Het demobedrijf: pictogrammen en voorzorgsmaatregelen invullen
-- ---------------------------------------------------------------------------
-- Zonder dit staat er in de demo een leeg vak waar het net om draait. Dezelfde
-- waarden staan voortaan ook in 0091, zodat een reset ze behoudt.
--
-- De pictogrammen zijn niet verzonnen maar volgen uit de indeling. Bij de
-- roestomvormer staat alleen GHS05 en niet ook GHS07: artikel 26 zegt dat het
-- uitroepteken wegvalt zodra het bijtende teken er staat. Dat is precies het
-- soort regel dat een klant nooit zelf toepast, en waarom dit hier per product
-- ingevuld wordt in plaats van afgeleid uit de H-zinnen.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
begin
  if not exists (select 1 from chemische_producten where bedrijf_id = v_bedrijf) then
    raise notice 'Geen demoproducten gevonden; niets ingevuld.';
    return;
  end if;

  update chemische_producten set pictogrammen = array['GHS07'],
    p_zinnen = array['P261','P271','P280','P302+P352','P305+P351+P338']
   where bedrijf_id = v_bedrijf and naam = 'Ontvetter X-200';

  update chemische_producten set pictogrammen = array['GHS02','GHS07'],
    p_zinnen = array['P210','P211','P251','P280','P410+P412']
   where bedrijf_id = v_bedrijf and naam = 'Antispatspray lasposten';

  update chemische_producten set pictogrammen = array['GHS08','GHS07'],
    p_zinnen = array['P261','P272','P280','P284','P302+P352','P342+P311']
   where bedrijf_id = v_bedrijf and naam = 'Tweecomponentenlijm PU';

  update chemische_producten set pictogrammen = array['GHS05','GHS08'],
    p_zinnen = array['P260','P280','P301+P330+P331','P303+P361+P353','P305+P351+P338','P310']
   where bedrijf_id = v_bedrijf and naam = 'Roestomvormer';

  update chemische_producten set pictogrammen = array['GHS07'],
    p_zinnen = array['P261','P272','P280','P302+P352','P333+P313']
   where bedrijf_id = v_bedrijf and naam = 'Koelsmeermiddel';

  update chemische_producten set pictogrammen = array['GHS08','GHS07'],
    p_zinnen = array['P201','P280','P302+P352','P308+P313']
   where bedrijf_id = v_bedrijf and naam = 'Chroomhoudende primer';

  raise notice 'Demoproducten aangevuld met pictogrammen en voorzorgsmaatregelen.';
end
$$;


-- ---------------------------------------------------------------------------
-- Controle
-- ---------------------------------------------------------------------------
do $$
declare
  v_totaal int;
  v_groepen int;
begin
  select count(*), count(distinct groep) into v_totaal, v_groepen
  from voorzorgsmaatregelen where actief;
  raise notice 'Voorzorgsmaatregelen: % codes in % groepen.', v_totaal, v_groepen;
end
$$;

notify pgrst, 'reload schema';
