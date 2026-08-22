-- Ontbrekende INSERT-policy voor bedrijven (enkel select/update bestonden al):
-- nodig om nieuwe klanten te kunnen aanmaken vanuit het Klanten-scherm.
-- Enkel de superbeheerder mag dit -- het aanmaken van een nieuwe klant is een
-- contractbeslissing, geen self-service actie.

create policy superbeheerder_insert_bedrijven on bedrijven for insert to authenticated
  with check (public.is_superbeheerder());
