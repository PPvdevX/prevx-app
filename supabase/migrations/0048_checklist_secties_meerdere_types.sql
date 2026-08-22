-- Een checklist-sectie kon tot nu toe maar aan ÉÉN bedrijfsmiddel-type hangen
-- (inspectie_secties.voertuig_type_id, zie 0037) of aan alle types tegelijk
-- (null = "Gedeeld"). Een klant met 7 types waarvan er 4 dezelfde vragen delen
-- en 3 andere, kon dat niet uitdrukken zonder secties te dupliceren.
--
-- Vanaf nu: een koppeltabel, zodat een sectie aan een willekeurige combinatie
-- van types kan hangen. Geen rijen = "Gedeeld" (alle types) -- dat houdt de
-- bestaande betekenis van null intact en is meteen de fallback voor elke
-- sectie die vandaag al gedeeld is.
--
-- Let op de gekozen delete-regels:
--   sectie_id       -> on delete cascade: een verwijderde sectie laat geen
--                      wees-koppelingen achter.
--   voertuig_type_id-> BEWUST geen cascade. Met cascade zou het verwijderen van
--                      een type stilzwijgend de laatste koppeling van een
--                      sectie kunnen wissen, waardoor die sectie plots
--                      "Gedeeld" wordt en dus bij ÁLLE types opduikt -- een
--                      checklist die ongemerkt breder wordt is in een
--                      veiligheidsproduct het gevaarlijkste faalgedrag. Zonder
--                      cascade geeft Postgres netjes 23503 en vangt de UI dat
--                      al af (zie verwijderVoertuigType in mijn.html, zelfde
--                      patroon als 0040).

create table if not exists inspectie_sectie_types (
  sectie_id uuid not null references inspectie_secties(id) on delete cascade,
  voertuig_type_id uuid not null references voertuig_types(id),
  primary key (sectie_id, voertuig_type_id)
);

alter table inspectie_sectie_types enable row level security;

create policy portal_all_sectie_types on inspectie_sectie_types for all to authenticated
  using (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_sectie_types.sectie_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ))
  with check (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_sectie_types.sectie_id and s.bedrijf_id = public.huidig_bedrijf_id()
  ));

-- Zelfde additieve patroon als 0029: de superbeheerder beheert ook checklists
-- van andere bedrijven vanuit "Bekijk dossier", waar huidig_bedrijf_id() naar
-- zijn eigen bedrijf wijst en de policy hierboven dus niet volstaat.
create policy superbeheerder_all_sectie_types on inspectie_sectie_types for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

-- Bestaande scoping overzetten: elke sectie die vandaag aan één type hangt,
-- krijgt exact één koppelrij. Secties met null blijven "Gedeeld" (geen rijen).
insert into inspectie_sectie_types (sectie_id, voertuig_type_id)
select id, voertuig_type_id
from inspectie_secties
where voertuig_type_id is not null
on conflict do nothing;

comment on column inspectie_secties.voertuig_type_id is
  'VERVANGEN door de koppeltabel inspectie_sectie_types (migratie 0048). Wordt niet meer gelezen of geschreven; de data is bij 0048 overgezet en blijft enkel als historiek staan. Niet gebruiken in nieuwe code.';

-- Signatuur en returntype blijven identiek, dus hier volstaat create or
-- replace (geen drop nodig zoals in 0042/0047, waar de argumentenlijst wél
-- veranderde). Enige wijziging: de type-filter kijkt naar de koppeltabel.
create or replace function public.rpc_checklist(p_gebruiker_id uuid, p_voertuig_id uuid)
returns table(
  sectie_id uuid, sectie_naam text, sectie_icon text, sectie_volgorde int,
  punt_id uuid, punt_omschrijving text, punt_volgorde int, punt_niveau text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_type_id uuid;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    return;
  end if;

  select type_id into v_type_id from voertuigen where id = p_voertuig_id and bedrijf_id = v_bedrijf_id;
  if v_type_id is null then
    return; -- voertuig hoort niet bij dit bedrijf, of heeft (nog) geen type
  end if;

  return query
    select s.id, s.naam, s.icon, s.volgorde, p.id, p.omschrijving, p.volgorde, p.niveau
    from inspectie_secties s
    join inspectie_punten p on p.sectie_id = s.id
    where s.bedrijf_id = v_bedrijf_id and s.actief = true and p.actief = true
      and (
        -- geen koppelingen = gedeeld, dus geldig voor elk type
        not exists (select 1 from inspectie_sectie_types st where st.sectie_id = s.id)
        or exists (
          select 1 from inspectie_sectie_types st
          where st.sectie_id = s.id and st.voertuig_type_id = v_type_id
        )
      )
    order by s.volgorde, p.volgorde;
end;
$$;

grant execute on function public.rpc_checklist(uuid, uuid) to anon;
