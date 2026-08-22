-- TIJDELIJK diagnose-migratie: laat elke authenticated gebruiker uploaden naar
-- de bucket, zonder de bedrijf-mapfilter, om te isoleren of het probleem in de
-- padvergelijking zit of ergens fundamenteler. NIET definitief laten staan.

drop policy if exists portal_upload_bedrijfsmiddel_fotos on storage.objects;

create policy portal_upload_bedrijfsmiddel_fotos on storage.objects for insert to authenticated
  with check (bucket_id = 'bedrijfsmiddel-fotos');
