-- Kritiek/informatief-onderscheid per checklistvraag.
-- Default 'kritisch' voor bestaande punten = geen gedragswijziging bij migratie
-- (een NOK op een bestaand punt blokkeert het voertuig nog steeds, zoals nu).

alter table inspectie_punten
  add column if not exists niveau text not null default 'kritisch';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'inspectie_punten_niveau_check'
  ) then
    alter table inspectie_punten
      add constraint inspectie_punten_niveau_check check (niveau in ('kritisch', 'informatief'));
  end if;
end $$;
