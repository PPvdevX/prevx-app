-- Herstelt de bedrijf-scoping op de upload-policy (0010 liet die tijdelijk los
-- staan als diagnose-stap). Root cause bleek de nieuwe publishable API-key i.c.m.
-- Storage-schrijfacties, niet de policy zelf; zie portaal.html voor de fix
-- (een aparte storage-client op de legacy anon-key).

drop policy if exists portal_upload_bedrijfsmiddel_fotos on storage.objects;

create policy portal_upload_bedrijfsmiddel_fotos on storage.objects for insert to authenticated
  with check (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = (
      select bedrijf_id::text from gebruikers where auth_user_id = auth.uid() and actief = true limit 1
    )
  );
