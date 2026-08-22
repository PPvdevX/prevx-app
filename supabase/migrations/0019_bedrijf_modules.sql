-- Generiek module-toggle-mechanisme per bedrijf. Vandaag met exact één echte
-- waarde ('preinspecties'), zodat de sidebar kan tonen/grijs-maken naargelang
-- de overeenkomst van de klant. Verdere klantendossier-modules (actiepunten,
-- documenten, planning, meldingen, kennisbank) krijgen later gewoon hun eigen
-- module_key-rij, zonder dat dit mechanisme opnieuw moet wijzigen.

create table if not exists bedrijf_modules (
  bedrijf_id uuid not null references bedrijven(id),
  module_key text not null,
  actief boolean not null default true,
  primary key (bedrijf_id, module_key)
);

alter table bedrijf_modules enable row level security;

-- Klant leest mee welke modules actief zijn (stuurt de UI); superbeheerder ziet alles.
create policy portal_select_bedrijf_modules on bedrijf_modules for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

-- Activeren/deactiveren is een contractbeslissing van de adviseur, geen self-service.
create policy superbeheerder_write_bedrijf_modules on bedrijf_modules for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_bedrijf_modules on bedrijf_modules for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_bedrijf_modules on bedrijf_modules for delete to authenticated
  using (public.is_superbeheerder());

-- Backfill: alle bestaande bedrijven behouden de toegang die ze vandaag al hebben.
insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'preinspecties', true from bedrijven
on conflict do nothing;
