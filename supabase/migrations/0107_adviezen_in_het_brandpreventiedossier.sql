-- ===========================================================================
-- 0107_adviezen_in_het_brandpreventiedossier.sql
-- ADB naast ADV: welk advies telt mee voor onderdeel 10
-- ===========================================================================
-- Onderdeel 10 van het brandpreventiedossier is "de adviezen van de
-- preventieadviseur, het comité en de openbare hulpdienst". Dat onderdeel keek
-- tot nu naar type ADV -- hetzelfde type als de gewone adviesnota. Een advies
-- over een heftruck, een lawaaimeting of een aankoop zette het onderdeel dus
-- op groen. Het dossier zei "in orde" over een stuk dat er niet in hoort, en
-- omgekeerd was er geen manier om aan te duiden dat een adviesnota wél over
-- brandpreventie ging.
--
-- Vanaf nu:
--   ADV  de gewone adviesnota, over om het even welk risico
--   ADB  advies van adviseur, comité of hulpdienst over brandpreventie
--        -> dit is wat onderdeel 10 telt
--
-- Er verandert niets aan de databank: het type is een tekstveld zonder
-- beperking en de nummering (document_nummers, 0086) maakt vanzelf een teller
-- voor ADB aan. Deze migratie past dan ook niets aan. Ze bestaat om twee
-- redenen: de splitsing staat ergens opgeschreven, en het blok hieronder toont
-- welke bestaande adviezen nog nagekeken moeten worden.
--
-- Waarom niet automatisch omzetten: aan een rij is niet te zien of een advies
-- over brand ging. Dat weet enkel wie het geschreven heeft.
-- ===========================================================================

do $$
declare
  r record;
  v_aantal int := 0;
begin
  raise notice '--- bestaande adviezen (type ADV) ---';
  for r in
    select b.naam as bedrijf, d.code, d.titel, d.geupload_op::date as datum, d.id
    from documenten d
    join bedrijven b on b.id = d.bedrijf_id
    where d.type = 'ADV'
    order by b.naam, d.geupload_op
  loop
    v_aantal := v_aantal + 1;
    raise notice '% | % | % | %', r.bedrijf, coalesce(r.code, '(geen code)'), r.datum, r.titel;
    raise notice '    id: %', r.id;
  end loop;

  if v_aantal = 0 then
    raise notice 'Geen enkel document van type ADV. Niets na te kijken.';
  else
    raise notice '';
    raise notice '% advies/adviezen gevonden. Ging er een over brandpreventie, dan hoort', v_aantal;
    raise notice 'die op ADB. Twee manieren:';
    raise notice '  1. opnieuw opladen in het portaal met type ADB -- dan krijgt het stuk';
    raise notice '     meteen een kloppende code (KLANT-PX-ADB-001) en blijft de oude rij';
    raise notice '     verwijderbaar. Dit is de propere weg.';
    raise notice '  2. het blok onderaan deze migratie uitcommentariëren en de id invullen.';
    raise notice '     Dat zet type én code recht in één keer.';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Een bestaand advies omzetten naar ADB
-- ---------------------------------------------------------------------------
-- Vul de id in uit de lijst hierboven en haal de commentaartekens weg. De code
-- gaat mee: een stuk dat KLANT-PX-ADV-004 heet maar in het brandpreventie-
-- dossier zit, is precies het soort verwarring dat deze splitsing wegneemt.
-- De oude ADV-teller loopt niet terug -- dat hoeft ook niet, nummers worden
-- niet hergebruikt.
--
-- update documenten
--    set type = 'ADB',
--        code = public.volgend_documentcode(bedrijf_id, 'ADB')
--  where id = '00000000-0000-0000-0000-000000000000';
