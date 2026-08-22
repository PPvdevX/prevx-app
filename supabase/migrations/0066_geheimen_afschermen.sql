-- KRITIEK. De webhook-sleutel was via de publieke API op te vragen door
-- iedereen, zonder in te loggen:
--
--   POST /rest/v1/rpc/rpc_webhook_secret   -> de sleutel
--   POST /rest/v1/rpc/geheim {"p_naam":"webhook_secret"} -> dezelfde sleutel
--
-- Mijn fout in 0055/0056. Daar staat `revoke execute ... from public`, en ik
-- ging ervan uit dat daarmee niemand er nog bij kon. Dat klopt niet op
-- Supabase: dit project heeft default privileges staan die EXECUTE op elke
-- nieuwe functie in het public-schema expliciet aan `anon` en `authenticated`
-- geven. `revoke from public` haalt de impliciete PUBLIC-toekenning weg, maar
-- laat die twee expliciete toekenningen ongemoeid. De functie leek afgeschermd
-- en was het niet.
--
-- Wat de sleutel beschermt: hij is het enige wat de Edge Functions ervan
-- weerhoudt door willekeurige aanroepers gebruikt te worden -- rapportmails,
-- pincode-herstelmails, goedkeuringscodes en nazorgherinneringen. Geen
-- rechtstreekse toegang tot klantgegevens, maar wel het vermogen om in naam van
-- PrevX mail te laten vertrekken naar echte ontvangers.
--
-- Deze migratie sluit alleen de deur. De sleutel zelf moet daarna nog geroteerd
-- worden -- zie de opdracht onderaan -- want de oude waarde is blootgesteld
-- geweest en moet als gecompromitteerd beschouwd worden.

revoke execute on function public.geheim(text) from anon, authenticated;
revoke execute on function public.rpc_webhook_secret() from anon, authenticated;
revoke execute on function public.rpc_vapid_config() from anon, authenticated;

-- service_role behoudt wat het nodig heeft; expliciet herhaald zodat deze
-- migratie op zichzelf leesbaar is.
grant execute on function public.rpc_webhook_secret() to service_role;
grant execute on function public.rpc_vapid_config() to service_role;

-- ---------------------------------------------------------------------------
-- Nalopen: wat mag anon/authenticated nog uitvoeren?
-- ---------------------------------------------------------------------------
-- Draai dit apart in de SQL Editor. De driver-RPC's (rpc_login_chauffeur_klant,
-- rpc_voertuigen, rpc_checklist, rpc_verzend_inspectie, rpc_bedrijf_via_klantcode,
-- rpc_push_abonneren, rpc_push_afmelden en de vergunning-RPC's) HOREN bij anon
-- te staan -- dat is de kern van de opzet. Alles wat daar níét bij hoort en toch
-- opduikt, is een gat van hetzelfde soort als dit.
--
--   select p.proname,
--          array_agg(distinct a.rolname order by a.rolname) as rollen
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   cross join lateral (values ('anon'),('authenticated')) as r(rolname)
--   join pg_roles a on a.rolname = r.rolname
--   where n.nspname = 'public'
--     and has_function_privilege(a.oid, p.oid, 'EXECUTE')
--   group by p.proname
--   order by p.proname;
--
-- ---------------------------------------------------------------------------
-- Daarna: de sleutel roteren
-- ---------------------------------------------------------------------------
-- Eén update, want sinds 0056 leest zowel de databank als elke Edge Function
-- hem uit Vault. Voer dit uit ná deze migratie, als losse opdracht:
--
--   select vault.update_secret(
--     (select id from vault.secrets where name = 'webhook_secret'),
--     encode(decode(md5(gen_random_uuid()::text) || md5(gen_random_uuid()::text), 'hex'), 'hex')
--   );
--
-- Controle (moet een andere waarde geven dan voorheen, en 64 tekens lang zijn):
--   select length(public.geheim('webhook_secret'));
