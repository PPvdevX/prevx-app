-- ===========================================================================
-- 0094_pakket_stuurt_modules_en_bezoeken.sql
-- Eén formule bepaalt wat de klant ziet én hoeveel bezoeken hij krijgt
-- ===========================================================================
-- Wat er al was (0059): een pakket kende een setje modules, en het kiezen van
-- een formule in de bedrijfsfiche zette die aan of uit. Twee beperkingen:
--
--   1. De matrix dekte vijf modules. Pre-inspecties, vuurvergunning en LMRA
--      bleven er bewust buiten omdat ze als losse producten golden. Gevolg: een
--      formule zei niet volledig wat een klant ziet, en voor die drie moest je
--      per klant apart een bolletje omzetten.
--   2. De formule zei niets over het aantal bezoekdagen, terwijl dat nu net het
--      verschil is tussen Light, Standaard en Intensief. Dat aantal werd met de
--      hand ingetikt bij elke klant.
--
-- Vanaf nu geldt: je vinkt per pakket aan welke modules erbij horen -- alle
-- acht, geen uitzonderingen meer -- en je zet erbij hoeveel bezoekdagen het
-- pakket voorziet. Bij het toekennen van een formule volgt de rest vanzelf.
--
-- LET OP -- EEN PAKKET ZONDER AANGEVINKTE MODULES ZET ALLES UIT.
-- Dat was in 0059 al zo en het blijft zo: de matrix is de waarheid. Elk pakket
-- dat je in Codelijsten toevoegt zonder er modules bij aan te vinken, schakelt
-- bij toepassing dus alles uit bij die klant. Blok 5 hieronder noemt de
-- pakketten waar vandaag niets bij staat, zodat je ze niet per ongeluk op een
-- klant loslaat.
--
-- Om die reden bestaat rpc_pakket_voorstel: het portaal vraagt eerst wat er zou
-- veranderen, toont dat, en past pas toe na bevestiging. Een formulewissel mag
-- nooit stilzwijgend een module uitzetten waar de klant voor betaalt.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. Eén catalogus van modules
-- ---------------------------------------------------------------------------
-- De tabel modules (0050) kende er drie: pre-inspecties, vuurvergunning en LMRA.
-- De vijf dossiermodules bestonden enkel als tekstsleutel in bedrijf_modules en
-- pakket_modules -- nergens stond wat ze heten of in welke volgorde ze horen.
-- Dat maakt een aanvinklijst bouwen onmogelijk zonder die namen te herhalen in
-- de schermcode.
--
-- Ze komen er nu bij. Maar rpc_modules voedt het keuzescherm van de CHAUFFEURS-
-- app, en daar bestaat geen scherm voor documenten of planning. Vandaar in_app:
-- de app toont enkel wat ze zelf kan tonen, het portaal ziet de hele lijst.
alter table modules add column if not exists in_app boolean not null default false;

comment on column modules.in_app is
  'Heeft deze module een scherm in de chauffeurs-app? rpc_modules toont enkel deze. De dossiermodules bestaan alleen in het portaal.';

update modules set in_app = true where key in ('preinspecties','vuurvergunning','lmra');

insert into modules (key, naam, volgorde, actief) values
  ('actiepunten', 'Actiepunten', 10, true),
  ('planning',    'Planning en keuringen', 20, true),
  ('documenten',  'Documenten', 30, true),
  ('meldingen',   'Meldingen', 40, true),
  ('kennisbank',  'Kennisbank', 50, true)
on conflict (key) do nothing;

-- De drie app-modules achteraan, zodat de aanvinklijst eerst het dossier toont.
update modules set volgorde = 60 where key = 'preinspecties';
update modules set volgorde = 70 where key = 'vuurvergunning';
update modules set volgorde = 80 where key = 'lmra';

-- De app kreeg voordien de hele tabel te zien. Nu enkel wat ze kan openen --
-- anders verschijnt "Documenten" als keuze op een gsm en gebeurt er niets.
create or replace function public.rpc_modules(p_gebruiker_id uuid)
returns table(key text, naam text, volgorde int)
language sql
security definer
set search_path = public
as $$
  select m.key, m.naam, m.volgorde
  from modules m
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true
  join bedrijf_modules bm on bm.bedrijf_id = g.bedrijf_id and bm.module_key = m.key and bm.actief = true
  where m.actief = true and m.in_app = true
  order by m.volgorde;
$$;

