-- Ontbrekende INSERT/DELETE-policies voor gebruiker_voertuigen (enkel select
-- bestond, sinds 0002_enable_rls_policies.sql) -- nodig om vanuit het portaal
-- bedrijfsmiddelen aan chauffeurs te kunnen toewijzen. Zonder deze koppeling
-- ziet een chauffeur-rol gebruiker niets in rpc_voertuigen().

create policy portal_insert_gebruiker_voertuigen on gebruiker_voertuigen for insert to authenticated
  with check (exists (
    select 1 from gebruikers g
    where g.id = gebruiker_voertuigen.gebruiker_id and g.bedrijf_id = public.huidig_bedrijf_id()
  ));

create policy portal_delete_gebruiker_voertuigen on gebruiker_voertuigen for delete to authenticated
  using (exists (
    select 1 from gebruikers g
    where g.id = gebruiker_voertuigen.gebruiker_id and g.bedrijf_id = public.huidig_bedrijf_id()
  ));
