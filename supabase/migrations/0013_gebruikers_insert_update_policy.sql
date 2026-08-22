-- Ontbrekende INSERT/UPDATE-policies voor gebruikers (enkel select bestond al):
-- nodig om nieuwe gebruikers aan te maken en te archiveren vanuit het portaal.

create policy portal_insert_gebruikers on gebruikers for insert to authenticated
  with check (bedrijf_id = public.huidig_bedrijf_id());

create policy portal_update_gebruikers on gebruikers for update to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id())
  with check (bedrijf_id = public.huidig_bedrijf_id());
