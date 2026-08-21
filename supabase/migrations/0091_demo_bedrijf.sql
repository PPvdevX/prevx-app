-- ===========================================================================
-- 0091_demo_bedrijf.sql -- een volledig gevulde demonstratieklant
-- ===========================================================================
-- Doel: een klantdossier dat je aan een prospect kan tonen zonder dat er ook
-- maar iets van een echte klant in beeld komt. Alles hieronder is verzonnen:
-- bedrijf, mensen, assets, vaststellingen, keuringen, documenten.
--
-- BELANGRIJK -- DIT SCRIPT IS HERBRUIKBAAR EN WIST EERST ZICHZELF.
-- Elke uitvoering gooit alles van het demobedrijf weg en bouwt het opnieuw op.
-- Dat is met opzet: na een demo staat er van alles in (een prospect die zelf
-- geklikt heeft, een testvergunning, een halve inspectie) en voor de volgende
-- demo wil je een propere start. Draai dit script dan gewoon opnieuw.
--
-- Twee dingen overleven zo'n reset met opzet: de huisstijl van het bedrijf (de
-- rij in bedrijven wordt bijgewerkt, niet gewist) en de veiligheidsinformatie-
-- bladen die je bij een chemisch product hebt opgeladen -- dat bestand ligt al
-- in de opslag, en het opnieuw moeten opladen zou werk zijn zonder reden.
--
-- Het raakt NOOIT een ander bedrijf aan: elke delete en elke insert is gescoopt
-- op één vast bedrijf-id (dddddddd-...). Dat id ligt vast zodat een tweede
-- uitvoering hetzelfde dossier hergebruikt in plaats van een tweede
-- demobedrijf te maken.
--
-- ---------------------------------------------------------------------------
-- WAT JE ZELF NOG MOET DOEN (één keer)
-- ---------------------------------------------------------------------------
-- 1. Maak in Supabase Dashboard > Authentication > Users een gebruiker aan met
--    e-mailadres  demo@prevx.be  en een wachtwoord naar keuze. Dat wachtwoord
--    hoort niet in dit bestand: een repository is geen kluis, en deze staat
--    bovendien publiek.
--    Een ander adres? Pas v_login_email in BLOK 1 aan.
-- 2. Draai dit script (SQL Editor). Het koppelt dat auth-account automatisch
--    aan de demobeheerder. Bestaat het account nog niet, dan zegt het script
--    dat in een NOTICE; doe stap 1 dan alsnog en draai het script opnieuw.
--
-- ---------------------------------------------------------------------------
-- INLOGGEGEVENS VAN DE DEMO
-- ---------------------------------------------------------------------------
--   Mijn PrevX (account.html):  demo@prevx.be + het wachtwoord uit stap 1
--   App (app.html):             klantcode DEMO
--                                 1111 -- Kevin De Smet (Niveau 4)
--                                 2222 -- Younes El Amrani (Niveau 4)
--                                 4444 -- Marc Delrue (Niveau 4)
--                                 3333 -- Nele Coppens (Niveau 3; keurt
--                                         vuurvergunningen goed)
--
-- Die vier pincodes zijn de gewénste codes. De kolom pincode dateert van vóór
-- de klantcode-login en is platformbreed uniek; is er dus bij een echte klant
-- al iemand met 1111, dan schuift de demo een code op in plaats van halverwege
-- te crashen. Wat het uiteindelijk geworden is, drukt het script onderaan af
-- (BLOK 7, in het NOTICE-venster van de SQL Editor). Kijk daar dus altijd even.
--
-- Klantcode "DEMO" is bewust kort en typbaar: op de gsm van een prospect wil je
-- geen zes willekeurige tekens moeten intikken. Ze is daardoor ook raadbaar --
-- vandaar dat er achter die code niets anders zit dan verzonnen gegevens. Wil
-- je dat niet, zet er dan een minder voor de hand liggende code neer; het veld
-- is vrije tekst en moet enkel uniek zijn.
--
-- ---------------------------------------------------------------------------
-- WAAROM ER GEEN ECHTE E-MAILADRESSEN IN STAAN
-- ---------------------------------------------------------------------------
-- Alle demogebruikers behalve de beheerder hebben e-mail NULL, en het bedrijf
-- gebruikt example.com (RFC 2606: dat domein kan nooit van iemand zijn). Zo kan
-- een verkeerde klik -- "Nodig uit voor Mijn PrevX", een notificatie -- nooit
-- post sturen naar een adres dat toevallig wél bestaat. Bounces kosten
-- reputatie op een afzenddomein dat we voor echte klanten nodig hebben.
--
-- Om dezelfde reden staat er op geen enkele asset een notificatie-adres en
-- worden er geen nazorgherinneringen aangemaakt: die zouden via de cron
-- effectief mail proberen te versturen. De inspecties worden rechtstreeks
-- ingevoegd en niet via rpc_verzend_inspectie, juist omdat die functie een
-- e-mail op gang trekt.
--
-- Alle datums staan relatief tegenover current_date, zodat het dossier over
-- drie maanden nog altijd actueel oogt.
--
-- ---------------------------------------------------------------------------
-- MIGRATIES DIE NOG NIET GEDRAAID ZIJN
-- ---------------------------------------------------------------------------
-- Twee onderdelen hangen af van migraties die er misschien nog niet in staan:
-- het brandpreventiedossier (0088) en locatie/melder op een melding (0090).
-- Ontbreken die, dan slaat het script juist dat stukje over met een NOTICE in
-- plaats van te crashen -- de rest van de demo staat er dan gewoon. Draai je die
-- migratie later alsnog, draai dan ook dit script opnieuw: het onderdeel komt er
-- dan bij.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- BLOK 1 -- opruimen, bedrijf, mensen, assets, checklist
-- ---------------------------------------------------------------------------
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_login_email text := 'demo@prevx.be';
  v_auth uuid;

  v_beheerder uuid;
  v_adviseur uuid;
  v_leiding uuid;
  v_ch1 uuid;
  v_ch2 uuid;
  v_ch3 uuid;

  v_t_bestel uuid;
  v_t_heftruck uuid;
  v_t_hoogwerker uuid;
  v_t_aanhang uuid;
  v_t_werkpost uuid;
  v_t_zone uuid;

  v_a_bestel1 uuid;
  v_a_bestel2 uuid;
  v_a_heftruck1 uuid;
  v_a_heftruck2 uuid;
  v_a_hoogwerker uuid;
  v_a_aanhang uuid;

  v_sectie uuid;

  -- De gewenste pincodes, in de volgorde waarin ze hieronder toegekend worden:
  -- beheerder, preventieadviseur, leidinggevende, en dan de vier chauffeurs.
  v_gewenst text[] := array['9911','9922','3333','1111','2222','4444','8888'];
  v_pin text[] := '{}';
  v_kandidaat text;
  v_poging int;