grant execute on function public.rpc_modules(uuid) to anon;


-- ---------------------------------------------------------------------------
-- 2. Wat een pakket voorziet
-- ---------------------------------------------------------------------------
-- bezoekdagen als numeric(4,1): halve dagen bestaan, honderden dagen niet.
-- inbegrepen is de zin die de klant in zijn dossier te zien krijgt boven de
-- balk "x van y bezoekdagen opgenomen"; die stond tot nu per klant met de hand
-- ingetikt, terwijl hij per formule hetzelfde hoort te zijn.
alter table pakketten
  add column if not exists bezoekdagen numeric(4,1),
  add column if not exists inbegrepen text;

comment on column pakketten.bezoekdagen is
  'Bezoekdagen per jaar die deze formule voorziet. Leeg = de formule zegt er niets over; rpc_pakket_toepassen laat samenwerking dan ongemoeid.';


-- ---------------------------------------------------------------------------
-- 3. Wat zou er veranderen? -- vragen vóór doen
-- ---------------------------------------------------------------------------
-- Geeft terug wat een formule zou aanrichten bij deze klant, zonder iets te
-- wijzigen. Het portaal toont dat en past pas toe na bevestiging.
create or replace function public.rpc_pakket_voorstel(p_bedrijf_id uuid, p_pakket_naam text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pakket record;
  v_aan text[] := '{}';
  v_uit text[] := '{}';
  v_ongewijzigd int := 0;
  r record;
  v_jaar int := extract(year from current_date)::int;
  v_huidig numeric;
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder kan een pakket toepassen';
  end if;

  select * into v_pakket from pakketten where naam = p_pakket_naam;
  if not found then
    raise exception 'Onbekend pakket: %', p_pakket_naam;
  end if;

  for r in
    select m.key, m.naam,
           exists (select 1 from pakket_modules pm
                   where pm.pakket_id = v_pakket.id and pm.module_key = m.key) as hoort_erbij,
           coalesce((select bm.actief from bedrijf_modules bm
                     where bm.bedrijf_id = p_bedrijf_id and bm.module_key = m.key), false) as staat_aan
    from modules m
    where m.actief = true
    order by m.volgorde
  loop
    if r.hoort_erbij and not r.staat_aan then
      v_aan := v_aan || r.naam;
    elsif not r.hoort_erbij and r.staat_aan then
      v_uit := v_uit || r.naam;
    else
      v_ongewijzigd := v_ongewijzigd + 1;
    end if;
  end loop;

  select bezoekdagen_contract into v_huidig
  from samenwerking where bedrijf_id = p_bedrijf_id and jaar = v_jaar;

  return jsonb_build_object(
    'pakket', v_pakket.naam,
    'aan', to_jsonb(v_aan),
    'uit', to_jsonb(v_uit),
    'ongewijzigd', v_ongewijzigd,
    'jaar', v_jaar,
    'bezoekdagen_pakket', v_pakket.bezoekdagen,
    'bezoekdagen_nu', v_huidig,
    -- Leeg veld = gewoon invullen. Staat er al iets anders, dan moet iemand
    -- beslissen: misschien is er bewust van de formule afgeweken.
    'bezoekdagen_vraag', (v_pakket.bezoekdagen is not null
                          and v_huidig is not null
                          and v_huidig <> v_pakket.bezoekdagen)
  );
end;
$$;

revoke execute on function public.rpc_pakket_voorstel(uuid, text) from public;
grant execute on function public.rpc_pakket_voorstel(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 4. Toepassen
-- ---------------------------------------------------------------------------
-- Twee signaturen: de bestaande met twee argumenten blijft werken (een pagina
-- die nog openstaat), en overschrijft dan nooit bestaande bezoekdagen. De
-- nieuwe met drie zegt expliciet of dat wél mag.
create or replace function public.rpc_pakket_toepassen(
  p_bedrijf_id uuid,
  p_pakket_naam text,
  p_bezoekdagen_overschrijven boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pakket record;
  v_jaar int := extract(year from current_date)::int;
  v_huidig numeric;
  v_aantal_aan int := 0;
  v_aantal_uit int := 0;
  r record;
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder kan een pakket toepassen';
  end if;

  select * into v_pakket from pakketten where naam = p_pakket_naam;
  if not found then
    raise exception 'Onbekend pakket: %', p_pakket_naam;
  end if;

  -- De matrix is de waarheid: elke module uit de catalogus krijgt de stand die
  -- het pakket voorschrijft. Niets blijft buiten schot, ook pre-inspecties,
  -- vuurvergunning en LMRA niet -- vandaar dat het portaal eerst het voorstel
  -- toont.
  for r in
    select m.key,
           exists (select 1 from pakket_modules pm
                   where pm.pakket_id = v_pakket.id and pm.module_key = m.key) as hoort_erbij
    from modules m
    where m.actief = true
  loop
    if r.hoort_erbij then v_aantal_aan := v_aantal_aan + 1;
    else v_aantal_uit := v_aantal_uit + 1;
    end if;

    insert into bedrijf_modules (bedrijf_id, module_key, actief)
    values (p_bedrijf_id, r.key, r.hoort_erbij)
    on conflict (bedrijf_id, module_key) do update set actief = excluded.actief;
  end loop;

  -- Bezoekdagen. Zegt de formule er niets over, dan blijft samenwerking zoals
  -- ze is: een leeg veld op het pakket is geen uitspraak "nul dagen".
  if v_pakket.bezoekdagen is not null then
    select bezoekdagen_contract into v_huidig
    from samenwerking where bedrijf_id = p_bedrijf_id and jaar = v_jaar;

    if v_huidig is null then
      insert into samenwerking (bedrijf_id, jaar, bezoekdagen_contract, inbegrepen)
      values (p_bedrijf_id, v_jaar, v_pakket.bezoekdagen, v_pakket.inbegrepen)
      on conflict (bedrijf_id, jaar) do update
        set bezoekdagen_contract = excluded.bezoekdagen_contract,
            inbegrepen = coalesce(samenwerking.inbegrepen, excluded.inbegrepen);
    elsif coalesce(p_bezoekdagen_overschrijven, false) then
      update samenwerking
      set bezoekdagen_contract = v_pakket.bezoekdagen,
          inbegrepen = coalesce(inbegrepen, v_pakket.inbegrepen)
      where bedrijf_id = p_bedrijf_id and jaar = v_jaar;
    end if;
  end if;

  return jsonb_build_object(
    'pakket', v_pakket.naam,
    'modules_aan', v_aantal_aan,
    'modules_uit', v_aantal_uit,
    'jaar', v_jaar,
    'bezoekdagen', v_pakket.bezoekdagen
  );
end;
$$;

revoke execute on function public.rpc_pakket_toepassen(uuid, text, boolean) from public;
grant execute on function public.rpc_pakket_toepassen(uuid, text, boolean) to authenticated;

-- De oude vorm met twee argumenten: laat bestaande bezoekdagen met rust. Ze gaf
-- tot nu void terug; een returntype wijzigen kan Postgres enkel na een drop.
drop function if exists public.rpc_pakket_toepassen(uuid, text);

create or replace function public.rpc_pakket_toepassen(p_bedrijf_id uuid, p_pakket_naam text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.rpc_pakket_toepassen(p_bedrijf_id, p_pakket_naam, false);
end;
$$;

revoke execute on function public.rpc_pakket_toepassen(uuid, text) from public;
grant execute on function public.rpc_pakket_toepassen(uuid, text) to authenticated;


-- ---------------------------------------------------------------------------
-- 5. Welke pakketten staan er leeg?
-- ---------------------------------------------------------------------------
-- De matrix uit 0059 werd gevuld op naam, voor vijf namen. Elk pakket dat je
-- sindsdien toevoegde of hernoemde, staat leeg -- en toepassen zou bij die klant
-- alles uitzetten. Beter dat je dat hier leest dan bij een klant.
do $$
declare
  r record;
  v_leeg int := 0;
begin
  for r in
    select p.naam,
           (select count(*) from pakket_modules pm where pm.pakket_id = p.id) as aantal,
           p.bezoekdagen
    from pakketten p
    where p.actief = true
    order by p.volgorde
  loop
    if r.aantal = 0 then
      v_leeg := v_leeg + 1;
      raise notice 'LEEG: "%" heeft geen enkele module aangevinkt -- toepassen zet alles uit', r.naam;
    else
      raise notice 'ok: "%" -- % modules, % bezoekdagen', r.naam, r.aantal,
        coalesce(r.bezoekdagen::text, 'geen');
    end if;
  end loop;

  if v_leeg > 0 then
    raise notice ' ';
    raise notice 'Vul die % pakketten aan in Codelijsten > Pakketten voor je ze op een klant toepast.', v_leeg;
  end if;
end
$$;
