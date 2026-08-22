-- Documenten: gecodeerde, versienummerde bestandenlijst (RIS/ADV/AUD_RPT/GPP/JAP).
-- Volledig read-only voor de klant -- enkel de superbeheerder beheert dit.

create table if not exists documenten (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  type text not null,
  titel text not null,
  versie text,
  bestand_url text,
  geupload_op timestamptz not null default now()
);

alter table documenten enable row level security;

create policy portal_select_documenten on documenten for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_documenten on documenten for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_documenten on documenten for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_documenten on documenten for delete to authenticated
  using (public.is_superbeheerder());

insert into storage.buckets (id, name, public)
values ('documenten', 'documenten', true)
on conflict (id) do nothing;

insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'documenten', true from bedrijven
on conflict do nothing;
