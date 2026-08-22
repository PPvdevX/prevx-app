-- Vervolg op 0066. Daar sloot ik de drie secretfuncties; deze migratie pakt de
-- oorzaak aan in plaats van de symptomen.
--
-- Het probleem: dit project heeft default privileges die EXECUTE op élke nieuwe
-- functie in het public-schema aan `anon` en `authenticated` geven. Alles wat ik
-- schrijf staat dus standaard open, en blijft open tenzij ik er per functie aan
-- denk. Dat is precies omgekeerd aan wat je wil, en het heeft al drie keer
-- misgelopen: 0020 (huidig_bedrijf_id, is_superbeheerder -- die revoke werkte
-- nooit) en 0055/0056 (de webhook-sleutel, live opvraagbaar geweest).
--
-- Wat de controlelijst opleverde: 45 functies aanroepbaar door anon, waarvan de
-- clients er 24 respectievelijk 7 nodig hebben. De rest is interne machinerie --
-- triggerfuncties, hulpfuncties, de cron-taak, de nummerteller. Geen tweede lek:
-- alles wat overbleef is ofwel intern bewaakt (rpc_verwijder_bedrijf_cascade en
-- rpc_pakket_toepassen weigeren zonder superbeheerder), ofwel onbruikbaar zonder
-- een UUID die je niet kan raden. Maar twee verdienen wel aandacht:
--
--   volgend_vergunningsnummer  -- verhoogt de teller van de vergunningsnummers.
--     Met een klantcode is het bedrijf_id op te halen, en dan kan een vreemde
--     gaten slaan in een doorlopend genummerde reeks die als bewijsstuk dient.
--   verwerk_nazorg_herinneringen -- de cron-taak zelf, van buitenaf aanroepbaar.
--
-- Aanpak: intrekken bij anon en authenticated, daarna enkel teruggeven wat
-- app.html en mijn.html effectief aanroepen. Die lijsten komen niet uit mijn
-- hoofd maar uit een grep op beide bestanden.
--
-- Let op bij huidig_bedrijf_id en is_superbeheerder: die MOETEN uitvoerbaar
-- blijven voor `authenticated`. Ze staan in de RLS-policies zelf, en een policy
-- wordt geëvalueerd met de rechten van wie de query stelt -- niet met die van de
-- eigenaar. Zonder dat recht faalt élke portaalquery.

revoke execute on all functions in schema public from anon, authenticated;

do $$
declare
  -- Wat de chauffeurs-app aanroept. Die heeft geen sessie: dit is bewust anon.
  v_anon text[] := array[
    'rpc_bedrijf_via_klantcode','rpc_checklist','rpc_collegas',
    'rpc_goedkeuring_code_aanvragen','rpc_login_chauffeur_klant',
    'rpc_mijn_vergunningen','rpc_modules','rpc_nazorg_bevestigen',
    'rpc_pincode_reset_aanvragen','rpc_pincode_reset_bevestigen',
    'rpc_push_abonneren','rpc_push_afmelden',
    'rpc_vergunning_aanvragen','rpc_vergunning_beslissen','rpc_vergunning_intrekken',
    'rpc_vergunning_locaties','rpc_vergunning_status',
    'rpc_vergunning_tijdens_registreren','rpc_vergunning_vragen',
    'rpc_vergunning_werk_beeindigen','rpc_verzend_inspectie','rpc_voertuigen',
    'rpc_voorwaarden_bevestigen','rpc_werktypes','rpc_wijzig_pincode'
  ];
  -- Wat het portaal aanroept, plus de twee functies die in de policies zelf
  -- staan en de twee oudere portaalwegen uit 0021/0022.
  v_auth text[] := array[
    'huidig_bedrijf_id','is_superbeheerder',
    'rpc_escalatie_afhandelen','rpc_genereer_pincode','rpc_pakket_toepassen',
    'rpc_pincodes_controleren','rpc_verwijder_bedrijf_cascade',
    'rpc_vuurvergunning_activeren',
    'rpc_actiepunt_bewijs_opladen','rpc_meld_incident'
  ];
  r record;
begin
  -- Per oid toekennen i.p.v. per naam: zo krijgen we de exacte handtekening te
  -- pakken, ook bij functies die meerdere keren bestaan met andere argumenten.
  for r in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname = any(v_anon) or p.proname = any(v_auth))
  loop
    if r.proname = any(v_anon) then
      execute format('grant execute on function %s to anon', r.sig);
    end if;
    -- Alles wat anon mag, mag authenticated ook: de superbeheerder gebruikt de
    -- chauffeurs-app soms zelf, en een ingelogde gebruiker die minder mag dan
    -- een anonieme is een bron van onnavolgbare fouten.
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- Zodat de volgende functie niet opnieuw standaard openstaat. Dit geldt enkel
-- voor wat híérna aangemaakt wordt door dezelfde eigenaar; bestaande functies
-- zijn hierboven al behandeld.
alter default privileges in schema public revoke execute on functions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Nalopen na het uitvoeren: de lijst moet nu exact bovenstaande namen bevatten
-- ---------------------------------------------------------------------------
--   select p.proname, array_agg(distinct a.rolname order by a.rolname) as rollen
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   cross join lateral (values ('anon'),('authenticated')) as r(rolname)
--   join pg_roles a on a.rolname = r.rolname
--   where n.nspname = 'public' and has_function_privilege(a.oid, p.oid, 'EXECUTE')
--   group by p.proname order by p.proname;
