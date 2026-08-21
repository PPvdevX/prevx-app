-- ===========================================================================
-- 0096_keuringstypes_in_brandpreventiedossier.sql
-- Welke keuringen tellen mee voor onderdeel 8
-- ===========================================================================
-- 0088 gaf keuring_types een vlag in_brandpreventiedossier, maar liet het
-- aanduiden aan de superbeheerder over. Zolang er niets aangeduid staat, blijft
-- onderdeel 8 van het dossier leeg -- ook bij een klant die zijn blussers netjes
-- laat keuren.
--
-- Onderdeel 8 van de fiche gaat over de data en vaststellingen van de controles
-- en onderhoudsbeurten van de beschermingsmiddelen én van de gas-, verwarmings-,
-- airconditionings- en elektrische installaties. Dat is breder dan brand alleen,
-- en de vlaggen hieronder volgen die opsomming:
--
--   beschermingsmiddelen  brandblusapparaten, haspels en blusleidingen
--   gas                   gasinstallatie
--   verwarming            stookinstallatie
--   airconditioning       koelinstallatie (de F-gassencontrole is de enige
--                         periodieke controle die de meeste bedrijven op hun
--                         koelinstallatie laten uitvoeren)
--   elektriciteit         laagspanning en hoogspanning
--
-- NIET aangevinkt: hefwerktuigen, hijsgereedschap, ladders, valbeveiliging,
-- poorten, drukvaten, EHBO en de milieukeuringen. Die horen thuis in de
-- keuringskalender, niet in het brandpreventiedossier.
--
-- Deze zeven namen komen uit de standaardlijst van 0074. Heb je zelf types
-- toegevoegd -- branddetectie, noodverlichting, compartimenteringsdeuren, een
-- sprinklerinstallatie -- dan staan die er niet bij, want ik ken hun naam niet.
-- Het laatste blok drukt de volledige lijst af met hun stand, zodat je in één
-- oogopslag ziet wat er nog aangevinkt moet worden. Dat doe je in
-- Codelijsten > Keuringstypes met de knop "In dossier".
-- ===========================================================================

update keuring_types
set in_brandpreventiedossier = true
where naam in (
  'Controle brandblusapparaten',
  'Controle brandhaspels en blusleidingen',
  'Keuring gasinstallatie',
  'Onderhoud en keuring stookinstallatie',
  'Lekdichtheidscontrole koelinstallatie (F-gassen)',
  'Periodieke controle elektrische installatie (laagspanning)',
  'Periodieke controle elektrische installatie (hoogspanning)'
);

do $$
declare
  r record;
  v_aan int := 0;
begin
  raise notice '--- keuringstypes en onderdeel 8 ---';
  for r in
    select naam, domein, in_brandpreventiedossier as in_dossier
    from keuring_types
    where actief = true
    order by in_brandpreventiedossier desc, volgorde
  loop
    if r.in_dossier then v_aan := v_aan + 1; end if;
    raise notice '%  %  (%)',
      case when r.in_dossier then '[x]' else '[ ]' end, rpad(r.naam, 58), r.domein;
  end loop;
  raise notice ' ';
  raise notice '% van de actieve types tellen mee voor onderdeel 8.', v_aan;
  raise notice 'Mist er een eigen type (branddetectie, noodverlichting, compartimentering, sprinkler)? Vink het aan in Codelijsten > Keuringstypes.';
end
$$;
