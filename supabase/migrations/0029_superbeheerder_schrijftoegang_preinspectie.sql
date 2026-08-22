-- Bevestigde regressie: "Bekijk dossier" laat de superbeheerder overal correct
-- LEZEN (alle bestaande superbeheerder-select-policies uit 0018), maar de
-- oudere pre-inspectie-tabellen controleren bij schrijven enkel
-- `bedrijf_id = huidig_bedrijf_id()` -- die functie kijkt naar de EIGEN
-- gebruikersrij van de superbeheerder op de server, niet naar het dossier dat
-- client-side bekeken wordt. Resultaat: 403 bij elke insert/update terwijl een
-- ander dossier bekeken wordt (bv. bulk-import van gebruikers).
--
-- Zelfde additieve patroon als 0018_superbeheerder_rol.sql: niets bestaands
-- aangepast/verwijderd, enkel extra policies die is_superbeheerder() toelaten,
-- ongeacht bedrijf_id.

create policy superbeheerder_insert_gebruikers on gebruikers for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_gebruikers on gebruikers for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_insert_voertuigen on voertuigen for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_voertuigen on voertuigen for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_all_voertuig_types on voertuig_types for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_insert_secties on inspectie_secties for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_secties on inspectie_secties for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_insert_punten on inspectie_punten for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_punten on inspectie_punten for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_all_inspectie_punt_types on inspectie_punt_types for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_update_bedrijven on bedrijven for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_insert_gebruiker_voertuigen on gebruiker_voertuigen for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_gebruiker_voertuigen on gebruiker_voertuigen for delete to authenticated
  using (public.is_superbeheerder());
