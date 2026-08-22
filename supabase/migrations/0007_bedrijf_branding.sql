-- Huisstijl per bedrijf: logo en hoofdkleuren instelbaar maken vanuit het portaal.
-- Achtergrondkleur is bewust NIET per bedrijf (dat is een algemene app-instelling,
-- zie de --bg CSS-variabele in index.html/portaal.html).

alter table bedrijven
  add column if not exists logo_url text,
  add column if not exists kleur_primair text not null default '#003366',
  add column if not exists kleur_accent text not null default '#40668C';

create policy portal_update_bedrijven on bedrijven for update to authenticated
  using (id = public.huidig_bedrijf_id())
  with check (id = public.huidig_bedrijf_id());

-- Returntype van rpc_login_chauffeur breidt uit (logo/kleuren erbij), dat vereist
-- een drop+create in Postgres (create or replace mag het returntype niet wijzigen).
drop function if exists public.rpc_login_chauffeur(text);

create function public.rpc_login_chauffeur(p_pincode text)
returns table(
  id uuid, naam text, rol text, bedrijf_id uuid,
  logo_url text, kleur_primair text, kleur_accent text
)
language sql
security definer
set search_path = public
as $$
  select g.id, g.naam, g.rol, g.bedrijf_id, b.logo_url, b.kleur_primair, b.kleur_accent
  from gebruikers g
  join bedrijven b on b.id = g.bedrijf_id
  where g.pincode = p_pincode and g.actief = true
  limit 1;
$$;

grant execute on function public.rpc_login_chauffeur(text) to anon;