begin
  -- Deze vlag laat de trigger op vergunning_antwoorden toe dat antwoorden van
  -- een AFGESLOTEN vergunning verdwijnen. Buiten dit soort opruimwerk blijft
  -- een afgesloten dossier onwijzigbaar (zie 0057 en 0064). De vlag geldt enkel
  -- binnen deze transactie.
  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  -- --- opruimen, in de volgorde van de verwijzingen ------------------------
  delete from vergunning_herinneringen
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = v_bedrijf);
  delete from vergunning_goedkeuring_codes
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = v_bedrijf);
  delete from vergunning_antwoorden
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = v_bedrijf);
  delete from vuurvergunningen where bedrijf_id = v_bedrijf;
  delete from vergunning_nummers where bedrijf_id = v_bedrijf;
  delete from vergunning_vraag_werktypes
    where vraag_id in (select id from vergunning_vragen where bedrijf_id = v_bedrijf);
  delete from vergunning_vragen where bedrijf_id = v_bedrijf;
  delete from werktypes where bedrijf_id = v_bedrijf;

  delete from lmra_risico_antwoorden
    where lmra_id in (select id from lmras where bedrijf_id = v_bedrijf);
  delete from lmras where bedrijf_id = v_bedrijf;
  delete from bedrijf_lmra_risicos where bedrijf_id = v_bedrijf;

  delete from inspectie_resultaten
    where inspectie_id in (select id from inspecties where bedrijf_id = v_bedrijf);
  delete from inspecties where bedrijf_id = v_bedrijf;
  delete from inspectie_punt_types
    where punt_id in (
      select p.id from inspectie_punten p
      join inspectie_secties s on s.id = p.sectie_id
      where s.bedrijf_id = v_bedrijf);
  delete from inspectie_sectie_types
    where sectie_id in (select id from inspectie_secties where bedrijf_id = v_bedrijf);
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = v_bedrijf);
  delete from inspectie_secties where bedrijf_id = v_bedrijf;

  delete from keuringen where bedrijf_id = v_bedrijf;
  delete from gebruiker_voertuigen
    where voertuig_id in (select id from voertuigen where bedrijf_id = v_bedrijf);
  delete from voertuigen where bedrijf_id = v_bedrijf;
  delete from voertuig_types where bedrijf_id = v_bedrijf;

  -- Meldingen vóór actiepunten: een melding kan naar een actiepunt wijzen.
  delete from meldingen where bedrijf_id = v_bedrijf;
  delete from actiepunten where bedrijf_id = v_bedrijf;
  -- Planning vóór documenten: een afspraak kan naar een verslag wijzen.
  delete from planning where bedrijf_id = v_bedrijf;
  delete from documenten where bedrijf_id = v_bedrijf;
  -- De teller mee resetten, anders loopt de demo op termijn tot RPT-047.
  delete from document_nummers where bedrijf_id = v_bedrijf;

  delete from bedrijf_kennisbank where bedrijf_id = v_bedrijf;
  -- Chemische agentia wordt hier NIET opgekuist. Die producten ruimt blok 4B
  -- zelf op, omdat het de verwijzingen naar opgeladen veiligheidsinformatiebladen
  -- eerst opzij moet zetten. Zie de uitleg daar.
  if to_regclass('public.vragen') is not null then
    delete from vragen where bedrijf_id = v_bedrijf;
  end if;
  -- Het brandpreventiedossier komt uit 0088. Staat die migratie nog niet in de
  -- databank, dan slaan we dat onderdeel over in plaats van hier te crashen: de
  -- demo mag niet afhangen van de volgorde waarin jij je migraties uitvoert.
  -- PL/pgSQL ontleedt een SQL-opdracht pas bij de eerste uitvoering, dus de
  -- regel hieronder stoort niet zolang de tak niet genomen wordt.
  if to_regclass('public.brandpreventie_status') is not null then
    delete from brandpreventie_status where bedrijf_id = v_bedrijf;
  end if;
  delete from samenwerking where bedrijf_id = v_bedrijf;
  delete from bedrijf_kpis where bedrijf_id = v_bedrijf;
  delete from bedrijf_modules where bedrijf_id = v_bedrijf;

  delete from pincode_reset_codes
    where gebruiker_id in (select id from gebruikers where bedrijf_id = v_bedrijf);
  delete from gebruikers where bedrijf_id = v_bedrijf;

  -- --- het bedrijf ---------------------------------------------------------
  -- De rij zelf blijft tussen twee uitvoeringen door bestaan (upsert), zodat
  -- een aangepaste huisstijl en de klantcode standhouden.
  insert into bedrijven (id, naam, klantcode)
  values (v_bedrijf, 'Demo Metaal & Techniek BV', 'DEMO')
  on conflict (id) do update set naam = excluded.naam;

  update bedrijven set
    juridische_benaming = 'Demo Metaal & Techniek BV',
    handelsnaam         = 'Demo Metaal & Techniek',
    klantcode           = 'DEMO',
    btw_nummer          = 'BE 0999.999.999',
    adres               = 'Nijverheidslaan 42, 8800 Roeselare',
    vestigingsadres_1   = 'Nijverheidslaan 42, 8800 Roeselare (productie)',
    vestigingsadres_2   = 'Ambachtstraat 7, 8870 Izegem (magazijn)',
    telefoon            = '+32 51 00 00 00',
    email_algemeen      = 'info@example.com',
    website             = 'www.example.com',
    contact_naam        = 'Sofie Delaere',
    functie_hoofdcontact= 'Zaakvoerder',
    contact_gsm         = '+32 470 00 00 00',
    contact_email       = 'sofie.delaere@example.com',
    ops_contact         = 'Nele Coppens',
    functie_ops_contact = 'Productieverantwoordelijke',
    mail_ops_contact    = 'nele.coppens@example.com',
    hr_contact          = 'Sofie Delaere',
    functie_hr_contact  = 'Zaakvoerder',
    mail_hr_contact     = 'sofie.delaere@example.com',
    sector              = 'Metaalverwerking en onderhoud',
    sector_categorie    = 'Industrie',
    paritair_comite     = '111.01',
    aantal_werknemers   = '24',
    status              = 'actief',
    klantnummer         = 'DEMO',
    pakket              = 'PrevX Partner - Standaard',
    type_samenwerking   = 'Externe preventieadviseur',
    contract_startdatum = date_trunc('year', current_date)::date,
    contract_einddatum  = (date_trunc('year', current_date) + interval '1 year - 1 day')::date,
    verlengingsdatum    = (date_trunc('year', current_date) + interval '1 year')::date,
    opzegtermijn        = '3 maanden',
    betalingstermijn    = '30 dagen einde maand',
    interne_preventieadviseur = 'Nele Coppens',
    niveau_preventieadviseur  = 'Niveau 3',
    mail_preventieadviseur    = 'nele.coppens@example.com',
    edpbw               = 'Externe dienst (demo)',
    arbeidsongevallenverzekeraar = 'Verzekeraar (demo)',
    cpbw                = 'Geen CPBW (minder dan 50 werknemers)',
    groep               = 'Zelfstandig',
    vrije_informatie    = 'DEMODOSSIER -- alle gegevens hierin zijn verzonnen en dienen enkel om PrevX te tonen.',
    afzender_email      = null
  where id = v_bedrijf;

  -- --- modules: alles aan, want een demo moet alles kunnen tonen -----------
  insert into bedrijf_modules (bedrijf_id, module_key, actief)
  select v_bedrijf, k, true
  from unnest(array['preinspecties','vuurvergunning','lmra','actiepunten',
                    'planning','documenten','meldingen','kennisbank','chemie']) as k
  on conflict (bedrijf_id, module_key) do update set actief = true;

  -- --- vrije pincodes zoeken ----------------------------------------------
  -- De kolom pincode dateert van vóór de klantcode-login (0052) en is
  -- platformbreed uniek. Zit er bij een echte klant al iemand op 1111, dan
  -- crasht een vaste demopincode het hele script. Daarom: opschuiven tot er een
  -- vrije code is. Met stappen van 1111 (1111 wordt 2222 wordt 3333), want een
  -- code die je tijdens een demo foutloos intikt is meer waard dan een code die
  -- er mooi uitziet. Dit moet ná de deletes hierboven: zo komen de codes van de
  -- vorige demo weer vrij.
  foreach v_kandidaat in array v_gewenst loop
    v_poging := 0;
    while exists (select 1 from gebruikers where pincode = v_kandidaat)
       or v_kandidaat = any (v_pin) loop
      v_poging := v_poging + 1;
      if v_poging > 30 then
        raise exception 'Geen vrije pincode gevonden in de buurt van %', v_kandidaat;
      end if;
      v_kandidaat := lpad(((v_kandidaat::int + 1111) % 10000)::text, 4, '0');
    end loop;
    v_pin := array_append(v_pin, v_kandidaat);
  end loop;

  -- --- mensen --------------------------------------------------------------
  -- De rolsleutels blijven de oude (beheerder / preventieadviseur /
  -- leidinggevende / chauffeur); in de schermen heten ze Niveau 1 t.e.m. 4.
  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief, dossier_rol)
  values (v_bedrijf, 'Sofie Delaere', 'beheerder', v_pin[1], v_login_email, true, 'klant_beheerder')
  returning id into v_beheerder;

  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief, dossier_rol)
  values (v_bedrijf, 'Bart Vermeulen', 'preventieadviseur', v_pin[2], null, true, 'klant_medewerker')
  returning id into v_adviseur;

  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief, dossier_rol)
  values (v_bedrijf, 'Nele Coppens', 'leidinggevende', v_pin[3], null, true, 'klant_medewerker')
  returning id into v_leiding;

  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief)
  values (v_bedrijf, 'Kevin De Smet', 'chauffeur', v_pin[4], null, true)
  returning id into v_ch1;

  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief)
  values (v_bedrijf, 'Younes El Amrani', 'chauffeur', v_pin[5], null, true)
  returning id into v_ch2;

  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief)
  values (v_bedrijf, 'Marc Delrue', 'chauffeur', v_pin[6], null, true)
  returning id into v_ch3;

  -- Eén niet-actieve medewerker, zodat het scherm ook die toestand toont.
  insert into gebruikers (bedrijf_id, naam, rol, pincode, email, actief)
  values (v_bedrijf, 'Tom Baert', 'chauffeur', v_pin[7], null, false);

  -- --- het auth-account koppelen -------------------------------------------
  select id into v_auth from auth.users where lower(email) = lower(v_login_email) limit 1;
  if v_auth is null then
    raise notice 'Geen auth-account gevonden voor %. Maak het aan via Dashboard > Authentication > Users en draai dit script daarna opnieuw.', v_login_email;
  else
    update gebruikers set auth_user_id = v_auth where id = v_beheerder;
    raise notice 'Auth-account % gekoppeld aan de demobeheerder.', v_login_email;
  end if;

  -- --- assets --------------------------------------------------------------
  insert into voertuig_types (bedrijf_id, naam, volgorde) values (v_bedrijf, 'Bestelwagen', 10)   returning id into v_t_bestel;
  insert into voertuig_types (bedrijf_id, naam, volgorde) values (v_bedrijf, 'Heftruck', 20)      returning id into v_t_heftruck;
  insert into voertuig_types (bedrijf_id, naam, volgorde) values (v_bedrijf, 'Hoogwerker', 30)    returning id into v_t_hoogwerker;
  insert into voertuig_types (bedrijf_id, naam, volgorde) values (v_bedrijf, 'Aanhangwagen', 40)  returning id into v_t_aanhang;
  -- Werkpost en Zone zijn voor de checklistmotor gewone assettypes. Daarmee
  -- dekken ergonomie en verfraaiing zich met wat er al staat: een werkpost of
  -- een kleedkamer doorlopen is dezelfde handeling als een heftruck nakijken.
  insert into voertuig_types (bedrijf_id, naam, volgorde) values (v_bedrijf, 'Werkpost', 50) returning id into v_t_werkpost;
  insert into voertuig_types (bedrijf_id, naam, volgorde) values (v_bedrijf, 'Zone', 60)     returning id into v_t_zone;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, serienummer, type, type_id, actief)
  values (v_bedrijf, '1-DEM-001', 'Bestelwagen montageploeg noord', 'WF0DEMO2025001', 'Bestelwagen', v_t_bestel, true)
  returning id into v_a_bestel1;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, serienummer, type, type_id, actief)
  values (v_bedrijf, '1-DEM-002', 'Bestelwagen montageploeg zuid', 'WF0DEMO2025002', 'Bestelwagen', v_t_bestel, true)
  returning id into v_a_bestel2;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, serienummer, type, type_id, actief)
  values (v_bedrijf, 'HEF-01', 'Heftruck magazijn 2,5 ton', 'HT-2500-0001', 'Heftruck', v_t_heftruck, true)
  returning id into v_a_heftruck1;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, serienummer, type, type_id, actief)
  values (v_bedrijf, 'HEF-02', 'Heftruck productie 1,6 ton', 'HT-1600-0002', 'Heftruck', v_t_heftruck, true)
  returning id into v_a_heftruck2;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, serienummer, type, type_id, actief)
  values (v_bedrijf, 'HWK-01', 'Schaarhoogwerker 12 m', 'SL-12-77812', 'Hoogwerker', v_t_hoogwerker, true)
  returning id into v_a_hoogwerker;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, serienummer, type, type_id, actief)
  values (v_bedrijf, 'AHW-01', 'Aanhangwagen geremd 1350 kg', 'AH-1350-0224', 'Aanhangwagen', v_t_aanhang, true)
  returning id into v_a_aanhang;

  insert into voertuigen (bedrijf_id, nummerplaat, omschrijving, type, type_id, actief) values
    (v_bedrijf, 'WP-01', 'Lasplaats 1', 'Werkpost', v_t_werkpost, true),
    (v_bedrijf, 'WP-02', 'Slijpcabine', 'Werkpost', v_t_werkpost, true),
    (v_bedrijf, 'WP-03', 'Inpaktafel verzending', 'Werkpost', v_t_werkpost, true),
    (v_bedrijf, 'ZN-01', 'Kleedkamers en douches', 'Zone', v_t_zone, true),
    (v_bedrijf, 'ZN-02', 'Refter', 'Zone', v_t_zone, true),
    (v_bedrijf, 'ZN-03', 'Productiehal', 'Zone', v_t_zone, true);

  -- Wie ziet wat in de app. Kevin en Younes rijden, Marc doet het magazijn.
  insert into gebruiker_voertuigen (gebruiker_id, voertuig_id) values
    (v_ch1, v_a_bestel1), (v_ch1, v_a_aanhang),
    (v_ch2, v_a_bestel2), (v_ch2, v_a_hoogwerker),
    (v_ch3, v_a_heftruck1), (v_ch3, v_a_heftruck2),
    (v_leiding, v_a_bestel1), (v_leiding, v_a_heftruck1);

  -- --- checklist -----------------------------------------------------------
  -- Een sectie zonder type-koppeling geldt voor élk type (zie rpc_checklist).
  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Algemeen en documenten', 'documenten', 10, true) returning id into v_sectie;
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Is het toestel proper en vrij van zichtbare schade?', 10, 'informatief', true),
    (v_sectie, 'Zijn de boorddocumenten aanwezig?', 20, 'kritisch', true),
    (v_sectie, 'Is het laatste keuringsattest geldig?', 30, 'kritisch', true);

  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Verlichting en signalisatie', 'verlichting', 20, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id) values (v_sectie, v_t_bestel), (v_sectie, v_t_aanhang);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Werken dimlicht, grootlicht en achterlichten?', 10, 'kritisch', true),
    (v_sectie, 'Werken de richtingaanwijzers en de vier knipperlichten?', 20, 'kritisch', true),
    (v_sectie, 'Werken de remlichten?', 30, 'kritisch', true),
    (v_sectie, 'Is het zwaailicht in orde?', 40, 'informatief', true);

  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Banden en remmen', 'banden', 30, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id) values (v_sectie, v_t_bestel), (v_sectie, v_t_aanhang);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Is het profiel van de banden voldoende diep?', 10, 'kritisch', true),
    (v_sectie, 'Is de bandenspanning in orde?', 20, 'informatief', true),
    (v_sectie, 'Remt het voertuig recht en zonder ongewone geluiden?', 30, 'kritisch', true),
    (v_sectie, 'Houdt de handrem het voertuig op een helling?', 40, 'kritisch', true);

  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Hydrauliek en hefinrichting', 'gereedschap', 40, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id) values (v_sectie, v_t_heftruck), (v_sectie, v_t_hoogwerker);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Zijn de hydraulische leidingen lekvrij?', 10, 'kritisch', true),
    (v_sectie, 'Is het oliepeil in orde?', 20, 'informatief', true),
    (v_sectie, 'Zijn de vorken of het platform onbeschadigd?', 30, 'kritisch', true),
    (v_sectie, 'Werkt de hefinrichting vloeiend, zonder wegzakken?', 40, 'kritisch', true);

  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Veiligheidsvoorzieningen', 'veiligheid', 50, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id)
    values (v_sectie, v_t_heftruck), (v_sectie, v_t_hoogwerker), (v_sectie, v_t_bestel);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Werkt de noodstop?', 10, 'kritisch', true),
    (v_sectie, 'Werken de claxon en het achteruitrijsignaal?', 20, 'kritisch', true),
    (v_sectie, 'Is de gordel of het veiligheidsharnas in orde?', 30, 'kritisch', true),
    (v_sectie, 'Zijn de brandblusser en de EHBO-koffer aanwezig en geldig?', 40, 'kritisch', true);

  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Werkplatform', 'lading', 60, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id) values (v_sectie, v_t_hoogwerker);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Zijn de leuningen en het toegangshek onbeschadigd?', 10, 'kritisch', true),
    (v_sectie, 'Werkt de kantelbeveiliging of de hellingssensor?', 20, 'kritisch', true),
    (v_sectie, 'Is de belastingtabel leesbaar aanwezig?', 30, 'informatief', true);

  -- Ergonomie: wat je aan een werkpost bekijkt. Kort gehouden -- een lijst die
  -- niemand afwerkt, levert niets op.
  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Werkpost en houding', 'gereedschap', 70, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id) values (v_sectie, v_t_werkpost);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Staat het werkvlak op de juiste hoogte voor wie er werkt?', 10, 'kritisch', true),
    (v_sectie, 'Kan het werk afwisselend zittend en staand gebeuren?', 20, 'informatief', true),
    (v_sectie, 'Ligt alles wat vaak nodig is binnen handbereik, zonder draaien of reiken?', 30, 'kritisch', true),
    (v_sectie, 'Is er een tilhulp aanwezig voor lasten boven 25 kg?', 40, 'kritisch', true),
    (v_sectie, 'Is de verlichting op de werkpost voldoende en zonder verblinding?', 50, 'kritisch', true);

  -- Verfraaiing: de sociale voorzieningen en de staat van de arbeidsplaats.
  insert into inspectie_secties (bedrijf_id, naam, icon, volgorde, actief)
  values (v_bedrijf, 'Voorzieningen en netheid', 'algemeen', 80, true) returning id into v_sectie;
  insert into inspectie_sectie_types (sectie_id, voertuig_type_id) values (v_sectie, v_t_zone);
  insert into inspectie_punten (sectie_id, omschrijving, volgorde, niveau, actief) values
    (v_sectie, 'Zijn de kleedkamers en het sanitair proper en in orde?', 10, 'kritisch', true),
    (v_sectie, 'Is er drinkbaar water beschikbaar?', 20, 'kritisch', true),
    (v_sectie, 'Is de refter gescheiden van de werkzone?', 30, 'kritisch', true),
    (v_sectie, 'Zijn de gangen en nooduitgangen vrij van obstakels?', 40, 'kritisch', true),
    (v_sectie, 'Is de verlichting in de zone voldoende, ook bij donker weer?', 50, 'informatief', true),
    (v_sectie, 'Ligt er niets rond dat er niet hoort te liggen?', 60, 'informatief', true);

  -- --- KPI-selectie: de standaardvier, expliciet vastgelegd ---------------
  insert into bedrijf_kpis (bedrijf_id, kpi_key, volgorde, actief, label) values
    (v_bedrijf, 'inspecties_totaal',    0, true,  null),
    (v_bedrijf, 'dekking_gemiddeld',    1, true,  null),
    (v_bedrijf, 'signalen',             2, true,  null),
    (v_bedrijf, 'buiten_werkuren',      3, true,  null),
    (v_bedrijf, 'nok_totaal',         100, false, null),
    (v_bedrijf, 'nok_percentage',     101, false, null),
    (v_bedrijf, 'niet_rijklaar',      102, false, null),
    (v_bedrijf, 'rijklaar_percentage',103, false, null)
  on conflict (bedrijf_id, kpi_key) do nothing;
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 2 -- zes weken ingediende rapporten
-- ---------------------------------------------------------------------------
-- Rechtstreeks in de tabellen, niet via rpc_verzend_inspectie: die functie
-- stuurt na elke indiening een e-mail (0016). Honderd demo-rapporten zouden
-- honderd mails betekenen.
--
-- De handtekening is een SVG in de src zelf, geen bestand in Storage. Het
-- portaal haalt voor een private opslaglink een ondertekende URL op en valt
-- voor al de rest terug op de waarde zoals ze er staat (priveVerwijzing in
-- account.html) -- een data-URI komt dus gewoon in beeld, zonder dat we
-- bestanden moeten uploaden die bij een reset weer zouden blijven rondslingeren.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_sig text := 'data:image/svg+xml;utf8,<svg xmlns=''http://www.w3.org/2000/svg'' width=''220'' height=''70''><path d=''M12 50 C 30 14, 44 60, 62 33 S 92 10, 110 42 S 140 60, 168 22'' fill=''none'' stroke=''rgb(20,40,70)'' stroke-width=''2.5'' stroke-linecap=''round''/><path d=''M96 56 C 118 54, 140 56, 176 50'' fill=''none'' stroke=''rgb(20,40,70)'' stroke-width=''1.5'' stroke-linecap=''round''/></svg>';

  v_opmerkingen text[] := array[
    'Rechter achterlicht brandt niet meer. Gemeld aan de werkplaats.',
    'Profiel linkervoorband bijna op de merkstreep. Vervanging aangevraagd.',
    'Lichte olievlek onder de mast, moet nagekeken worden.',
    'Brandblusser vervalt volgende maand.',
    'Achteruitrijsignaal klinkt zwak.',
    'Gordel rolt niet vlot op.',
    'Kleine barst in de spiegelkap rechts.',
    'Beschermkap over de aftakas ontbreekt.'
  ];

  v_dag int;
  v_k record;
  v_punt record;
  v_inspectie uuid;
  v_verdict text;
  v_kans double precision;
  v_tijd time;
  v_moment timestamptz;
  v_start timestamptz;
  v_altijd_groen uuid;
  v_aantal int;
  v_index int;
  v_nok1 int;
  v_nok2 int;
  v_status text;
  v_opm text;
