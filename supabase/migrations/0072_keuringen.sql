-- Vervalkalender: keuringsplichtige zaken met een vervaldatum.
--
-- Dit is het enige stuk uit de portaal-teaser waar nog geen datamodel voor was.
-- Niet te verwarren met `planning` (0024): dat gaat over een afspraak óp een
-- datum -- een bezoek, een toolbox. Een keuring is het omgekeerde: iets dat
-- geldig is tót een datum en daarna niet meer. Je wil er niet naartoe plannen,
-- je wil gewaarschuwd worden voor het te laat is.
--
-- vervaldatum wordt bewust APART opgeslagen en niet berekend uit
-- laatste_keuring + periodiciteit. Op een attest staat een geldigheidsdatum, en
-- die valt lang niet altijd samen met die rekensom -- een keurder die twee
-- weken later langskwam, een attest dat tot einde jaar loopt. Rekenen we het
-- uit, dan overschrijven we wat er op het papier staat, en dat papier is het
-- bewijsstuk. De rekensom blijft een hulpje bij het invullen, geen waarheid.

create table if not exists keuringen (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  omschrijving text not null,
  -- Vrije tekst i.p.v. een vaste lijst: welke keuringen verplicht zijn hangt af
  -- van de sector, en een lijst die niet klopt kost meer dan ze oplevert. Een
  -- codelijst kan er later bij als blijkt wat er echt terugkomt.
  categorie text,
  aantal integer,
  uitvoerder text,
  periodiciteit_maanden integer,
  laatste_keuring date,
  vervaldatum date not null,
  attest_url text,
  opmerking text,
  actief boolean not null default true,
  aangemaakt_op timestamptz not null default now()
);

create index if not exists idx_keuringen_bedrijf_verval on keuringen (bedrijf_id, vervaldatum);

alter table keuringen enable row level security;

-- Zelfde opzet als actiepunten (0021): de klant leest zijn eigen dossier, de
-- superbeheerder leest alles en is de enige die schrijft. Een klant die zijn
-- eigen vervaldatums kan opschuiven, heeft geen vervalkalender maar een
-- wensenlijst.
create policy portal_select_keuringen on keuringen for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_keuringen on keuringen for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_keuringen on keuringen for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_keuringen on keuringen for delete to authenticated
  using (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- Meenemen in het verwijderen van een bedrijf
-- ---------------------------------------------------------------------------
-- Elke nieuwe tabel met een bedrijf_id moet hierin, anders loopt "bedrijf
-- verwijderen" vast op een onzichtbare FK-blokkade. Alleen die ene regel is
-- nieuw; de rest is 0069 ongewijzigd.
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
