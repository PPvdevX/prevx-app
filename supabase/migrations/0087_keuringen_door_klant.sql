-- Wie bij de klant over keuringen gaat, mag ze invoeren en afvinken.
--
-- Tot nu schreef alleen de superbeheerder, met deze reden in 0072:
--
--   "Een klant die zijn eigen vervaldatums kan opschuiven, heeft geen
--    vervalkalender maar een wensenlijst."
--
-- Dat argument gaat over verzetten, niet over invoeren. Keuringen worden
-- doorgaans door een externe keuringsinstelling uitgevoerd en het is de klant
-- die het attest in handen krijgt. Moet de adviseur dat telkens overtikken,
-- dan loopt de kalender achter op de werkelijkheid -- precies wat een
-- vervalkalender niet mag doen.
--
-- Wat het bezwaar opvangt is niet minder rechten maar een spoor: bij elke rij
-- staat wie ze invoerde en wie ze laatst wijzigde. Een opgeschoven datum is
-- dan geen anonieme datum meer. Dat spoor wordt door een trigger gezet en niet
-- door de browser meegestuurd: anders schrijft een klant er "PrevX" in.
--
-- Verwijderen blijft bij de superbeheerder. Daar hoort actief=false bij: een
-- keuring op inactief zetten haalt haar uit de kalender en is dus verwijderen
-- met een andere naam.

-- ---------------------------------------------------------------------------
-- Hulpfunctie
-- ---------------------------------------------------------------------------
-- Op `rol` en niet op `dossier_rol`: het gaat om wie er in het bedrijf over
-- keuringen gaat, niet om wie het dossier beheert. Beheerder, preventieadviseur
-- en leidinggevende mogen invoeren en opvolgen; een chauffeur niet. Die rijdt
-- met het toestel, hij gaat niet over het attest.
--
-- Portaaltoegang is een aparte voorwaarde die hier niet herhaald hoeft te
-- worden: zonder auth_user_id is auth.uid() nooit gelijk, en dan geeft deze
-- functie sowieso false.
create or replace function public.mag_keuringen_beheren()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from gebruikers g
    where g.auth_user_id = auth.uid()
      and g.actief
      and g.rol in ('beheerder', 'preventieadviseur', 'leidinggevende')
  );
$$;

revoke execute on function public.mag_keuringen_beheren() from public, anon;
grant execute on function public.mag_keuringen_beheren() to authenticated;

-- ---------------------------------------------------------------------------
-- Herkomst
-- ---------------------------------------------------------------------------
alter table keuringen
  add column if not exists ingevoerd_door text,
  add column if not exists gewijzigd_door text,
  add column if not exists gewijzigd_op timestamptz;

-- Naam en niet enkel een verwijzing naar gebruikers: een medewerker die het
-- bedrijf verlaat wordt verwijderd, en dan hoort er in het dossier nog altijd
-- te staan wie die keuring destijds invoerde.
create or replace function public.zet_keuring_herkomst()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wie text;
begin
  if auth.uid() is null then
    -- SQL Editor, service-role, security definer-RPC. Wegen die al
    -- beheerderstoegang veronderstellen; daar valt geen persoon aan te wijzen.
    v_wie := coalesce(
      case when tg_op = 'INSERT' then new.ingevoerd_door else null end,
      'PrevX');
  elsif public.is_superbeheerder() then
    v_wie := 'PrevX';
  else
    select g.naam into v_wie
    from gebruikers g
    where g.auth_user_id = auth.uid()
    limit 1;
    v_wie := coalesce(v_wie, 'Onbekend');
  end if;

  if tg_op = 'INSERT' then
    new.ingevoerd_door := v_wie;
    new.gewijzigd_door := null;
    new.gewijzigd_op := null;
    return new;
  end if;

  -- De invoerder ligt vast; enkel de laatste wijziging schuift op.
  new.ingevoerd_door := old.ingevoerd_door;
  new.gewijzigd_door := v_wie;
  new.gewijzigd_op := now();

  -- Op inactief zetten is verwijderen met een andere naam.
  if auth.uid() is not null and not public.is_superbeheerder()
     and old.actief and not new.actief then
    raise exception 'Enkel de preventieadviseur kan een keuring uit de kalender halen';
  end if;

  -- Een keuring naar een ander bedrijf schuiven hoort nergens thuis.
  if new.bedrijf_id is distinct from old.bedrijf_id then
    raise exception 'Een keuring kan niet naar een ander bedrijf verplaatst worden';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_keuring_herkomst on keuringen;
create trigger trg_keuring_herkomst
  before insert or update on keuringen
  for each row execute function public.zet_keuring_herkomst();

-- Bestaande rijen komen van de adviseur: voor deze migratie kon niemand anders
-- schrijven.
update keuringen set ingevoerd_door = 'PrevX' where ingevoerd_door is null;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
drop policy if exists superbeheerder_insert_keuringen on keuringen;
drop policy if exists superbeheerder_update_keuringen on keuringen;

create policy schrijf_keuringen_insert on keuringen for insert to authenticated
  with check (
    public.is_superbeheerder()
    or (public.mag_keuringen_beheren() and bedrijf_id = public.huidig_bedrijf_id())
  );

create policy schrijf_keuringen_update on keuringen for update to authenticated
  using (
    public.is_superbeheerder()
    or (public.mag_keuringen_beheren() and bedrijf_id = public.huidig_bedrijf_id())
  )
  with check (
    public.is_superbeheerder()
    or (public.mag_keuringen_beheren() and bedrijf_id = public.huidig_bedrijf_id())
  );

-- superbeheerder_delete_keuringen uit 0072 blijft ongewijzigd: verwijderen
-- blijft bij de adviseur.