begin
  select id into v_altijd_groen from gebruikers
  where bedrijf_id = v_bedrijf and naam = 'Marc Delrue';

  for v_dag in reverse 41..0 loop
    -- Geen weekendinspecties: dat valt op in de grafiek en klopt niet met hoe
    -- een montageploeg werkt.
    continue when extract(isodow from current_date - v_dag) > 5;

    for v_k in
      select gv.gebruiker_id, gv.voertuig_id
      from gebruiker_voertuigen gv
      join gebruikers g on g.id = gv.gebruiker_id
      where g.bedrijf_id = v_bedrijf and g.rol = 'chauffeur' and g.actief
      order by gv.gebruiker_id, gv.voertuig_id
    loop
      -- Niet elk toestel gaat elke dag buiten: een dekking van 100% zou net
      -- ongeloofwaardig zijn, en de KPI "dekking per gebruiker" heeft pas
      -- betekenis als ze niet altijd vol staat.
      continue when random() < 0.28;

      v_kans := random();
      v_verdict := case
        when v_kans < 0.82 then 'rijklaar'
        when v_kans < 0.94 then 'rijklaar_met_opmerkingen'
        else 'niet_rijklaar'
      end;

      -- Eén chauffeur vinkt stelselmatig alles groen aan. Dat is geen slordige
      -- demodata maar het punt zelf: het rapportscherm herkent dat patroon
      -- (detecteerRubberStamping in account.html) en zet er een signaal bij.
      -- Zonder zo iemand in de gegevens blijft dat scherm leeg en moet je in een
      -- demo uitleggen wat je niet kan tonen.
      if v_k.gebruiker_id = v_altijd_groen then
        v_verdict := 'rijklaar';
      end if;

      -- Bijna altijd bij de start van de shift; af en toe eentje buiten de
      -- werkuren, zodat die KPI ook iets te tonen heeft.
      if random() < 0.06 then
        v_tijd := time '05:10' + (floor(random() * 40) || ' minutes')::interval;
      else
        v_tijd := time '06:35' + (floor(random() * 85) || ' minutes')::interval;
      end if;
      v_moment := (current_date - v_dag) + v_tijd;

      -- Duur: normaal een minuut of vijf. Af en toe eentje die er dertig
      -- seconden over deed -- dat is het tweede signaal dat het rapportscherm
      -- kan tonen (zoekKorteInspecties: minder dan drie seconden per punt).
      if random() < 0.05 then
        v_start := v_moment - interval '30 seconds';
      else
        v_start := v_moment - ((4 + floor(random() * 7)) || ' minutes')::interval;
      end if;

      insert into inspecties (bedrijf_id, gebruiker_id, voertuig_id, datum, tijdstip,
                              verdict, handtekening, gestart_op, verzonden_op)
      values (v_bedrijf, v_k.gebruiker_id, v_k.voertuig_id, (current_date - v_dag), v_tijd,
              v_verdict, v_sig, v_start, v_moment)
      returning id into v_inspectie;

      -- Welke punten hoorden bij dit toestel? Zelfde regel als rpc_checklist:
      -- een sectie zonder koppeling geldt voor elk type.
      select count(*) into v_aantal
      from inspectie_secties s
      join inspectie_punten p on p.sectie_id = s.id
      where s.bedrijf_id = v_bedrijf and s.actief and p.actief
        and (not exists (select 1 from inspectie_sectie_types st where st.sectie_id = s.id)
             or exists (select 1
                        from inspectie_sectie_types st
                        join voertuigen v on v.id = v_k.voertuig_id
                        where st.sectie_id = s.id and st.voertuig_type_id = v.type_id));

      -- Bij een afwijkend verdict ligt op voorhand vast wélk punt niet in orde
      -- was: zo staat er gegarandeerd een vaststelling bij, in plaats van een
      -- rood rapport zonder aanleiding.
      v_nok1 := case when v_verdict = 'rijklaar' then 0 else 1 + floor(random() * v_aantal)::int end;
      v_nok2 := case when v_verdict = 'niet_rijklaar' then 1 + floor(random() * v_aantal)::int else 0 end;

      v_index := 0;
      for v_punt in
        select p.id
        from inspectie_secties s
        join inspectie_punten p on p.sectie_id = s.id
        where s.bedrijf_id = v_bedrijf and s.actief and p.actief
          and (not exists (select 1 from inspectie_sectie_types st where st.sectie_id = s.id)
               or exists (select 1
                          from inspectie_sectie_types st
                          join voertuigen v on v.id = v_k.voertuig_id
                          where st.sectie_id = s.id and st.voertuig_type_id = v.type_id))
        order by s.volgorde, p.volgorde
      loop
        v_index := v_index + 1;
        v_opm := null;

        if v_index = v_nok1 or v_index = v_nok2 then
          v_status := 'nok';
          v_opm := v_opmerkingen[1 + floor(random() * array_length(v_opmerkingen, 1))::int];
        elsif random() < 0.03 then
          v_status := 'na';
        else
          v_status := 'ok';
        end if;

        -- fotos is een text[], geen jsonb -- zie migratie 0017, die daar destijds
        -- rpc_verzend_inspectie voor rechtzette. Leeg dus, want er hangen geen
        -- bestanden aan een demovaststelling.
        insert into inspectie_resultaten (inspectie_id, punt_id, status, opmerking, fotos)
        values (v_inspectie, v_punt.id, v_status, v_opm, '{}'::text[]);
      end loop;
    end loop;
  end loop;
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 3 -- keuringen: een kalender met groen, oranje en rood
-- ---------------------------------------------------------------------------
-- Een demokalender waarin alles in orde is, toont niets. Twee vervallen en twee
-- bijna vervallen keuringen zijn precies wat het scherm moet kunnen laten zien.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
begin
  -- Geen kolom categorie: 0074 heeft die geschrapt en opgelost in het
  -- keuringstype (domein + naam) plus de opmerking. De soort keuring hangt dus
  -- aan keuring_type_id, niet aan een los tekstveld.
  insert into keuringen (bedrijf_id, omschrijving, aantal, uitvoerder,
                         periodiciteit_maanden, laatste_keuring, vervaldatum,
                         opmerking, actief, keuring_type_id, voertuig_id, ingevoerd_door)
  select v_bedrijf, x.omschrijving, x.aantal, x.uitvoerder, x.per,
         x.laatste, x.verval, x.opmerking, true,
         (select kt.id from keuring_types kt where kt.naam = x.type_naam),
         (select v.id from voertuigen v where v.bedrijf_id = v_bedrijf and v.nummerplaat = x.asset),
         'PrevX'
  from (values
    ('Periodieke keuring heftruck HEF-01', 1, 'Externe keuringsinstelling (demo)', 12,
       (current_date - 380)::date, (current_date - 15)::date,
       'Vervallen. Keuring opnieuw in te plannen.', 'Periodieke keuring hefwerktuigen', 'HEF-01'),
    ('Periodieke keuring heftruck HEF-02', 1, 'Externe keuringsinstelling (demo)', 12,
       (current_date - 300)::date, (current_date + 65)::date,
       null, 'Periodieke keuring hefwerktuigen', 'HEF-02'),
    ('Periodieke keuring hoogwerker HWK-01', 1, 'Externe keuringsinstelling (demo)', 12,
       (current_date - 350)::date, (current_date + 14)::date,
       'Afspraak vastleggen.', 'Periodieke keuring hefwerktuigen', 'HWK-01'),
    ('Keuring hijsbanden en kettingwerk', 18, 'Externe keuringsinstelling (demo)', 12,
       (current_date - 210)::date, (current_date + 155)::date,
       '18 stuks, genummerd magazijn.', 'Keuring hijs- en hefgereedschap', null),
    ('Keuring ladders en rolsteiger', 7, 'Interne controle', 12,
       (current_date - 250)::date, (current_date + 115)::date,
       null, 'Keuring ladders en steigers', null),
    ('Keuring valbeveiliging en ankerpunten', 6, 'Externe keuringsinstelling (demo)', 12,
       (current_date - 400)::date, (current_date - 35)::date,
       'Vervallen sinds vorige maand. Harnassen tijdelijk uit dienst.', 'Keuring valbeveiliging en ankerpunten', null),
    ('AREI-controle laagspanningsinstallatie', 1, 'Erkend organisme (demo)', 60,
       (current_date - 1180)::date, (current_date + 640)::date,
       'Laatste verslag zonder inbreuken.', 'Periodieke controle elektrische installatie (laagspanning)', null),
    ('Controle brandblussers', 14, 'Onderhoudsfirma (demo)', 12,
       (current_date - 330)::date, (current_date + 35)::date,
       '14 toestellen, verspreid over productie en magazijn.', 'Controle brandblusapparaten', null),
    ('Controle brandhaspels', 4, 'Onderhoudsfirma (demo)', 12,
       (current_date - 330)::date, (current_date + 35)::date,
       null, 'Controle brandhaspels en blusleidingen', null),
    ('Keuring sectionaalpoorten', 3, 'Onderhoudsfirma (demo)', 12,
       (current_date - 190)::date, (current_date + 175)::date,
       null, 'Keuring poorten en laadbruggen', null),
    ('Onderhoud en keuring stookinstallatie', 1, 'Technieker (demo)', 12,
       (current_date - 280)::date, (current_date + 85)::date,
       null, 'Onderhoud en keuring stookinstallatie', null),
    ('Bijscholing hulpverleners EHBO', 3, 'Opleidingsverstrekker (demo)', 12,
       (current_date - 200)::date, (current_date + 165)::date,
       'Drie hulpverleners in dienst.', 'Bijscholing hulpverleners (EHBO)', null),
    ('Lekdichtheidscontrole koelinstallatie', 2, 'Erkend koeltechnicus (demo)', 12,
       (current_date - 240)::date, (current_date + 125)::date,
       null, 'Lekdichtheidscontrole koelinstallatie (F-gassen)', null)
  ) as x(omschrijving, aantal, uitvoerder, per, laatste, verval, opmerking, type_naam, asset);
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 4 -- het dossier: actiepunten, meldingen, documenten, planning, rest
-- ---------------------------------------------------------------------------
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_ap_melding uuid;
  v_doc_verslag1 uuid;
  v_doc_verslag2 uuid;
  v_ch1 uuid;
  v_ch3 uuid;
  v_m1 uuid;
  v_m2 uuid;
  v_m3 uuid;
  v_m4 uuid;
