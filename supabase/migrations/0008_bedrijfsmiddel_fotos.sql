-- Fotoveld per bedrijfsmiddel (voertuig), i.p.v. het generieke type-icoon.
-- Gebruikt een publieke Supabase Storage-bucket: publiek lezen (nodig voor de
-- chauffeurs-app, die geen sessie heeft), maar enkel de eigen beheerder mag
-- uploaden/wijzigen/verwijderen (pad-conventie: <bedrijf_id>/<voertuig_id>.<ext>).

alter table voertuigen add column if not exists foto_url text;

insert into storage.buckets (id, name, public)
values ('bedrijfsmiddel-fotos', 'bedrijfsmiddel-fotos', true)
on conflict (id) do nothing;

create policy portal_upload_bedrijfsmiddel_fotos on storage.objects for insert to authenticated
  with check (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = public.huidig_bedrijf_id()::text
  );

create policy portal_update_bedrijfsmiddel_fotos on storage.objects for update to authenticated
  using (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = public.huidig_bedrijf_id()::text
  )
  with check (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = public.huidig_bedrijf_id()::text
  );

create policy portal_delete_bedrijfsmiddel_fotos on storage.objects for delete to authenticated
  using (
    bucket_id = 'bedrijfsmiddel-fotos'
    and (storage.foldername(name))[1] = public.huidig_bedrijf_id()::text
  );

-- Returntype van rpc_voertuigen breidt uit (foto_url erbij) -> drop+create.
drop function if exists public.rpc_voertuigen(uuid);

create function public.rpc_voertuigen(p_gebruiker_id uuid)
returns table(
  id uuid, bedrijf_id uuid, nummerplaat text, omschrijving text,
  actief boolean, aangemaakt_op timestamptz, type_id uuid, type_naam text, foto_url text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gebruiker gebruikers;
begin
  select * into v_gebruiker from gebruikers where gebruikers.id = p_gebruiker_id and gebruikers.actief = true;
  if not found then
    return;
  end if;

  if v_gebruiker.rol = 'chauffeur' then
    return query
      select v.id, v.bedrijf_id, v.nummerplaat, v.omschrijving, v.actief, v.aangemaakt_op, v.type_id, vt.naam, v.foto_url
      from voertuigen v
      join gebruiker_voertuigen gv on gv.voertuig_id = v.id
      left join voertuig_types vt on vt.id = v.type_id
      where gv.gebruiker_id = p_gebruiker_id and v.actief = true;
  else
    return query
      select v.id, v.bedrijf_id, v.nummerplaat, v.omschrijving, v.actief, v.aangemaakt_op, v.type_id, vt.naam, v.foto_url
      from voertuigen v
      left join voertuig_types vt on vt.id = v.type_id
      where v.bedrijf_id = v_gebruiker.bedrijf_id and v.actief = true;
  end if;
end;
$$;

grant execute on function public.rpc_voertuigen(uuid) to anon;
