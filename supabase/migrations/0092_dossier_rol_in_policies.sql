-- ===========================================================================
-- 0092_dossier_rol_in_policies.sql
-- Schrijfrechten die de rol lezen, niet enkel het bedrijf
-- ===========================================================================
-- Het gat: bijna alle schrijfpolicies staan op `bedrijf_id = huidig_bedrijf_id()`.
-- Dat betekent: élke ingelogde gebruiker van een klant mag alles van die klant
-- wijzigen. Tot nu was dat verdedigbaar, want de schermen die het aankonden --
-- checklist, gebruikers, bedrijfsfiche, huisstijl, de vragenlijst van de
-- vuurvergunning -- staan enkel in de zijbalk, en een klant heeft geen zijbalk
-- (zetKlantModus in account.html). De interface was dus de enige grendel.
--
-- Een interface is geen grendel. Wie met een klantlogin de console opent, of
-- gewoon de REST-API aanspreekt met zijn eigen token, komt er langs. Zolang het
-- klantgezicht groeit, groeit dat risico mee.
--
-- Deze migratie legt de schrijfrechten vast op wat iemand IS, niet enkel bij wie
-- hij hoort:
--
--   PrevX (superbeheerder)   de opbouw van het dossier: checklist, assettypes,
--                            bedrijfsfiche en huisstijl, de vragenlijst van de
--                            vuurvergunning, en alles wat definitief wist.
--   Klant-beheerder          zijn eigen mensen: gebruikers aanmaken en
--                            bijwerken. (Het toekennen van een dossierrol
--                            blijft bij PrevX -- die trigger staat in 0071 en
--                            blijft ongemoeid.)
--   Iedereen bij de klant    wat de klant hoort te doen en al kon: keuringen
--                            (0087), meldingen, actiepunten met bewijsstuk,
--                            assets bijwerken, LMRA's en vuurvergunningen via
--                            hun RPC's. Daar verandert niets aan.
--
-- WAAROM DE POLICIES EERST WEG EN DAN OPNIEUW
-- Namen zijn over 90 migraties heen gegroeid, en een policy die ik hier niet bij
-- naam ken, blijft anders stilletjes staan naast de nieuwe -- policies zijn
-- OR-logica, dus één vergeten policy houdt het gat open. Daarom worden per tabel
-- eerst álle schrijfpolicies verwijderd en daarna precies gezet wat er hoort te
-- staan. Leespolicies blijven ongemoeid, behalve waar ze in een `for all`-policy
-- verweven zaten; die worden expliciet opnieuw aangemaakt.
--
-- NA HET DRAAIEN drukt het laatste blok de volledige eindtoestand af. Kijk die
-- na: dat is de enige plek waar je in één oogopslag ziet wie wat mag.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. Wie is de ingelogde gebruiker?
-- ---------------------------------------------------------------------------
-- Security definer, want de functie leest gebruikers terwijl RLS op die tabel
-- staat. Stable: binnen één query verandert het antwoord niet.
create or replace function public.is_klant_beheerder()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from gebruikers
    where auth_user_id = auth.uid()
      and actief = true
      and dossier_rol = 'klant_beheerder'
  );
$$;

comment on function public.is_klant_beheerder() is
  'True voor een ingelogde klantgebruiker met dossierrol klant_beheerder. Bedoeld om te combineren met bedrijf_id = huidig_bedrijf_id(); de functie zelf zegt niets over welk bedrijf.';

-- Zoals in 0020: Postgres geeft EXECUTE standaard aan PUBLIC. Intrekken en enkel
-- aan authenticated geven -- anon heeft hier niets te zoeken.
revoke execute on function public.is_klant_beheerder() from public;
grant execute on function public.is_klant_beheerder() to authenticated;


-- ---------------------------------------------------------------------------
-- 2. Bestaande schrijfpolicies weghalen op de tabellen die we hier vastleggen
-- ---------------------------------------------------------------------------
do $$
declare
  v_tabellen text[] := array[
    'inspectie_secties','inspectie_punten','inspectie_sectie_types','inspectie_punt_types',
    'voertuig_types','bedrijven','gebruikers',
    'werktypes','vergunning_vragen','vergunning_vraag_werktypes'
  ];
  r record;
begin
  for r in
    select policyname, tablename, cmd
    from pg_policies
    where schemaname = 'public'
      and tablename = any (v_tabellen)
      and cmd in ('INSERT','UPDATE','DELETE','ALL')
  loop
    raise notice 'weg: % op % (%)', r.policyname, r.tablename, r.cmd;
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end
$$;


-- ---------------------------------------------------------------------------
-- 3. Checklist -- PrevX bouwt, de klant leest
-- ---------------------------------------------------------------------------
-- De checklist is het product zelf. Een klant die er punten uit haalt, haalt de
-- bewijskracht uit zijn eigen rapporten -- en het valt niemand op tot iemand het
-- dossier nodig heeft.
create policy superbeheerder_schrijf_secties on inspectie_secties
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_schrijf_punten on inspectie_punten
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

-- Deze twee koppeltabellen hadden een `for all`-policy waar het lezen in zat;
-- die is in blok 2 mee verdwenen en komt hier terug, nu gesplitst.
create policy portal_lees_sectie_types on inspectie_sectie_types
  for select to authenticated
  using (exists (
    select 1 from inspectie_secties s
    where s.id = inspectie_sectie_types.sectie_id
      and (s.bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder())
  ));