begin
  select id into v_ch1 from gebruikers where bedrijf_id = v_bedrijf and naam = 'Kevin De Smet';
  select id into v_ch3 from gebruikers where bedrijf_id = v_bedrijf and naam = 'Marc Delrue';

  -- --- actiepunten ---------------------------------------------------------
  insert into actiepunten (bedrijf_id, omschrijving, bron, verantwoordelijke, deadline, status, aangemaakt_op) values
    (v_bedrijf, 'Keuring heftruck HEF-01 opnieuw laten uitvoeren; toestel tot dan uit dienst.',
       'keuringen', 'Nele Coppens', (current_date + 7)::date, 'open', now() - interval '12 days'),
    (v_bedrijf, 'Harnassen en ankerpunten laten herkeuren voor de werken op het dak.',
       'keuringen', 'Nele Coppens', (current_date + 14)::date, 'open', now() - interval '9 days'),
    (v_bedrijf, 'Markering voetgangerszone magazijn opnieuw aanbrengen.',
       'bezoek', 'Sofie Delaere', (current_date + 21)::date, 'open', now() - interval '18 days'),
    (v_bedrijf, 'Rechter achterlicht 1-DEM-001 laten herstellen.',
       'inspectie', 'Kevin De Smet', (current_date + 3)::date, 'ter_validatie', now() - interval '5 days'),
    (v_bedrijf, 'Oogdouche werkplaats maandelijks laten spoelen en aftekenen.',
       'bezoek', 'Nele Coppens', (current_date + 30)::date, 'open', now() - interval '22 days'),
    (v_bedrijf, 'Toolbox "veilig stapelen" geven aan het magazijnteam.',
       'bezoek', 'Nele Coppens', (current_date - 4)::date, 'afgesloten', now() - interval '40 days'),
    (v_bedrijf, 'Noodverlichting boven de nooduitgang achteraan vervangen.',
       'bezoek', 'Sofie Delaere', (current_date - 12)::date, 'afgesloten', now() - interval '48 days'),
    (v_bedrijf, 'Veiligheidsinstructiekaart lasposten uithangen.',
       'bezoek', 'Bart Vermeulen', (current_date - 20)::date, 'afgesloten', now() - interval '55 days');

  insert into actiepunten (bedrijf_id, omschrijving, bron, verantwoordelijke, deadline, status, aangemaakt_op)
  values (v_bedrijf, 'Losliggende kabelgoot aan laadkade vastzetten.',
          'melding', 'Nele Coppens', (current_date + 5)::date, 'open', now() - interval '3 days')
  returning id into v_ap_melding;

  -- --- meldingen -----------------------------------------------------------
  -- Eerst de kolommen die er sinds 0022 zijn; locatie en de koppeling naar de
  -- melder kwamen er pas bij met "melden vanaf de vloer" (0090). Door die twee
  -- apart te zetten werkt de demo ook als die migratie nog niet gedraaid is --
  -- dezelfde afweging als bij het brandpreventiedossier verderop.
  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam, status, actiepunt_id, aangemaakt_op)
  values (v_bedrijf, 'onveilige-situatie', 'Kabelgoot aan de laadkade ligt los; je blijft er met de palletwagen aan haperen.',
          'Marc Delrue', 'in_behandeling', v_ap_melding, now() - interval '3 days')
  returning id into v_m1;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam, status, actiepunt_id, aangemaakt_op)
  values (v_bedrijf, 'bijna-ongeval', 'Pallet gleed van de vorken bij het afzetten. Niemand in de buurt, geen schade.',
          'Marc Delrue', 'nieuw', null, now() - interval '9 days')
  returning id into v_m2;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam, status, actiepunt_id, aangemaakt_op)
  values (v_bedrijf, 'vraag', 'Moeten we voor het werk op het dak van gebouw B ook een vuurvergunning aanvragen?',
          'Kevin De Smet', 'afgehandeld', null, now() - interval '16 days')
  returning id into v_m3;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam, status, actiepunt_id, aangemaakt_op)
  values (v_bedrijf, 'onveilige-situatie', 'Nooduitgang achteraan stond geblokkeerd door leeggoed.',
          'Younes El Amrani', 'afgehandeld', null, now() - interval '25 days')
  returning id into v_m4;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam, status, actiepunt_id, aangemaakt_op)
  values (v_bedrijf, 'ongeval', 'Snijwonde aan de duim bij het ontbramen. Verzorgd met de EHBO-koffer, geen werkverlet.',
          'Nele Coppens', 'afgehandeld', null, now() - interval '38 days');

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'meldingen' and column_name = 'locatie') then
    update meldingen set gebruiker_id = v_ch3, locatie = 'Laadkade'         where id = v_m1;
    update meldingen set gebruiker_id = v_ch3, locatie = 'Magazijn, gang 2' where id = v_m2;
    update meldingen set gebruiker_id = v_ch1                               where id = v_m3;
    update meldingen set locatie = 'Productiehal'                           where id = v_m4;
  else
    raise notice 'Kolommen uit 0090 (melden vanaf de vloer) ontbreken; meldingen krijgen geen locatie of melder-koppeling.';
  end if;

  -- --- documenten ----------------------------------------------------------
  -- De codes komen uit dezelfde teller als een echte upload
  -- (volgend_documentcode, 0086), dus ze zien er in de demo net zo uit als bij
  -- een klant: DEMO-PX-RIS-001 enzovoort. Er hangt geen bestand aan -- die
  -- zouden in Storage blijven staan na een reset. Het scherm toont dan "-" bij
  -- Bekijk; dat is de enige plek waar je merkt dat het een demo is.
  insert into documenten (bedrijf_id, type, titel, versie, geupload_op, code) values
    (v_bedrijf, 'RIS', 'Risicoanalyse productie en magazijn', '2.0', now() - interval '70 days',
       public.volgend_documentcode(v_bedrijf, 'RIS')),
    (v_bedrijf, 'GPP', 'Globaal preventieplan ' || extract(year from current_date)::text || '-' || (extract(year from current_date)::int + 4)::text, '1.0',
       now() - interval '64 days', public.volgend_documentcode(v_bedrijf, 'GPP')),
    (v_bedrijf, 'JAP', 'Jaaractieplan ' || extract(year from current_date)::text, '1.1', now() - interval '58 days',
       public.volgend_documentcode(v_bedrijf, 'JAP')),
    (v_bedrijf, 'BRA', 'Brandrisicoanalyse vestiging Roeselare', '1.0', now() - interval '52 days',
       public.volgend_documentcode(v_bedrijf, 'BRA')),
    (v_bedrijf, 'EVP', 'Evacuatieplan productiehal en magazijn', '2.1', now() - interval '46 days',
       public.volgend_documentcode(v_bedrijf, 'EVP')),
    (v_bedrijf, 'BPR', 'Procedures bij brand en evacuatie', '1.0', now() - interval '44 days',
       public.volgend_documentcode(v_bedrijf, 'BPR')),
    (v_bedrijf, 'HLP', 'Info voor de openbare hulpdiensten', '1.0', now() - interval '42 days',
       public.volgend_documentcode(v_bedrijf, 'HLP')),
    (v_bedrijf, 'TBX', 'Toolbox: veilig stapelen en heffen', '1.0', now() - interval '30 days',
       public.volgend_documentcode(v_bedrijf, 'TBX'));

  insert into documenten (bedrijf_id, type, titel, versie, geupload_op, code)
  values (v_bedrijf, 'RPT', 'Bezoekverslag rondgang magazijn', '1.0', now() - interval '38 days',
          public.volgend_documentcode(v_bedrijf, 'RPT'))
  returning id into v_doc_verslag1;

  insert into documenten (bedrijf_id, type, titel, versie, geupload_op, code)
  values (v_bedrijf, 'RPT', 'Bezoekverslag productie en laskamer', '1.0', now() - interval '11 days',
          public.volgend_documentcode(v_bedrijf, 'RPT'))
  returning id into v_doc_verslag2;

  -- --- planning ------------------------------------------------------------
  insert into planning (bedrijf_id, type, datum, tijdstip, status, document_id, aangemaakt_op) values
    (v_bedrijf, 'bezoek',   (current_date - 38)::date, time '09:00', 'afgerond', v_doc_verslag1, now() - interval '60 days'),
    (v_bedrijf, 'rondgang', (current_date - 24)::date, time '13:30', 'afgerond', null,           now() - interval '50 days'),
    (v_bedrijf, 'bezoek',   (current_date - 11)::date, time '09:30', 'afgerond', v_doc_verslag2, now() - interval '40 days'),
    (v_bedrijf, 'comite',   (current_date + 9)::date,  time '10:00', 'gepland',  null,           now() - interval '20 days'),
    (v_bedrijf, 'bezoek',   (current_date + 26)::date, time '09:00', 'gepland',  null,           now() - interval '20 days'),
    (v_bedrijf, 'rondgang', (current_date + 54)::date, time '14:00', 'gepland',  null,           now() - interval '20 days');

  -- --- kennisbank ----------------------------------------------------------
  -- Alles wat er centraal staat, delen met de demoklant. Staat er nog niets,
  -- dan blijft het scherm leeg -- dat is geen fout, enkel een lege kennisbank.
  insert into bedrijf_kennisbank (bedrijf_id, item_id)
  select v_bedrijf, k.id from kennisbank_items k
  on conflict do nothing;

  -- --- samenwerking --------------------------------------------------------
  -- Zes dagen, want de demoklant staat op Partner Standaard, en die formule
  -- voorziet er sinds 0095 zes. Wijzig je dat aantal in Codelijsten, pas het
  -- dan hier mee aan -- anders spreekt de balk in het dossier de formule tegen
  -- die erboven staat, en dat is net het soort detail dat een prospect opmerkt.
  -- Vorig jaar stond de klant op Light: vier dagen. Dat vertelt en passant het
  -- verhaal van een klant die opgeschaald heeft.
  insert into samenwerking (bedrijf_id, jaar, bezoekdagen_contract, inbegrepen, opmerking) values
    (v_bedrijf, extract(year from current_date)::int, 6.0,
     'Zes bezoekdagen: risicoanalyse, vier rondgangen en de jaarevaluatie. Portaal, documentbeheer en meldingen inbegrepen.',
     'Demodossier.'),
    (v_bedrijf, extract(year from current_date)::int - 1, 4.0,
     'Opstartjaar op de formule Light: risicoanalyse en globaal preventieplan.', null)
  on conflict (bedrijf_id, jaar) do nothing;

  -- --- brandpreventiedossier ----------------------------------------------
  -- Bewust gemengd: een dossier waarin elk onderdeel groen staat, toont niet
  -- waar het scherm voor dient.
  --
  -- Overgeslagen zolang migratie 0088 niet gedraaid is (zie de uitleg bij de
  -- gelijkaardige controle in BLOK 1). De rest van de demo staat er dan wel
  -- gewoon; draai 0088 en daarna dit script opnieuw, en het onderdeel komt
  -- erbij.
  if to_regclass('public.brandpreventie_status') is null then
    raise notice 'Tabel brandpreventie_status bestaat nog niet (migratie 0088 nog niet gedraaid). Brandpreventiedossier overgeslagen.';
  else
    insert into brandpreventie_status (bedrijf_id, onderdeel, nagekeken_op, door, hertermijn_maanden, opmerking) values
      (v_bedrijf, 'risicoanalyse',          (current_date - 52)::date, 'PrevX', 12, null),
      (v_bedrijf, 'brandbestrijdingsdienst',(current_date - 44)::date, 'PrevX', 12, 'Vier aangeduide medewerkers.'),
      (v_bedrijf, 'procedures',             (current_date - 44)::date, 'PrevX', 12, null),
      (v_bedrijf, 'evacuatieplan',          (current_date - 46)::date, 'PrevX', 12, 'Plannen hangen aan beide uitgangen.'),
      (v_bedrijf, 'interventiedossier',     (current_date - 42)::date, 'PrevX', 12, null),
      (v_bedrijf, 'oefeningen',             (current_date - 400)::date,'PrevX', 12, 'Laatste evacuatieoefening is meer dan een jaar geleden.'),
      (v_bedrijf, 'beschermingsmiddelen',   (current_date - 30)::date, 'PrevX', 12, null),
      (v_bedrijf, 'controles',              (current_date - 30)::date, 'PrevX', 12, 'Zie de keuringskalender.'),
      (v_bedrijf, 'afwijkingen',            null,                      null,    12, 'Nog na te kijken of er afwijkingen art. 52 ARAB gelden.'),
      (v_bedrijf, 'adviezen',               (current_date - 41)::date, 'PrevX', 12, null),
      (v_bedrijf, 'hulpdiensten',           (current_date - 42)::date, 'PrevX', 12, null)
    on conflict (bedrijf_id, onderdeel) do nothing;
  end if;
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 4B -- chemische agentia
-- ---------------------------------------------------------------------------
-- Zes producten die je in een metaalbedrijf werkelijk aantreft, gekozen zodat
-- elk signaal in het scherm iets te tonen heeft:
--
--   * een product onder titel 2 (de PU-lijm, via EUH380 -- hormoonontregelaar,
--     de categorie zonder pictogram);
--   * een product met H351 "verdacht van kanker", categorie 2, dat er juist
--     NIET onder valt -- dat verschil van één cijfer is het hele punt;
--   * een gearchiveerd product dat wel onder titel 2 viel, om te tonen dat het
--     spoor blijft;
--   * bladen met en zonder datum.
--
-- GEEN ENKEL PRODUCT HEEFT BIJ HET ZAAIEN EEN BESTAND. Dat is geen vergetelheid:
-- een verzonnen adres geeft een 404 midden in je demo, en een pdf in de repo
-- zetten om hem bij elke reset weer te uploaden is meer omhaal dan het waard is.
-- Laad vóór je eerste demo bij één product een pdf op -- tien seconden werk --
-- dan toont het scherm ook de knop "Veiligheidsinformatieblad openen".
--
-- Wat je oplaadt, blijft staan. Dit blok kuist zijn eigen producten op (het
-- opkuisblok bovenaan laat ze met opzet met rust) en onthoudt daarbij per
-- productnaam waar het opgeladen blad staat. Na het opnieuw zaaien hangt die
-- verwijzing er weer aan. Het bestand zelf staat in de opslag en wordt hier
-- toch nooit aangeraakt; enkel de verwijzing weggooien zou betekenen dat je na
-- elke reset opnieuw moet opladen voor een pdf die er al ligt.
--
-- Op naam koppelen, niet op id: de id's zijn nieuw na het opnieuw zaaien, de
-- namen staan hieronder vast. Hernoem je een product in de lijst, dan raakt het
-- zijn blad kwijt -- dat is het eerlijke gedrag, want dan is het een ander
-- product geworden.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_bladen  jsonb;
begin
  if to_regclass('public.chemische_producten') is null then
    raise notice 'Tabel chemische_producten bestaat nog niet (migratie 0098 nog niet gedraaid). Producten overgeslagen.';
    return;
  end if;

  -- distinct on: stond er per ongeluk twee keer dezelfde productnaam, dan zou
  -- jsonb_object_agg struikelen over de dubbele sleutel en je hele reset
  -- afbreken. Het jongste blad wint.
  select coalesce(jsonb_object_agg(naam, vib_url), '{}'::jsonb)
    into v_bladen
    from (select distinct on (naam) naam, vib_url
            from chemische_producten
           where bedrijf_id = v_bedrijf
             and vib_url is not null
           order by naam, vib_datum desc nulls last) b;

  delete from chemische_producten where bedrijf_id = v_bedrijf;

  insert into chemische_producten
    (bedrijf_id, naam, leverancier, toepassing, locatie, hoeveelheid,
     h_zinnen, vib_datum, opmerking, actief, toegevoegd_door)
  values
    (v_bedrijf, 'Ontvetter X-200', 'Chemco', 'Ontvetten voor het lassen',
     'Chemiekast magazijn', '4 bussen van 5 l',
     array['H315','H319','H336'], (current_date - 500)::date, null, true, 'PrevX'),

    (v_bedrijf, 'Antispatspray lasposten', 'Weldtech', 'Voorkomen dat lasspatten hechten',
     'Lasplaats 1 en 2', '6 spuitbussen',
     array['H222','H229','H315'], (current_date - 780)::date, null, true, 'PrevX'),

    -- Titel 2 via EUH380: geen pictogram, en juist daarom het product waarop je
    -- in een demo blijft staan.
    (v_bedrijf, 'Tweecomponentenlijm PU', 'Bouwchemie', 'Verlijmen van panelen',
     'Magazijn, rek 4', '12 x 750 ml',
     array['H317','H334','EUH380'], null,
     'Enkel gebruiken met afzuiging.', true, 'PrevX'),

    -- H351 is categorie 2 ("verdacht van"): valt onder titel 1, NIET onder
    -- titel 2. Het blad is van 2019 en voedt de oranje teller zodra er een
    -- bestand aan hangt.
    (v_bedrijf, 'Roestomvormer', 'Metaalchemie', 'Voorbehandeling van staal',
     'Chemiekast magazijn', '2 bidons van 10 l',
     array['H314','H351'], (current_date - 2100)::date,
     'Blad dateert van voor de laatste receptwijziging; nieuwe versie opvragen.', true, 'PrevX'),

    (v_bedrijf, 'Koelsmeermiddel', 'Cooltech', 'Verspanen op de draaibank',
     'Machinepark', 'Vat van 200 l',
     array['H315','H317'], (current_date - 220)::date, null, true, 'PrevX'),

    -- Gearchiveerd, niet gewist: dat dit ooit in huis was, is zelf informatie --
    -- zeker bij een stof onder titel 2.
    (v_bedrijf, 'Chroomhoudende primer', 'Coatings NV', 'Grondlaag op staal (vervangen in 2025)',
     'Uit dienst', '-',
     array['H350i','H317'], (current_date - 1600)::date,
     'Vervangen door een chroomvrije primer. Rest afgevoerd via erkende ophaler.', false, 'PrevX');

  update chemische_producten
     set vib_url = v_bladen ->> naam
   where bedrijf_id = v_bedrijf
     and v_bladen ->> naam is not null;

  raise notice 'Zes chemische producten toegevoegd, % opgeladen blad(en) behouden.',
    (select count(*) from jsonb_object_keys(v_bladen));
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 4C -- twee vragen
-- ---------------------------------------------------------------------------
-- Eén beantwoord en één open, zodat het scherm allebei de toestanden toont
-- zonder dat je er tijdens een demo eerst zelf een moet stellen.
--
-- De beantwoorde vraag is met opzet die over jobstudenten en chemische agentia:
-- ze raakt aan twee modules tegelijk en het antwoord wijst terug naar de
-- productlijst. Dat is precies wat een portaal doet wat een mail niet doet.
--
-- Het antwoord is nagelezen bij FOD WASO op 21 aug 2026 (boek X titel 3,
-- jongeren op het werk). Wat daar staat en hier verwerkt is: een jobstudent valt
-- onder categorie e; het verbod op gevaarlijke arbeid geldt voor alle
-- categorieën en dekt onder meer kankerverwekkende, mutagene, reprotoxische en
-- hormoonontregelende stoffen; het verbod is niet absoluut, want de
-- risicoanalyse moet aantonen dat het risico reëel is; en die analyse gebeurt
-- vóór de start, jaarlijks opnieuw en bij elke wijziging van werkpost.
-- De precieze afwijkingsvoorwaarden per categorie staan er ook, maar die heb ik
-- hier niet in verwerkt -- gebruik dit antwoord dus als demomateriaal, en toets
-- het aan de bron voor je het aan een echte klant geeft.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_sofie uuid;
  v_kevin uuid;
