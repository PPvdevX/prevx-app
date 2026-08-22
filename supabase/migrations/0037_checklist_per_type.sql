-- Checklists volledig scheiden per bedrijfsmiddel-type, i.p.v. één gedeelde
-- pool van secties/punten met per-punt-checkboxes (inspectie_punt_types).
-- Beslissing van de gebruiker: de per-punt-uitzondering wordt niet gebruikt
-- en mag verdwijnen; scoping gebeurt voortaan op sectieniveau.
--
-- inspectie_secties.voertuig_type_id: null = "Gedeeld" (zichtbaar voor alle
-- types van dit bedrijf) -- dit is de fallback voor ALLE bestaande secties,
-- dus er verandert niets zichtbaar voor chauffeurs totdat de superbeheerder
-- een sectie bewust aan een specifiek type toewijst.
--
-- inspectie_punt_types (tabel + data) blijft gewoon bestaan -- wordt enkel
-- niet meer gebruikt door nieuwe code, geen destructieve drop.
--
-- Geen nieuwe RLS-policy nodig: alle bestaande policies op inspectie_secties/
-- inspectie_punten zijn al bedrijf_id-gescopet (rechtstreeks of via
-- sectie_id-join) en blijven ongewijzigd geldig met deze extra kolom.

alter table inspectie_secties
  add column if not exists voertuig_type_id uuid references voertuig_types(id);

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
      and (s.voertuig_type_id is null or s.voertuig_type_id = v_type_id)
    order by s.volgorde, p.volgorde;
end;
$$;
