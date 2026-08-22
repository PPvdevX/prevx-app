-- Welke KPI-kaarten bovenaan de Rapportages-tab verschijnen, instelbaar per
-- bedrijf. De KPI's zelf zijn een vaste catalogus in mijn.html (KPI_CATALOGUS);
-- deze tabel bepaalt enkel welke daarvan getoond worden, in welke volgorde, en
-- eventueel onder welke eigen benaming.
--
-- Geen backfill: een bedrijf zonder rijen valt client-side terug op de vier
-- standaard-KPI's. Zo verandert er niets voor bestaande klanten, en betekent
-- "geen rijen" hetzelfde als "nog niets ingesteld" i.p.v. "alles verborgen".

create table if not exists bedrijf_kpis (
  bedrijf_id uuid not null references bedrijven(id),
  kpi_key text not null,
  volgorde int not null default 0,
  actief boolean not null default true,
  label text,
  primary key (bedrijf_id, kpi_key)
);

alter table bedrijf_kpis enable row level security;

-- Klant leest zijn eigen selectie mee (stuurt de rendering); superbeheerder ziet alles.
create policy portal_select_bedrijf_kpis on bedrijf_kpis for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

-- Instellen is bewust géén self-service: de adviseur bepaalt wat een klant ziet
-- (keuze van de gebruiker), zelfde redenering als bij bedrijf_modules in 0019.
create policy superbeheerder_write_bedrijf_kpis on bedrijf_kpis for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_bedrijf_kpis on bedrijf_kpis for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_bedrijf_kpis on bedrijf_kpis for delete to authenticated
  using (public.is_superbeheerder());

-- rpc_verwijder_bedrijf_cascade moet elke nieuwe bedrijf_id-tabel kennen, anders
-- loopt "bedrijf verwijderen" opnieuw vast op een onzichtbare FK-blokkade -- exact
-- het probleem dat 0043 kwam oplossen. Enige wijziging t.o.v. 0043: bedrijf_kpis
-- wordt mee opgeruimd. (inspectie_sectie_types uit 0048 heeft geen eigen regel
-- nodig: die hangt met on delete cascade aan inspectie_secties, dat hieronder al
-- verwijderd wordt vóór voertuig_types aan de beurt komt.)
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  delete from pincode_reset_codes
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id);

  delete from inspectie_resultaten
    where inspectie_id in (select id from inspecties where bedrijf_id = p_bedrijf_id);
  delete from inspecties where bedrijf_id = p_bedrijf_id;

  delete from inspectie_punt_types
    where punt_id in (
      select p.id from inspectie_punten p
      join inspectie_secties s on s.id = p.sectie_id
      where s.bedrijf_id = p_bedrijf_id
    );
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