begin
  if to_regclass('public.vragen') is null then
    raise notice 'Tabel vragen bestaat nog niet (migratie 0101 nog niet gedraaid). Vragen overgeslagen.';
    return;
  end if;

  select id into v_sofie from gebruikers where bedrijf_id = v_bedrijf and naam = 'Sofie Delaere';
  select id into v_kevin from gebruikers where bedrijf_id = v_bedrijf and naam = 'Kevin De Smet';

  -- De trigger op vragen verwittigt PrevX per mail bij elke nieuwe vraag. Zonder
  -- deze onderbreking krijg je twee berichten telkens je de demo reset -- over
  -- vragen die je zelf net gezaaid hebt. Even uit, en meteen weer aan: bij een
  -- fout rolt de transactie de hele blok terug, inclusief dit.
  alter table vragen disable trigger trg_meld_nieuwe_vraag;

  insert into vragen (bedrijf_id, gebruiker_id, gesteld_door, vraag, gesteld_op,
                      antwoord, beantwoord_op, beantwoord_door, status)
  values (
    v_bedrijf, v_sofie, 'Sofie Delaere',
    'Mogen jobstudenten chemische agentia gebruiken? We nemen er twee aan voor de zomer, voor het ontvetten en het opkuisen van de werkplaats.',
    now() - interval '9 days',
    'Kort: niet zomaar, en voor een deel van uw producten niet.' || chr(10) || chr(10) ||
    'Een jobstudent valt onder titel 3 van boek X van de codex (jongeren op het werk), als student-werknemer met een studentenovereenkomst. Voor die groep geldt een verbod op werk waarbij ze worden blootgesteld aan onder meer kankerverwekkende, mutagene en reprotoxische stoffen en aan stoffen met hormoonontregelende eigenschappen.' || chr(10) || chr(10) ||
    'Dat verbod is niet absoluut: het is uw risicoanalyse die moet aantonen of het risico reëel is, en er gelden voorwaarden om ervan af te wijken. Die analyse moet er zijn vóór ze beginnen, wordt jaarlijks hernieuwd en opnieuw bij een wijziging van werkpost.' || chr(10) || chr(10) ||
    'Praktisch voor uw situatie: in uw productlijst staat bij elk product of het onder titel 2 van boek VI valt. Die producten houdt u buiten hun bereik tot we samen bekeken hebben of er een werkbare afwijking bestaat. Voor de gewone ontvetter en de kuisproducten volstaat een degelijk onthaal, de juiste PBM en toezicht van een ervaren collega.' || chr(10) || chr(10) ||
    'Ik neem dit mee op het volgende bezoek en zet de risicoanalyse jongeren in uw dossier.',
    now() - interval '7 days', 'Peter Van Deyk', 'beantwoord'),

  (
    v_bedrijf, v_kevin, 'Kevin De Smet',
    'Moet er op elke bestelwagen een EHBO-koffer liggen, of volstaat één koffer in de werkplaats?',
    now() - interval '2 days',
    null, null, null, 'open');

  alter table vragen enable trigger trg_meld_nieuwe_vraag;

  raise notice 'Twee vragen toegevoegd: een beantwoorde en een open. Geen mail verstuurd -- de trigger stond even uit.';
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 5 -- vuurvergunning
-- ---------------------------------------------------------------------------
-- Dezelfde kopieerslag als rpc_vuurvergunning_activeren (0050). Die functie
-- zelf aanroepen kan hier niet: ze eist is_superbeheerder(), en in de SQL
-- Editor is auth.uid() leeg.
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_std record;
  v_vraag record;
  v_vraag_id uuid;

  v_leiding uuid;
  v_ch1 uuid;
  v_ch2 uuid;

  v_wt_lassen uuid;
  v_wt_slijpen uuid;
  v_wt_dak uuid;

  v_verg uuid;
  v_antwoord text;
