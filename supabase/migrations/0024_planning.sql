-- Planning: jaarkalender met bezoeken/rondgangen/comités. Enkel de
-- superbeheerder plant in en beheert -- de klant is louter lezend.

create table if not exists planning (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  type text not null,
  datum date not null,
  tijdstip time,
  status text not null default 'gepland',
  document_id uuid references documenten(id),
  aangemaakt_op timestamptz not null default now()
);

alter table planning enable row level security;

create policy portal_select_planning on planning for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_planning on planning for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_planning on planning for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_planning on planning for delete to authenticated
  using (public.is_superbeheerder());

insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'planning', true from bedrijven
on conflict do nothing;
