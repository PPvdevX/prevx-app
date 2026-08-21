-- ===========================================================================
-- 0095_drie_formules.sql
-- Nog drie formules: Light, Standaard, Intensief
-- ===========================================================================
-- De pakkettenlijst (0036) kende er vijf: de drie Partner-formules plus Project
-- en Vorming. Die laatste twee zijn geen formules maar een eenmalige opdracht en
-- een losse sessie -- ze horen niet thuis in een keuzelijst die bepaalt wat een
-- klant in zijn dossier ziet. Ze verdwijnen hier uit de lijst.
--
-- Archiveren, niet wissen. Staat "PrevX Project" bij een klant in het veld
-- pakket, dan blijft dat leesbaar; een verdwenen rij zou die fiche stil
-- onverklaarbaar maken. Gearchiveerde pakketten vallen uit de keuzelijst en zijn
-- via Codelijsten weer te herstellen.
--
-- De drie die blijven, krijgen meteen hun bezoekdagen. Die staan in
-- PX-INT-PKT-001 (Dienstenpakketten, versie v1.0): kwartaalbezoek is 4 dagen,
-- tweemaandelijks 6, maandelijks 12. Vanaf nu vult het kiezen van een formule
-- die dagen zelf in bij de klant (0094), in plaats van dat iemand ze overtikt.
--
-- WAT DEZE MIGRATIE NIET DOET: de drie app-modules aanvinken. Pre-inspecties,
-- vuurvergunning en LMRA zijn aparte producten met een eigen prijs -- zo staan
-- ze ook in het prijsdocument, dat ze niet in de Partner-formules vermeldt.
-- Verkoop je er ooit een bínnen een formule, dan vink je hem aan in Codelijsten
-- en klopt het meteen voor elke nieuwe klant. Let op wat dat betekent voor een
-- bestaande klant die zo'n module heeft: bij het toepassen van een formule zegt
-- het portaal "Gaat UIT: Pre-inspectie". Dat is de bedoeling van dat scherm --
-- lees het, en annuleer als het niet klopt.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Wat geen formule is, uit de lijst
-- ---------------------------------------------------------------------------
update pakketten
set actief = false
where naam in ('PrevX Project', 'PrevX Vorming');

-- ---------------------------------------------------------------------------
-- 2. De drie formules: bezoekdagen en de zin die de klant leest
-- ---------------------------------------------------------------------------
-- inbegrepen komt in het dossier van de klant te staan, boven de balk met
-- "x van y bezoekdagen opgenomen". Kort houden: het is een geheugensteun, geen
-- contract. Wat er precies in zit, staat in de overeenkomst.
update pakketten set bezoekdagen = 4,
  inbegrepen = coalesce(inbegrepen,
    'Vier bezoekdagen per jaar: veiligheidsronde met verslag, actielijst en opvolging. Portaal en documentbeheer inbegrepen.')
where naam = 'PrevX Partner - Light';

update pakketten set bezoekdagen = 6,
  inbegrepen = coalesce(inbegrepen,
    'Zes bezoekdagen per jaar: veiligheidsronde met verslag, actielijst, driemaandelijkse toolbox en opvolging van arbeidsongevallen.')
where naam = 'PrevX Partner - Standaard';

update pakketten set bezoekdagen = 12,
  inbegrepen = coalesce(inbegrepen,
    'Twaalf bezoekdagen per jaar: maandelijkse veiligheidsronde met verslag, actielijst, toolboxen en opvolging van arbeidsongevallen.')
where naam = 'PrevX Partner - Intensief';

-- ---------------------------------------------------------------------------
-- 3. De matrix nakijken
-- ---------------------------------------------------------------------------
-- 0059 vulde de vijf dossiermodules voor precies deze drie namen. Deze migratie
-- rekent daarop; als er in de tussentijd hernoemd is, staat het hieronder.
do $$
declare
  r record;
begin
  raise notice '--- pakketten na deze migratie ---';
  for r in
    select p.naam, p.actief, p.bezoekdagen,
           (select count(*) from pakket_modules pm where pm.pakket_id = p.id) as modules,
           (select count(*) from bedrijven b where b.pakket = p.naam) as klanten
    from pakketten p
    order by p.actief desc, p.volgorde
  loop
    raise notice '% | % | % bezoekdagen | % modules | % klanten',
      rpad(r.naam, 30),
      case when r.actief then 'in de lijst ' else 'gearchiveerd' end,
      coalesce(r.bezoekdagen::text, 'geen'), r.modules, r.klanten;
  end loop;
  raise notice ' ';
  raise notice 'Staat er een klant op een gearchiveerd pakket, dan blijft dat in zijn fiche staan tot je er een van de drie kiest.';
end
$$;
