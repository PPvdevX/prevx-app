-- Superbeheerder-rol: de preventieadviseur zelf (PrevX), die als enige over alle
-- klantdossiers heen mag kijken. Dit is bewust additief: geen van de bestaande
-- 16 policies uit 0002/0003/0005/0007/0012/0013 wordt aangeraakt of vervangen.
-- Postgres OR't meerdere permissive policies voor dezelfde actie automatisch
-- samen, dus onderstaande policies breiden enkel SELECT-toegang uit.
--
-- Bewust enkel leestoegang, geen schrijftoegang: dit is een zichtbaarheidslaag
-- voor de eigenaar van de klantrelatie, geen koppeling tussen producten.

create table if not exists superbeheerders (
  auth_user_id uuid primary key references auth.users(id)
);

alter table superbeheerders enable row level security;

revoke all on superbeheerders from anon, authenticated;

create or replace function public.is_superbeheerder()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from superbeheerders where auth_user_id = auth.uid()
  );
$$;

grant execute on function public.is_superbeheerder() to authenticated;

create policy superbeheerder_select_bedrijven on bedrijven for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_gebruikers on gebruikers for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_voertuigen on voertuigen for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_gebruiker_voertuigen on gebruiker_voertuigen for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_secties on inspectie_secties for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_punten on inspectie_punten for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_inspecties on inspecties for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_resultaten on inspectie_resultaten for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_voertuig_types on voertuig_types for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_inspectie_punt_types on inspectie_punt_types for select to authenticated
  using (public.is_superbeheerder());

-- Backfill: e-mailadres waarmee vandaag als beheerder wordt ingelogd in portaal.html.
insert into superbeheerders (auth_user_id)
select id from auth.users where email = 'peter@prevx.be'
on conflict do nothing;
