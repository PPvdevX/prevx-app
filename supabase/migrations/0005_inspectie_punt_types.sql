-- Koppeltabel: één checklistpunt kan voor meerdere voertuigtypes gelden
-- (bv. "banden OK" voor alle types, "hydrauliek" enkel voor Heftruck).

create table if not exists inspectie_punt_types (
  punt_id uuid not null references inspectie_punten(id) on delete cascade,
  type_id uuid not null references voertuig_types(id) on delete cascade,
  primary key (punt_id, type_id)
);

alter table inspectie_punt_types enable row level security;

create policy portal_all_inspectie_punt_types on inspectie_punt_types for all to authenticated
  using (exists (
    select 1 from inspectie_punten p
    join inspectie_secties s on s.id = p.sectie_id
    where p.id = inspectie_punt_types.punt_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ))
  with check (exists (
    select 1 from inspectie_punten p
    join inspectie_secties s on s.id = p.sectie_id
    where p.id = inspectie_punt_types.punt_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ));

-- Backfill: elk bestaand punt geldt voorlopig voor alle voertuigtypes van
-- hetzelfde bedrijf, zodat de checklist na migratie identiek blijft aan nu.
-- De beheerder kan dit nadien verfijnen in het portaal (Checklist-tab).
insert into inspectie_punt_types (punt_id, type_id)
select p.id, vt.id
from inspectie_punten p
join inspectie_secties s on s.id = p.sectie_id
join voertuig_types vt on vt.bedrijf_id = s.bedrijf_id
on conflict do nothing;
