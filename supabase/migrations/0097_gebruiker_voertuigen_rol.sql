-- ===========================================================================
-- 0097_gebruiker_voertuigen_rol.sql
-- De laatste schrijfpolicy die enkel naar het bedrijf keek
-- ===========================================================================
-- 0092 legde de schrijfrechten vast op wat iemand IS in plaats van enkel bij wie
-- hij hoort. Eén tabel bleef daarbij liggen: gebruiker_voertuigen, de koppeling
-- die bepaalt welke assets een medewerker in de app te zien krijgt.
--
-- Daar staat sinds 0028 een insert- en delete-policy die enkel controleert of de
-- medewerker bij het bedrijf van de ingelogde gebruiker hoort. Elke klantgebruiker
-- kan dus koppelingen leggen en weghalen. Het scherm ervoor zit in de zijbalk en
-- een klant heeft geen zijbalk, dus in de praktijk gebeurt het niet -- maar dat
-- is opnieuw de interface als grendel, en die redenering is in 0092 juist
-- verlaten.
--
-- Wat een verkeerde koppeling aanricht: een chauffeur die een asset niet meer
-- ziet, kan er geen pre-inspectie meer op indienen. Er verschijnt geen fout, er
-- verdwijnt gewoon een toestel uit zijn lijst -- precies het soort stille
-- wijziging dat pas opvalt wanneer iemand achteraf vraagt waarom er drie weken
-- niets is ingediend.
--
-- Vanaf nu: PrevX, of de klant-beheerder van hetzelfde bedrijf.
-- ===========================================================================

drop policy if exists portal_insert_gebruiker_voertuigen on gebruiker_voertuigen;
drop policy if exists portal_delete_gebruiker_voertuigen on gebruiker_voertuigen;

create policy beheer_insert_gebruiker_voertuigen on gebruiker_voertuigen
  for insert to authenticated
  with check (
    public.is_superbeheerder()
    or (
      public.is_klant_beheerder()
      and exists (
        select 1 from gebruikers g
        where g.id = gebruiker_voertuigen.gebruiker_id
          and g.bedrijf_id = public.huidig_bedrijf_id()
      )
    )
  );

create policy beheer_delete_gebruiker_voertuigen on gebruiker_voertuigen
  for delete to authenticated
  using (
    public.is_superbeheerder()
    or (
      public.is_klant_beheerder()
      and exists (
        select 1 from gebruikers g
        where g.id = gebruiker_voertuigen.gebruiker_id
          and g.bedrijf_id = public.huidig_bedrijf_id()
      )
    )
  );

-- Lezen blijft zoals het was: iedereen bij de klant mag zien welke medewerker
-- aan welk toestel hangt. Dat is nodig om de lijst überhaupt te tonen, en er
-- staat niets gevoeligs in.

do $$
declare
  r record;
begin
  raise notice '--- schrijfrechten op gebruiker_voertuigen ---';
  for r in
    select cmd, policyname, coalesce(qual, with_check) as voorwaarde
    from pg_policies
    where schemaname = 'public' and tablename = 'gebruiker_voertuigen'
    order by cmd, policyname
  loop
    raise notice '% % -> %', rpad(r.cmd, 6), rpad(r.policyname, 44), left(r.voorwaarde, 90);
  end loop;
end
$$;
