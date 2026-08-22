-- Beheerde lijst van PrevX-pakketten voor de "Gekozen pakket"-keuzelijst op
-- Overzicht, naar exact hetzelfde patroon als sector_codes (0032) en
-- paritaire_comites (0033): één gedeelde lijst voor alle klantdossiers,
-- superbeheerder kan toevoegen en archiveren, nooit hard verwijderen.
--
-- Bewust leeg gestart: dit zijn PrevX-eigen pakketnamen, geen externe
-- officiële classificatie -- die kan niemand behalve de superbeheerder zelf
-- correct invullen.

create table if not exists pakketten (
  id uuid primary key default gen_random_uuid(),
  naam text not null,
  volgorde int not null default 0,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now(),
  unique (naam)
);

alter table pakketten enable row level security;

create policy select_pakketten on pakketten for select to authenticated
  using (true);

create policy superbeheerder_insert_pakketten on pakketten for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_pakketten on pakketten for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());
