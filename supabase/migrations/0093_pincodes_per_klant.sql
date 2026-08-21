-- ===========================================================================
-- 0093_pincodes_per_klant.sql
-- De pincodevoorraad per klant in plaats van over het hele platform
-- ===========================================================================
-- rpc_genereer_pincode (0051, herzien in 0052) zoekt een code van vier cijfers
-- die door geen enkele ACTIEVE gebruiker gebruikt wordt -- platformbreed. Dat
-- was juist toen de login enkel een pincode was: één code moest toen wereldwijd
-- naar één persoon leiden.
--
-- Sinds 0052 logt een medewerker in met klantcode + pincode. De klantcode
-- scheidt de klanten al, dus twee klanten mogen probleemloos allebei 1234
-- hebben. De globale uniciteit kost sindsdien alleen maar: één gedeelde pot van
-- 10.000 over álle klanten samen, waarin de groei van de ene klant de voorraad
-- van de andere opeet. Dat is vandaag onschuldig en het is de enige plek waar
-- klanten elkaar in de weg kunnen lopen.
--
-- Vanaf nu zoekt de generator binnen één bedrijf. Elke klant heeft zijn eigen
-- 10.000, en de vraag "hoeveel gebruikers mag een klant aanmaken" is daarmee
-- geen technische vraag meer -- enkel nog een commerciële, als je die ooit wil
-- stellen.
--
-- TWEE FUNCTIES, BEWUST
-- De bestaande rpc_genereer_pincode() heeft geen parameter. Ze blijft bestaan --
-- een pagina die nog in een tabblad openstaat moet blijven werken -- en zoekt
-- voortaan binnen het bedrijf van wie ze aanroept. Voor de superbeheerder valt
-- ze terug op platformbreed, want zijn eigen bedrijf is niet de klant die hij op
-- dat moment bekijkt. Nieuw is rpc_genereer_pincode_voor(bedrijf),
-- en die is wél juist voor jou: als superbeheerder in het dossier van een klant
-- is huidig_bedrijf_id() jouw eigen bedrijf, niet dat van de klant die je op dat
-- moment bekijkt. Zonder die parameter zou de oude functie in de voorraad van
-- het verkeerde bedrijf zoeken -- en dan kan er binnen één klant twee keer
-- dezelfde pincode ontstaan. rpc_login_chauffeur_klant neemt bij een dubbele
-- code de eerste de beste rij; dat is precies het soort fout dat pas opvalt
-- wanneer twee mensen elkaars rapporten ondertekenen.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. De bestaande functie: zelfde naam, nu per bedrijf
-- ---------------------------------------------------------------------------
create or replace function public.rpc_genereer_pincode()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_poging int := 0;
  v_bedrijf uuid;
begin
  if public.is_superbeheerder() then
    -- Voor de superbeheerder zegt huidig_bedrijf_id() zijn EIGEN bedrijf, en dat
    -- is bijna nooit de klant waarvoor hij op dat moment een code vraagt. Dan
    -- liever platformbreed zoeken: verspillend maar nooit fout. Wie het juist
    -- wil, gebruikt rpc_genereer_pincode_voor hieronder.
    v_bedrijf := null;
  else
    v_bedrijf := public.huidig_bedrijf_id();
    if v_bedrijf is null then
      raise exception 'Niet geautoriseerd';
    end if;
  end if;

  loop
    v_poging := v_poging + 1;
    if v_poging > 200 then
      raise exception 'Geen vrije pincode gevonden; de voorraad van 4 cijfers raakt op bij deze klant.';
    end if;

    v_code := lpad(((public.willekeurige_byte() * 256 + public.willekeurige_byte()) % 10000)::text, 4, '0');

    -- v_bedrijf is null wanneer de superbeheerder deze oude, parameterloze
    -- functie aanroept. Dan valt ze terug op platformbreed zoeken: verspillend,
    -- maar nooit fout. De nieuwe functie hieronder is voor dat geval bedoeld.
    exit when not exists (
      select 1 from gebruikers
      where pincode = v_code
        and actief = true
        and (v_bedrijf is null or bedrijf_id = v_bedrijf)
    );
  end loop;

  return v_code;
