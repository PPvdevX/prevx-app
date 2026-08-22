-- "Uw samenwerking" uit de portaal-teaser: 4 van 6 bezoekdagen opgenomen in
-- 2026, met daaronder wat er in de formule zit.
--
-- Dit is het enige blok van dat scherm dat de klant vertelt wát hij krijgt voor
-- wat hij betaalt. Zonder dit is het portaal een archief; met dit is het ook
-- een verantwoording.
--
-- Twee stukken, bewust gescheiden:
--
-- 1. `samenwerking` -- de afspraak, per jaar. Per jaar en niet per bedrijf,
--    want een contract verandert: dit jaar zes dagen, volgend jaar acht. Zet je
--    het op `bedrijven`, dan overschrijf je bij elke verlenging de geschiedenis
--    en kan je achteraf niet meer aantonen wat er vorig jaar afgesproken was.
--
-- 2. `planning.bezoekdagen` -- hoeveel van die afspraak een activiteit opgebruikt.
--    Standaard 1: een gepland bezoek is doorgaans een dag. Een toolbox van een
--    uur zet je op 0.5 of 0, een tweedaagse op 2. Zonder zo'n kolom zou je
--    moeten tellen in aantal afspraken, en dan telt een toolbox van een uur even
--    zwaar als een volledige veiligheidsronde.
--
-- Er wordt geteld op status 'afgerond', niet op datum. "Opgenomen" hoort te
-- betekenen dat het ook echt gebeurd is; een bezoek dat gepland stond en niet
-- doorging mag de teller niet doen oplopen.

create table if not exists samenwerking (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  jaar integer not null,
  bezoekdagen_contract numeric(5,1) not null default 0,
  inbegrepen text,
  opmerking text,
  aangemaakt_op timestamptz not null default now(),
  unique (bedrijf_id, jaar)
);

alter table samenwerking enable row level security;

create policy portal_select_samenwerking on samenwerking for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_samenwerking on samenwerking for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_samenwerking on samenwerking for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_samenwerking on samenwerking for delete to authenticated
  using (public.is_superbeheerder());

alter table planning
  add column if not exists bezoekdagen numeric(4,1) not null default 1;

-- ---------------------------------------------------------------------------
-- Meenemen in het verwijderen van een bedrijf
-- ---------------------------------------------------------------------------
-- Enkel de regel voor samenwerking is nieuw; de rest is 0072 ongewijzigd.
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_ids uuid[];
  v_prefix text := p_bedrijf_id::text || '/';
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  select coalesce(array_agg(g.auth_user_id), '{}')
    into v_auth_ids
  from gebruikers g
  where g.bedrijf_id = p_bedrijf_id
    and g.auth_user_id is not null;

  delete from storage.objects
  where bucket_id in ('inspectie-media','documenten','kennisbank',
                      'bedrijfsmiddel-fotos','actiepunt-bewijsstukken')
    and name like v_prefix || '%';

  delete from vergunning_herinneringen
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_goedkeuring_codes
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_antwoorden
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vuurvergunningen where bedrijf_id = p_bedrijf_id;
  delete from vergunning_nummers where bedrijf_id = p_bedrijf_id;

  delete from vergunning_vraag_werktypes
    where vraag_id in (select id from vergunning_vragen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_vragen where bedrijf_id = p_bedrijf_id;
  delete from werktypes where bedrijf_id = p_bedrijf_id;

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
  delete from inspectie_sectie_types
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from samenwerking where bedrijf_id = p_bedrijf_id;
  delete from keuringen where bedrijf_id = p_bedrijf_id;
  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;

  delete from auth.users u
  where u.id = any(v_auth_ids)
    and not exists (select 1 from gebruikers g where g.auth_user_id = u.id)
    and not exists (select 1 from superbeheerders s where s.auth_user_id = u.id);
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
