-- Fix voor migratie 0008: de storage-policies verwezen naar public.huidig_bedrijf_id(),
-- wat op storage.objects onbetrouwbaar bleek ("new row violates row-level security
-- policy" bij elke upload). Vervangen door een rechtstreekse subquery op gebruikers,
-- het patroon dat Supabase zelf documenteert voor Storage-RLS.

drop policy if exists portal_upload_bedrijfsmiddel_fotos on storage.objects;
drop policy if exists portal_update_bedrijfsmiddel_fotos on storage.objects;
drop policy if exists portal_delete_bedrijfsmiddel_fotos on storage.objects;

create policy portal_upload_bedrijfsmiddel_fotos on storage.objects for insert to authenticated
  with check (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = (
      select bedrijf_id::text from gebruikers where auth_user_id = auth.uid() and actief = true limit 1
    )
  );

create policy portal_update_bedrijfsmiddel_fotos on storage.objects for update to authenticated
  using (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = (
      select bedrijf_id::text from gebruikers where auth_user_id = auth.uid() and actief = true limit 1
    )
  )
  with check (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = (
      select bedrijf_id::text from gebruikers where auth_user_id = auth.uid() and actief = true limit 1
    )
  );

create policy portal_delete_bedrijfsmiddel_fotos on storage.objects for delete to authenticated
  using (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = (
      select bedrijf_id::text from gebruikers where auth_user_id = auth.uid() and actief = true limit 1
    )
  );
