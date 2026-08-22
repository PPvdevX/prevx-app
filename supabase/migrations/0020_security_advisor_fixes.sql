-- Reactie op de Supabase Security Advisor-melding van 26/07/2026.
--
-- 1) public.portaal_gebruikers: een tabel die nergens in de app (migraties,
--    portaal.html, index.html, de Edge Function) gebruikt wordt — vermoedelijk
--    een restant uit vroege ontwikkeling. RLS stond hier niet aan, dus was
--    volledig publiek leesbaar/schrijfbaar/verwijderbaar. Fail-closed
--    afgesloten (geen policies = enkel de service-role/SQL-editor kan er nog
--    bij), consistent met de aanpak in 0002_enable_rls_policies.sql.
alter table if exists public.portaal_gebruikers enable row level security;

-- 2) Alle onderstaande functies kregen bij aanmaak stilzwijgend EXECUTE-rechten
--    voor PUBLIC (Postgres-standaardgedrag), bovenop de expliciete grants die
--    de eerdere migraties al gaven. Dat werd nooit ingetrokken. Hier eerst
--    alles van PUBLIC intrekken, dan exact teruggeven wat nodig is.
revoke execute on function public.huidig_bedrijf_id() from public;
revoke execute on function public.is_superbeheerder() from public;
revoke execute on function public.rpc_login_chauffeur(text) from public;
revoke execute on function public.rpc_checklist(uuid, uuid) from public;
revoke execute on function public.rpc_voertuigen(uuid) from public;
revoke execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb) from public;
revoke execute on function public.rpc_wijzig_pincode(uuid, text, text) from public;

-- huidig_bedrijf_id/is_superbeheerder: uitsluitend voor het ingelogde portaal.
grant execute on function public.huidig_bedrijf_id() to authenticated;
grant execute on function public.is_superbeheerder() to authenticated;

-- De chauffeurs-RPC's blijven bewust enkel voor anon (geen Supabase Auth-sessie
-- in de chauffeurs-app, zie 0002_enable_rls_policies.sql) — dit is het
-- beveiligingsmodel zelf, geen gat. Ze controleren zelf intern PIN/bedrijf.
grant execute on function public.rpc_login_chauffeur(text) to anon;
grant execute on function public.rpc_checklist(uuid, uuid) to anon;
grant execute on function public.rpc_voertuigen(uuid) to anon;
grant execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb) to anon;
grant execute on function public.rpc_wijzig_pincode(uuid, text, text) to anon;
