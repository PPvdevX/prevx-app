-- Beheerde lijst van NACE-sectorcodes voor de "Sector/activiteit"-keuzelijst
-- op Overzicht (0031). Eén gedeelde lijst voor alle klantdossiers -- in
-- tegenstelling tot voertuig_types (0003) dus bewust GEEN bedrijf_id.
-- Superbeheerder kan codes toevoegen en archiveren (actief=false); nooit
-- hard verwijderen, want een code die al als vrije tekst in bedrijven.sector
-- staat moet leesbaar blijven ook nadat hij uit de keuzelijst is gehaald.

create table if not exists sector_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  label text not null,
  volgorde int not null default 0,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now(),
  unique (code)
);

alter table sector_codes enable row level security;

-- Iedereen die ingelogd is moet de keuzelijst kunnen lezen (klantgebruikers
-- zien enkel de platte tekstwaarde, maar de dropdown zelf wordt door de
-- superbeheerder gevuld terwijl die als klant kan meekijken via bekijkDossier()).
create policy select_sector_codes on sector_codes for select to authenticated
  using (true);

create policy superbeheerder_insert_sector_codes on sector_codes for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_sector_codes on sector_codes for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

insert into sector_codes (code,label,volgorde) values
  ('41','Bouw van gebouwen',10),
  ('42','Weg- en waterbouw',20),
  ('43','Gespecialiseerde bouwwerkzaamheden',30),
  ('24','Vervaardiging van metalen in primaire vorm',40),
  ('25','Vervaardiging van producten van metaal, excl. machines',50),
  ('28','Vervaardiging van machines en apparaten',60),
  ('49','Vervoer te land',70),
  ('52','Opslag en vervoerondersteunende activiteiten',80),
  ('53','Posterijen en koeriersdiensten',90),
  ('38','Inzameling, verwerking en verwijdering van afval; terugwinning van materialen',100),
  ('39','Sanering en ander afvalbeheer',110)
on conflict (code) do nothing;
