-- Ontbrekende INSERT-policy voor voertuigen (enkel select/update bestonden al):
-- nodig om nieuwe bedrijfsmiddelen te kunnen aanmaken vanuit het portaal.

create policy portal_insert_voertuigen on voertuigen for insert to authenticated
  with check (bedrijf_id = public.huidig_bedrijf_id());
