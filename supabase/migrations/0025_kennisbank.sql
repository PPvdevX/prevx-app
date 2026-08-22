-- Kennisbank: gedeelde bibliotheek (checklists, sectorale gidsen, toolboxfiches)
-- die de superbeheerder per klant curieert -- "niet alles opengooien". In
-- tegenstelling tot Documenten is deze content NIET bedrijfsgebonden: dezelfde
-- fiche kan aan meerdere klanten toegewezen worden.

create table if not exists kennisbank_items (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  categorie text,
  bestand_url text,
  geupload_op timestamptz not null default now()
);

create table if not exists bedrijf_kennisbank (
  bedrijf_id uuid not null references bedrijven(id),
  item_id uuid not null references kennisbank_items(id) on delete cascade,
  primary key (bedrijf_id, item_id)
);

alter table kennisbank_items enable row level security;
alter table bedrijf_kennisbank enable row level security;

-- Een klant ziet enkel items die expliciet aan zijn bedrijf toegewezen zijn --
-- nooit de volledige bibliotheek.
create policy portal_select_kennisbank_items on kennisbank_items for select to authenticated
  using (
    public.is_superbeheerder()
    or exists (
      select 1 from bedrijf_kennisbank bk
      where bk.item_id = kennisbank_items.id and bk.bedrijf_id = public.huidig_bedrijf_id()
    )
  );

create policy superbeheerder_insert_kennisbank_items on kennisbank_items for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_kennisbank_items on kennisbank_items for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_kennisbank_items on kennisbank_items for delete to authenticated
  using (public.is_superbeheerder());

create policy portal_select_bedrijf_kennisbank on bedrijf_kennisbank for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_bedrijf_kennisbank on bedrijf_kennisbank for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_bedrijf_kennisbank on bedrijf_kennisbank for delete to authenticated
  using (public.is_superbeheerder());

insert into storage.buckets (id, name, public)
values ('kennisbank', 'kennisbank', true)
on conflict (id) do nothing;

insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'kennisbank', true from bedrijven
on conflict do nothing;