end;
$$;

revoke execute on function public.rpc_genereer_pincode() from public;
grant execute on function public.rpc_genereer_pincode() to authenticated;


-- ---------------------------------------------------------------------------
-- 2. De nieuwe functie: zeg voor welke klant
-- ---------------------------------------------------------------------------
create or replace function public.rpc_genereer_pincode_voor(p_bedrijf_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_poging int := 0;
begin
  if p_bedrijf_id is null then
    raise exception 'Zeg voor welke klant';
  end if;

  -- De superbeheerder mag het voor elke klant; een klantgebruiker enkel voor
  -- zijn eigen bedrijf. Wie er binnen dat bedrijf gebruikers mag aanmaken,
  -- bewaken de policies uit 0092 -- niet deze functie: een pincode op zich
  -- opent niets zolang ze niet op een gebruikersrij staat.
  if not (public.is_superbeheerder() or p_bedrijf_id = public.huidig_bedrijf_id()) then
    raise exception 'Niet geautoriseerd';
  end if;

  loop
    v_poging := v_poging + 1;
    if v_poging > 200 then
      raise exception 'Geen vrije pincode gevonden; de voorraad van 4 cijfers raakt op bij deze klant.';
    end if;

    v_code := lpad(((public.willekeurige_byte() * 256 + public.willekeurige_byte()) % 10000)::text, 4, '0');

    exit when not exists (
      select 1 from gebruikers
      where pincode = v_code and actief = true and bedrijf_id = p_bedrijf_id
    );
  end loop;

  return v_code;
end;
$$;

revoke execute on function public.rpc_genereer_pincode_voor(uuid) from public;
grant execute on function public.rpc_genereer_pincode_voor(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 3. Dubbele pincodes binnen één klant onmogelijk maken
-- ---------------------------------------------------------------------------
-- De generator vermijdt botsingen, maar een pincode kan ook met de hand gezet
-- worden (het veld staat gewoon in het gebruikersscherm). Een unieke index maakt
-- er een harde regel van in plaats van een gewoonte.
--
-- Enkel op actieve gebruikers: een medewerker uit dienst houdt zijn oude code in
-- de rij staan, en die hoort een nieuwe collega niet in de weg te zitten.
--
-- De index wordt alleen aangemaakt als de gegevens hem vandaag al halen. Zijn er
-- dubbels, dan noemt het script ze en verandert het niets -- een migratie die
-- halverwege afbreekt op bestaande data is erger dan een migratie die zegt wat
-- er eerst rechtgezet moet worden.
do $$
declare
  r record;
  v_dubbels int := 0;
begin
  for r in
    select b.naam as bedrijf, g.pincode, count(*) as aantal,
           string_agg(g.naam, ', ' order by g.naam) as wie
    from gebruikers g
    join bedrijven b on b.id = g.bedrijf_id
    where g.actief = true
    group by b.naam, g.pincode
    having count(*) > 1
  loop
    v_dubbels := v_dubbels + 1;
    raise notice 'DUBBELE PINCODE % bij %: % (% gebruikers)', r.pincode, r.bedrijf, r.wie, r.aantal;
  end loop;

  if v_dubbels > 0 then
    raise notice 'Index NIET aangemaakt: zet eerst bovenstaande % dubbels recht (Gebruikers > Reset pincode) en draai deze migratie opnieuw.', v_dubbels;
  else
    create unique index if not exists idx_gebruikers_pincode_per_bedrijf
      on gebruikers (bedrijf_id, pincode) where actief;
    raise notice 'Geen dubbele pincodes gevonden; unieke index aangemaakt.';
  end if;
end
$$;
