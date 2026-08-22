-- Beheerde lijst van paritaire comités voor de "Paritair comité"-keuzelijst op
-- Overzicht (0031), naar exact hetzelfde patroon als sector_codes (0032):
-- één gedeelde lijst voor alle klantdossiers, superbeheerder kan toevoegen en
-- archiveren, nooit hard verwijderen (een al gekozen comité moet leesbaar
-- blijven ook nadat hij uit de keuzelijst is gehaald).

create table if not exists paritaire_comites (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  label text not null,
  volgorde int not null default 0,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now(),
  unique (code)
);

alter table paritaire_comites enable row level security;

create policy select_paritaire_comites on paritaire_comites for select to authenticated
  using (true);

create policy superbeheerder_insert_paritaire_comites on paritaire_comites for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_paritaire_comites on paritaire_comites for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

insert into paritaire_comites (code,label,volgorde) values
  ('100','Aanvullend paritair comité voor de werklieden',10),
  ('111','Metaal-, machine- en elektrische bouw',20),
  ('124','Bouwbedrijf',30),
  ('140','Vervoer en logistiek',40),
  ('142','Recuperatie van metalen',50),
  ('200','Aanvullend paritair comité voor de bedienden',60),
  ('209','Bedienden van de metaalfabrikatennijverheid',70),
  ('226','Internationale handel, vervoer en aanverwante logistiek',80)
on conflict (code) do nothing;
