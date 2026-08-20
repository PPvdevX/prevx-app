-- Voertuigtypes als eigen tabel per bedrijf (i.p.v. vrije tekst op voertuigen.type),
-- zodat checklistpunten er straks een koppeling mee kunnen maken (zie 0005).

create table if not exists voertuig_types (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  naam text not null,
  icon text,
  volgorde int not null default 0,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now(),
  unique (bedrijf_id, naam)
);

alter table voertuig_types enable row level security;

create policy portal_all_voertuig_types on voertuig_types for all to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id())
  with check (bedrijf_id = public.huidig_bedrijf_id());

-- Eén type-rij per bestaande, unieke vrije-tekst 'type' per bedrijf
insert into voertuig_types (bedrijf_id, naam, icon)
select distinct bedrijf_id, type,
  case type
    when 'Vrachtwagen' then '🚛'
    when 'Bestelwagen' then '🚐'
    when 'Heftruck' then '🏗'
    when 'Aanhangwagen' then '🚌'
    else null
  end
from voertuigen
where type is not null
on conflict (bedrijf_id, naam) do nothing;

alter table voertuigen add column if not exists type_id uuid references voertuig_types(id);

update voertuigen v
set type_id = vt.id
from voertuig_types vt
where vt.bedrijf_id = v.bedrijf_id and vt.naam = v.type and v.type_id is null;

-- De oude 'type' kolom blijft voorlopig staan (rollback-veiligheid) en wordt pas
-- gedropt in een latere, aparte migratie zodra alles op type_id draait:
-- alter table voertuigen drop column type;