begin
  select id into v_leiding from gebruikers where bedrijf_id = v_bedrijf and naam = 'Nele Coppens';
  select id into v_ch1     from gebruikers where bedrijf_id = v_bedrijf and naam = 'Kevin De Smet';
  select id into v_ch2     from gebruikers where bedrijf_id = v_bedrijf and naam = 'Younes El Amrani';

  insert into werktypes (bedrijf_id, key, naam, toelichting, volgorde)
  select v_bedrijf, key, naam, toelichting, volgorde from werktype_standaard
  on conflict (bedrijf_id, key) do nothing;

  select id into v_wt_lassen  from werktypes where bedrijf_id = v_bedrijf and key = 'elektrisch_lassen';
  select id into v_wt_slijpen from werktypes where bedrijf_id = v_bedrijf and key = 'slijpen';
  select id into v_wt_dak     from werktypes where bedrijf_id = v_bedrijf and key = 'dakwerken';

  for v_std in select * from vergunning_standaardvragen order by fase, volgorde loop
    insert into vergunning_vragen (bedrijf_id, fase, vraagtekst, antwoordtype, verplicht, blokkerend, toelichting, volgorde)
    values (v_bedrijf, v_std.fase, v_std.vraagtekst, v_std.antwoordtype, v_std.verplicht,
            v_std.blokkerend, v_std.toelichting, v_std.volgorde)
    returning id into v_vraag_id;

    if array_length(v_std.werktype_keys, 1) is not null then
      insert into vergunning_vraag_werktypes (vraag_id, werktype_id)
      select v_vraag_id, w.id
      from werktypes w
      where w.bedrijf_id = v_bedrijf and w.key = any (v_std.werktype_keys);
    end if;
  end loop;

  -- --- 1. lopende vergunning ----------------------------------------------
  insert into vuurvergunningen (
    bedrijf_id, vergunningsnummer, werktype_id, locatie_omschrijving, uitvoerders,
    aanvrager_id, bewaker_id, status, geldig_van, geldig_tot,
    goedgekeurd_door_id, goedgekeurd_op, handtekening_methode, aangemaakt_op)
  values (
    v_bedrijf, public.volgend_vergunningsnummer(v_bedrijf), v_wt_lassen,
    'Productiehal, lasplaats 2 -- herstelling steunbalk',
    'Kevin De Smet en een technieker van de onderhoudsfirma',
    v_ch1, v_ch2, 'actief',
    now() - interval '2 hours', now() + interval '5 hours',
    v_leiding, now() - interval '2 hours 20 minutes', 'pincode', now() - interval '3 hours')
  returning id into v_verg;

  for v_vraag in
    select vv.id, vv.antwoordtype
    from vergunning_vragen vv
    left join vergunning_vraag_werktypes vw on vw.vraag_id = vv.id
    where vv.bedrijf_id = v_bedrijf and vv.fase = 'voor' and vv.actief
      and (vw.werktype_id is null or vw.werktype_id = v_wt_lassen)
    order by vv.volgorde
  loop
    v_antwoord := case
      when v_vraag.antwoordtype like 'ok_nok%' then 'ok'
      when v_vraag.antwoordtype = 'ja_nee' then 'ja'
      when v_vraag.antwoordtype = 'tekst' then 'Brandwacht voorzien, blusdeken en poederblusser ter plaatse.'
      else null
    end;
    continue when v_antwoord is null;

    insert into vergunning_antwoorden (vergunning_id, vraag_id, fase, antwoord, gebruiker_id, tijdstip)
    values (v_verg, v_vraag.id, 'voor', v_antwoord, v_ch1, now() - interval '2 hours 30 minutes');
  end loop;

  -- --- 2. afgehandeld dossier van vorige week ------------------------------
  -- Eerst als 'actief' aanmaken en pas daarna afsluiten: een afgesloten
  -- vergunning is onwijzigbaar, dus antwoorden erop invoegen lukt nadien niet
  -- meer (zie de triggers in 0057). Zo verloopt het bij een echte klant ook.
  insert into vuurvergunningen (
    bedrijf_id, vergunningsnummer, werktype_id, locatie_omschrijving, uitvoerders,
    aanvrager_id, bewaker_id, status, geldig_van, geldig_tot,
    goedgekeurd_door_id, goedgekeurd_op, handtekening_methode, aangemaakt_op)
  values (
    v_bedrijf, public.volgend_vergunningsnummer(v_bedrijf), v_wt_dak,
    'Dak gebouw B -- dichtingswerken met brander',
    'Dakwerker (externe firma), begeleid door Younes El Amrani',
    v_ch2, v_ch1, 'actief',
    now() - interval '8 days', now() - interval '7 days 2 hours',
    v_leiding, now() - interval '8 days 1 hour', 'pincode', now() - interval '8 days 2 hours')
  returning id into v_verg;

  for v_vraag in
    select vv.id, vv.antwoordtype, vv.fase
    from vergunning_vragen vv
    left join vergunning_vraag_werktypes vw on vw.vraag_id = vv.id
    where vv.bedrijf_id = v_bedrijf and vv.actief
      and (vw.werktype_id is null or vw.werktype_id = v_wt_dak)
    order by vv.fase, vv.volgorde
  loop
    v_antwoord := case
      when v_vraag.antwoordtype like 'ok_nok%' then 'ok'
      when v_vraag.antwoordtype = 'ja_nee' then 'ja'
      when v_vraag.antwoordtype = 'tekst' then 'Geen incidenten. Nacontrole uitgevoerd op het dak en in de ruimte eronder.'
      else null
    end;
    continue when v_antwoord is null;

    insert into vergunning_antwoorden (vergunning_id, vraag_id, fase, antwoord, gebruiker_id, tijdstip)
    values (v_verg, v_vraag.id, v_vraag.fase, v_antwoord, v_ch2, now() - interval '7 days 4 hours');
  end loop;

  update vuurvergunningen set
    status = 'afgesloten',
    werk_beeindigd_op = now() - interval '7 days 3 hours',
    nazorg_2u_bevestigd_op = now() - interval '7 days 1 hour',
    nazorg_2u_door_id = v_ch2,
    nazorg_24u_bevestigd_op = now() - interval '6 days 3 hours',
    nazorg_24u_door_id = v_ch1,
    afgesloten_door_id = v_leiding,
    afgesloten_op = now() - interval '6 days 3 hours'
  where id = v_verg;

  -- --- 3. aanvraag die op goedkeuring wacht --------------------------------
  insert into vuurvergunningen (
    bedrijf_id, vergunningsnummer, werktype_id, locatie_omschrijving, uitvoerders,
    aanvrager_id, status, geldig_van, geldig_tot, aangemaakt_op)
  values (
    v_bedrijf, public.volgend_vergunningsnummer(v_bedrijf), v_wt_slijpen,
    'Magazijn, gang 3 -- doorslijpen van oude rekstijlen',
    'Marc Delrue',
    v_ch1, 'aangevraagd',
    date_trunc('hour', now()) + interval '1 day 1 hour',
    date_trunc('hour', now()) + interval '1 day 5 hours',
    now() - interval '40 minutes');

  -- --- 4. afgewezen aanvraag ----------------------------------------------
  insert into vuurvergunningen (
    bedrijf_id, vergunningsnummer, werktype_id, locatie_omschrijving, uitvoerders,
    aanvrager_id, status, geldig_van, geldig_tot,
    goedgekeurd_door_id, goedgekeurd_op, beslissing_toelichting, handtekening_methode, aangemaakt_op)
  values (
    v_bedrijf, public.volgend_vergunningsnummer(v_bedrijf), v_wt_lassen,
    'Magazijn, rek 12 -- laswerk naast de verpakkingsvoorraad',
    'Externe firma',
    v_ch2, 'afgewezen',
    now() - interval '15 days', now() - interval '14 days 20 hours',
    v_leiding, now() - interval '15 days 1 hour',
    'Te veel brandbare verpakking binnen de tien meter. Eerst leegmaken en afschermen, daarna opnieuw aanvragen.',
    'portaal_login', now() - interval '15 days 2 hours');
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 6 -- LMRA
-- ---------------------------------------------------------------------------
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_ch1 uuid;
  v_ch2 uuid;
  v_ch3 uuid;
  v_lmra uuid;
  v_r record;
  v_dag int;
  v_start timestamptz;
  v_soort text;
  v_taken text[] := array[
    'Wisselen van een lasfles aan lasplaats 2',
    'Pallets afhalen van het bovenste rek',
    'Herstelling transportband, machine stilgelegd',
    'Schoonmaken van de slijpcabine',
    'Laden van staalprofielen op de aanhangwagen',
    'Vervangen van een verlichtingsarmatuur op hoogte'
  ];
  v_locaties text[] := array[
    'Productiehal', 'Magazijn, gang 2', 'Werkplaats', 'Slijpcabine', 'Laadkade', 'Magazijn, gang 4'
  ];