create policy superbeheerder_schrijf_sectie_types on inspectie_sectie_types
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy portal_lees_punt_types on inspectie_punt_types
  for select to authenticated
  using (exists (
    select 1 from inspectie_punten p
    join inspectie_secties s on s.id = p.sectie_id
    where p.id = inspectie_punt_types.punt_id
      and (s.bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder())
  ));

create policy superbeheerder_schrijf_punt_types on inspectie_punt_types
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());


-- ---------------------------------------------------------------------------
-- 4. Assettypes -- structuur, dus PrevX
-- ---------------------------------------------------------------------------
-- Een type stuurt aan welke checklist een asset krijgt (rpc_checklist, 0048).
-- Wie types kan aanmaken of wissen, stuurt dus de inhoud van de inspectie.
-- Assets zelf blijven wel van de klant: die mag hij toevoegen en bijwerken.
create policy portal_lees_voertuig_types on voertuig_types
  for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_schrijf_voertuig_types on voertuig_types
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());


-- ---------------------------------------------------------------------------
-- 5. Bedrijfsfiche en huisstijl -- PrevX
-- ---------------------------------------------------------------------------
-- Hier staan pakket, tarief, contractdatums en het afzenderadres van de mail.
-- Dat zijn afspraken tussen PrevX en de klant, geen velden die één kant alleen
-- bijwerkt. Het scherm zat al achter de zijbalk; nu de databank ook.
create policy superbeheerder_insert_bedrijven on bedrijven
  for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_bedrijven on bedrijven
  for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

-- Geen delete-policy: een bedrijf verdwijnt enkel via
-- rpc_verwijder_bedrijf_cascade (0043 e.v.), die zelf op superbeheerder
-- controleert en de opslag mee opruimt.


-- ---------------------------------------------------------------------------
-- 6. Gebruikers -- hier leest de policy wél de dossierrol
-- ---------------------------------------------------------------------------
-- Een klant-beheerder hoort zijn eigen mensen te kunnen toevoegen en bijwerken;
-- dat is precies wat die rol betekent. Een klant-medewerker niet: die zou zich
-- anders een pincode van een collega kunnen zetten.
--
-- Let op wat hier NIET verandert: de trigger uit 0071 blijft een klant beletten
-- om dossier_rol toe te kennen of te wijzigen, ook een klant-beheerder. Anders
-- zou hij zichzelf of een collega rechten kunnen geven die jij niet gaf.
create policy beheer_insert_gebruikers on gebruikers
  for insert to authenticated
  with check (
    public.is_superbeheerder()
    or (bedrijf_id = public.huidig_bedrijf_id() and public.is_klant_beheerder())
  );

create policy beheer_update_gebruikers on gebruikers
  for update to authenticated
  using (
    public.is_superbeheerder()
    or (bedrijf_id = public.huidig_bedrijf_id() and public.is_klant_beheerder())
  )
  with check (
    public.is_superbeheerder()
    or (bedrijf_id = public.huidig_bedrijf_id() and public.is_klant_beheerder())
  );

-- Definitief wissen blijft bij PrevX, zoals bij assets (0040) en om dezelfde
-- reden: een gebruikersrij hangt aan inspecties, LMRA's en vergunningen, en wat
-- eraan hangt is bewijs.
create policy superbeheerder_delete_gebruikers on gebruikers
  for delete to authenticated
  using (public.is_superbeheerder());


-- ---------------------------------------------------------------------------
-- 7. Vuurvergunning: werktypes en vragenlijst -- PrevX
-- ---------------------------------------------------------------------------
-- Dezelfde redenering als bij de checklist: dit is de motor onder de vergunning.
-- De vergunningen zelf lopen via RPC's die hun eigen controles doen; daar raakt
-- deze migratie niet aan.
create policy superbeheerder_schrijf_werktypes on werktypes
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_schrijf_vergunning_vragen on vergunning_vragen
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy portal_lees_vraag_werktypes on vergunning_vraag_werktypes
  for select to authenticated
  using (exists (
    select 1 from vergunning_vragen v
    where v.id = vergunning_vraag_werktypes.vraag_id
      and (v.bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder())
  ));

create policy superbeheerder_schrijf_vraag_werktypes on vergunning_vraag_werktypes
  for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());


-- ---------------------------------------------------------------------------
-- 8. De eindtoestand afdrukken
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  v_vorige text := '';
begin
  raise notice '--- schrijfrechten na deze migratie ---';
  for r in
    select tablename, cmd, policyname,
           coalesce(qual, with_check) as voorwaarde
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'inspectie_secties','inspectie_punten','inspectie_sectie_types','inspectie_punt_types',
        'voertuig_types','bedrijven','gebruikers',
        'werktypes','vergunning_vragen','vergunning_vraag_werktypes')
    order by tablename, cmd, policyname
  loop
    if r.tablename <> v_vorige then
      raise notice ' ';
      raise notice '%', r.tablename;
      v_vorige := r.tablename;
    end if;
    raise notice '   % %  ->  %', rpad(r.cmd, 6), rpad(r.policyname, 42), left(coalesce(r.voorwaarde,''), 110);
  end loop;
end
$$;
