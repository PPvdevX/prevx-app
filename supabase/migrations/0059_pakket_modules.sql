-- Koppelt pakketten aan modules, zodat het toekennen van een formule meteen de
-- juiste toegang geeft in plaats van dat je per klant vijf vinkjes moet zetten.
--
-- Bewust een VOORSTEL, geen dwang: bij het kiezen van een pakket springen de
-- bijhorende modules aan, maar je kan per klant nadien nog afwijken. De praktijk
-- heeft altijd uitzonderingen, en bedrijf_modules werkt vandaag al per klant.
--
-- Twee modules staan bewust in GEEN enkel pakket: preinspecties en
-- vuurvergunning. Dat zijn geen onderdelen van een Partner-formule maar aparte
-- producten met een eigen prijs. Het toepassen van een pakket laat ze dan ook
-- ongemoeid -- anders zou het wisselen van formule stilzwijgend een betaald
-- product uitschakelen.

create table if not exists pakket_modules (
  pakket_id uuid not null references pakketten(id) on delete cascade,
  module_key text not null,
  primary key (pakket_id, module_key)
);

alter table pakket_modules enable row level security;

create policy select_pakket_modules on pakket_modules for select to authenticated
  using (true);

create policy superbeheerder_all_pakket_modules on pakket_modules for all to authenticated
  using (public.is_superbeheerder()) with check (public.is_superbeheerder());

-- De drie Partner-formules krijgen alles. Ze verschillen in bezoekfrequentie --
-- dus in tijd van de adviseur -- niet in wat de klant in zijn dossier mag zien.
-- Een module afschermen kost niets om te geven en voelt als een uitgeklede
-- versie; het portaal is net wat PrevX onderscheidt van een adviseur die een
-- verslag per mail stuurt.
insert into pakket_modules (pakket_id, module_key)
select p.id, m.key
from pakketten p
cross join (values ('actiepunten'),('planning'),('documenten'),('meldingen'),('kennisbank')) as m(key)
where p.naam in ('PrevX Partner - Light','PrevX Partner - Standaard','PrevX Partner - Intensief')
on conflict do nothing;

-- Project is een eenmalige opdracht: vaststellingen en een oplevering, geen
-- doorlopende opvolging.
insert into pakket_modules (pakket_id, module_key)
select p.id, m.key
from pakketten p
cross join (values ('actiepunten'),('documenten')) as m(key)
where p.naam = 'PrevX Project'
on conflict do nothing;

-- Vorming levert lesmateriaal, verder niets.
insert into pakket_modules (pakket_id, module_key)
select p.id, 'kennisbank'
from pakketten p
where p.naam = 'PrevX Vorming'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Pakket toepassen op een klant
-- ---------------------------------------------------------------------------
-- Zet de door pakketten bestuurde modules aan of uit volgens de gekozen
-- formule. Modules die geen enkel pakket bestuurt (preinspecties,
-- vuurvergunning) blijven staan zoals ze stonden.
create or replace function public.rpc_pakket_toepassen(p_bedrijf_id uuid, p_pakket_naam text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pakket_id uuid;
  v_bestuurd text[] := array['actiepunten','planning','documenten','meldingen','kennisbank'];
  v_key text;
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder kan een pakket toepassen';
  end if;

  select id into v_pakket_id from pakketten where naam = p_pakket_naam;
  if v_pakket_id is null then
    raise exception 'Onbekend pakket: %', p_pakket_naam;
  end if;

  foreach v_key in array v_bestuurd loop
    insert into bedrijf_modules (bedrijf_id, module_key, actief)
    values (
      p_bedrijf_id,
      v_key,
      exists (select 1 from pakket_modules pm where pm.pakket_id = v_pakket_id and pm.module_key = v_key)
    )
    on conflict (bedrijf_id, module_key) do update set actief = excluded.actief;
  end loop;
end;
$$;

grant execute on function public.rpc_pakket_toepassen(uuid, text) to authenticated;