begin
  select id into v_ch1 from gebruikers where bedrijf_id = v_bedrijf and naam = 'Kevin De Smet';
  select id into v_ch2 from gebruikers where bedrijf_id = v_bedrijf and naam = 'Younes El Amrani';
  select id into v_ch3 from gebruikers where bedrijf_id = v_bedrijf and naam = 'Marc Delrue';

  -- Niet de volledige lijst van vijftien: een klant kiest wat bij hem past, en
  -- een demo die dat toont, verkoopt de module beter dan een volle lijst.
  insert into bedrijf_lmra_risicos (bedrijf_id, risico_id)
  select v_bedrijf, r.id
  from lmra_risicos r
  where r.naam in (
    'Vallen van hoogte', 'Struikelen, uitglijden', 'Aanrijding door voertuig',
    'Vallende of kantelende last', 'Bewegende machinedelen', 'Elektrocutie',
    'Brand of explosie', 'Gevaarlijke stoffen', 'Lawaai', 'Handling en houding',
    'Alleen werken', 'Derden in de zone')
  on conflict do nothing;

  for v_dag in reverse 12..0 loop
    continue when extract(isodow from current_date - v_dag) > 5;
    continue when random() < 0.45;

    -- Eén tijdstip berekenen en dat hergebruiken: met twee losse trekkingen zou
    -- een LMRA afgerond kunnen zijn voor ze begon.
    v_start := (current_date - v_dag) + time '08:00' + (floor(random() * 300) || ' minutes')::interval;
    -- Een bevestiging is de korte dagelijkse herbevestiging, een volledige
    -- LMRA overloopt de risicolijst. Dat onderscheid zit in de module zelf.
    v_soort := case when random() < 0.3 then 'bevestiging' else 'volledig' end;

    insert into lmras (bedrijf_id, gebruiker_id, taak, locatie, soort, status, gestart_op, afgerond_op)
    values (
      v_bedrijf,
      (array[v_ch1, v_ch2, v_ch3])[1 + floor(random() * 3)::int],
      v_taken[1 + floor(random() * array_length(v_taken, 1))::int],
      v_locaties[1 + floor(random() * array_length(v_locaties, 1))::int],
      v_soort,
      'veilig',
      v_start,
      v_start + ((2 + floor(random() * 5)) || ' minutes')::interval)
    returning id into v_lmra;

    -- Enkel bij een volledige LMRA hoort de risicolijst; een bevestiging is
    -- net de versie zonder.
    continue when v_soort = 'bevestiging';

    for v_r in
      select r.id from lmra_risicos r
      join bedrijf_lmra_risicos b on b.risico_id = r.id
      where b.bedrijf_id = v_bedrijf
      order by r.volgorde
    loop
      insert into lmra_risico_antwoorden (lmra_id, risico_id, in_orde, opmerking)
      values (v_lmra, v_r.id, true, null);
    end loop;
  end loop;

  -- Eén stilgelegde taak, en ze staat er niet voor de sier: de module bestaat
  -- juist om af te vinken te doorbreken. Zonder een gestopte LMRA in de demo
  -- toont het scherm enkel groene vinkjes.
  insert into lmras (bedrijf_id, gebruiker_id, taak, locatie, soort, status,
                     eigen_vaststelling, stop_reden, hervat_op, hervat_reden, gestart_op, afgerond_op)
  values (
    v_bedrijf, v_ch2,
    'Vervangen van een verlichtingsarmatuur op hoogte', 'Magazijn, gang 4', 'volledig', 'gestopt',
    'De rolsteiger stond op een helling en de wielen liepen niet vast.',
    'Rolsteiger niet stabiel op te stellen op deze plaats.',
    (current_date - 2) + time '14:10',
    'Werk hervat met de hoogwerker in plaats van de rolsteiger, na overleg met Nele.',
    (current_date - 2) + time '10:20',
    (current_date - 2) + time '10:34')
  returning id into v_lmra;

  for v_r in
    select r.id, r.naam from lmra_risicos r
    join bedrijf_lmra_risicos b on b.risico_id = r.id
    where b.bedrijf_id = v_bedrijf
    order by r.volgorde
  loop
    insert into lmra_risico_antwoorden (lmra_id, risico_id, in_orde, opmerking)
    values (v_lmra, v_r.id,
            v_r.naam <> 'Vallen van hoogte',
            case when v_r.naam = 'Vallen van hoogte'
                 then 'Rolsteiger staat op een helling, wielen lopen niet vast.'
                 else null end);
  end loop;
