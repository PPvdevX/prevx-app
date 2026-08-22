-- Sluit fase C af: het afhandelen van een escalatie.
--
-- Een vergunning waarvan de nazorg niet bevestigd raakt, blijft 'actief' staan
-- met escalatie_vereist (0060). Iemand moet dat kunnen afsluiten -- maar niet
-- door te doen alsof de controles wél gebeurd zijn.
--
-- Daarom sluit deze weg de vergunning af mét vermelding dat het via een
-- escalatie ging, en met de verklaring van wie het afhandelde. Het dossier
-- vertelt dan de waarheid: de controles zijn niet tijdig bevestigd, dit is wat
-- er in de plaats is vastgesteld. Zelfde principe als handtekening_methode --
-- een bewijsstuk hoort niet meer zekerheid te suggereren dan het waarmaakt.

alter table vuurvergunningen
  add column if not exists escalatie_afgehandeld_op timestamptz,
  add column if not exists escalatie_afgehandeld_door_id uuid references gebruikers(id),
  add column if not exists escalatie_toelichting text,
  add column if not exists is_incident boolean not null default false;

create or replace function public.rpc_escalatie_afhandelen(
  p_vergunning_id uuid, p_toelichting text, p_als_incident boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_gebruiker_id uuid;
begin
  if p_toelichting is null or btrim(p_toelichting) = '' then
    raise exception 'Geef aan wat er is vastgesteld; zonder verklaring is dit geen afhandeling maar een opruimactie';
  end if;

  select bedrijf_id into v_bedrijf_id from vuurvergunningen where id = p_vergunning_id;
  if v_bedrijf_id is null then
    raise exception 'Onbekende vergunning';
  end if;

  if not (public.is_superbeheerder() or v_bedrijf_id = public.huidig_bedrijf_id()) then
    raise exception 'Niet geautoriseerd';
  end if;

  -- Wie het afhandelt vastleggen, voor zover die persoon een gebruikersrij
  -- heeft. De superbeheerder heeft die niet noodzakelijk bij deze klant.
  select g.id into v_gebruiker_id
  from gebruikers g
  where g.auth_user_id = auth.uid() and g.actief = true
  limit 1;

  update vuurvergunningen set
    status = 'afgesloten',
    afgesloten_op = now(),
    afgesloten_door_id = v_gebruiker_id,
    escalatie_vereist = false,
    escalatie_afgehandeld_op = now(),
    escalatie_afgehandeld_door_id = v_gebruiker_id,
    escalatie_toelichting = btrim(p_toelichting),
    is_incident = coalesce(p_als_incident, false)
  where id = p_vergunning_id
    and status = 'actief';

  if not found then
    raise exception 'Deze vergunning staat niet meer open';
  end if;
end;
$$;

grant execute on function public.rpc_escalatie_afhandelen(uuid, text, boolean) to authenticated;
