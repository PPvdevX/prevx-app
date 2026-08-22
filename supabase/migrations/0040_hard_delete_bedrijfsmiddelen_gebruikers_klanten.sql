-- Echte verwijderfunctie (naast het bestaande archiveren) voor bedrijfsmiddelen
-- (voertuigen), gebruikers en klanten (bedrijven), voor het geval er per
-- ongeluk iets fout is aangemaakt. Enkel superbeheerder, zelfde patroon als
-- alle andere superbeheerder_delete_*-policies in dit project (0019/0021-0025).
--
-- Bewust geen aparte "is dit leeg genoeg"-check nodig: geen van de FK's naar
-- voertuigen/gebruikers/bedrijven heeft on delete cascade, dus Postgres
-- weigert vanzelf (foreign key violation, code 23503) zodra er nog
-- inspecties/koppelingen/gebruikers/... aan hangen -- exact het gewenste
-- gedrag ("enkel verwijderen wat nog geen echte historiek heeft, anders
-- archiveren"). De portaal-UI vangt die foutcode op met een duidelijke
-- melding, zelfde patroon als het bestaande verwijderVoertuigType().

create policy superbeheerder_delete_voertuigen on voertuigen for delete to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_delete_gebruikers on gebruikers for delete to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_delete_bedrijven on bedrijven for delete to authenticated
  using (public.is_superbeheerder());