end
$$;


-- ---------------------------------------------------------------------------
-- BLOK 7 -- korte telling, zodat je in de SQL Editor ziet wat er staat
-- ---------------------------------------------------------------------------
do $$
declare
  v_bedrijf uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_g int; v_a int; v_i int; v_k int; v_d int; v_v int; v_l int;
  v_u record;
begin
  select count(*) into v_g from gebruikers  where bedrijf_id = v_bedrijf;
  select count(*) into v_a from voertuigen  where bedrijf_id = v_bedrijf;
  select count(*) into v_i from inspecties  where bedrijf_id = v_bedrijf;
  select count(*) into v_k from keuringen   where bedrijf_id = v_bedrijf;
  select count(*) into v_d from documenten  where bedrijf_id = v_bedrijf;
  select count(*) into v_v from vuurvergunningen where bedrijf_id = v_bedrijf;
  select count(*) into v_l from lmras       where bedrijf_id = v_bedrijf;

  raise notice 'Demodossier klaar: % gebruikers, % assets, % rapporten, % keuringen, % documenten, % vuurvergunningen, % LMRAs.',
    v_g, v_a, v_i, v_k, v_d, v_v, v_l;
  raise notice 'Mijn PrevX: demo@prevx.be. App: klantcode DEMO, met deze pincodes:';

  -- De echte codes, niet de gewenste: zie het opschuiven in BLOK 1.
  for v_u in
    select naam, rol, pincode, actief from gebruikers
    where bedrijf_id = v_bedrijf order by rol, naam
  loop
    raise notice '  % -- % (%)%', v_u.pincode, v_u.naam, v_u.rol,
      case when v_u.actief then '' else ' [niet actief]' end;
  end loop;
end
$$;
