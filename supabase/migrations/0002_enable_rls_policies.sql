-- Schakelt Row Level Security in op alle bestaande tabellen (fail-closed) en
-- voegt policies toe voor het beheerportaal (portaal.html), dat via echte
-- Supabase Auth-sessies (e-mail/wachtwoord) inlogt.
--
-- De chauffeurs-app (index.html) gebruikt GEEN Supabase Auth-sessie (enkel de
-- statische anon-key + PIN-check), dus voor de anon-rol wordt hier expliciet
-- niets meer toegestaan op deze tabellen. Chauffeurstoegang loopt vanaf nu
-- uitsluitend via de SECURITY DEFINER-functies in migratie 0006.

create or replace function public.huidig_bedrijf_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select bedrijf_id from gebruikers
  where auth_user_id = auth.uid() and actief = true
  limit 1;
$$;

grant execute on function public.huidig_bedrijf_id() to authenticated;

alter table bedrijven enable row level security;
alter table gebruikers enable row level security;
alter table voertuigen enable row level security;
alter table gebruiker_voertuigen enable row level security;
alter table inspectie_secties enable row level security;
alter table inspectie_punten enable row level security;
alter table inspecties enable row level security;
alter table inspectie_resultaten enable row level security;

create policy portal_select_bedrijven on bedrijven for select to authenticated
  using (id = public.huidig_bedrijf_id());

create policy portal_select_gebruikers on gebruikers for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_select_voertuigen on voertuigen for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id());

-- Update toegestaan zodat de beheerder een voertuigtype kan toewijzen (zie portaal.html)
create policy portal_update_voertuigen on voertuigen for update to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id())
  with check (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_select_gebruiker_voertuigen on gebruiker_voertuigen for select to authenticated
  using (exists (
    select 1 from gebruikers g
    where g.id = gebruiker_voertuigen.gebruiker_id and g.bedrijf_id = public.huidig_bedrijf_id()
  ));

create policy portal_select_secties on inspectie_secties for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_write_secties on inspectie_secties for insert to authenticated
  with check (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_update_secties on inspectie_secties for update to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id())
  with check (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_select_punten on inspectie_punten for select to authenticated
  using (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_punten.sectie_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ));

create policy portal_write_punten on inspectie_punten for insert to authenticated
  with check (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_punten.sectie_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ));

create policy portal_update_punten on inspectie_punten for update to authenticated
  using (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_punten.sectie_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ))
  with check (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_punten.sectie_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ));

create policy portal_select_inspecties on inspecties for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_select_resultaten on inspectie_resultaten for select to authenticated
  using (exists (
    select 1 from inspecties i
    where i.id = inspectie_resultaten.inspectie_id and i.bedrijf_id = public.huidig_bedrijf_id()
  ));

-- Directe tabeltoegang voor anon volledig afsluiten. Alle chauffeurstoegang
-- loopt vanaf migratie 0006 via SECURITY DEFINER RPC's.
revoke all on bedrijven, gebruikers, voertuigen, gebruiker_voertuigen,
  inspectie_secties, inspectie_punten, inspecties, inspectie_resultaten
  from anon;
