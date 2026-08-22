-- 0067 was maar de helft. Er liggen twee lagen rechten op een functie:
--
--   1. Postgres geeft bij het aanmaken zélf EXECUTE aan PUBLIC.
--   2. Supabase legt daar via default privileges grants aan anon en
--      authenticated bovenop.
--
-- In 0067 haalde ik laag 2 weg en vergat laag 1. Het resultaat: functies waar
-- ooit `revoke from public` bij stond zijn nu dicht (willekeurige_byte,
-- verwerk_nazorg_herinneringen, de secretfuncties), en de rest is nog altijd
-- aanroepbaar -- niet omdat anon het recht heeft, maar omdat iederéén het heeft.
-- Van buitenaf gecontroleerd na 0067: volgend_vergunningsnummer voerde nog uit,
-- noteer_login_poging schreef nog weg, genereer_klantcode gaf nog een code
-- terug, en rpc_verwijder_bedrijf_cascade en rpc_pincodes_controleren draaiden
-- door tot hun interne bewaking. Die bewaking hield stand -- er is niets
-- weggelekt -- maar de deur hoorde al dicht te zijn.
--
-- Deze migratie haalt laag 1 weg en zet daarna de toegestane lijst opnieuw,
-- zodat het eindresultaat niet afhangt van de volgorde waarin 0067 en 0068
-- uitgevoerd worden.

revoke execute on all functions in schema public from public;

do $$
declare
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
  v_auth text[] := array[
    'huidig_bedrijf_id','is_superbeheerder',
    'rpc_escalatie_afhandelen','rpc_genereer_pincode','rpc_pakket_toepassen',
    'rpc_pincodes_controleren','rpc_verwijder_bedrijf_cascade',
    'rpc_vuurvergunning_activeren',
    'rpc_actiepunt_bewijs_opladen','rpc_meld_incident'
  ];
  r record;
begin
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
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

-- De service-role heeft zijn twee wegen naar Vault nodig; PUBLIC intrekken mag
-- die niet meenemen.
grant execute on function public.rpc_webhook_secret() to service_role;
grant execute on function public.rpc_vapid_config() to service_role;

alter default privileges in schema public revoke execute on functions from public;
