-- Aanvulling op 0057. Bij het bouwen van het aanvraagformulier bleek er nog
-- één ding te ontbreken: de aanvrager moet een brandwacht kunnen aanduiden, en
-- daarvoor heeft de app een lijst van collega's nodig.
--
-- Bewust geen bestaande gebruikerslijst hergebruikt: de chauffeurs-app heeft
-- geen Supabase Auth-sessie en mag de gebruikers-tabel niet rechtstreeks lezen
-- (zie 0002). Deze functie geeft enkel naam en id terug van actieve collega's
-- binnen hetzelfde bedrijf -- geen pincodes, geen e-mailadressen.

create or replace function public.rpc_collegas(p_gebruiker_id uuid)
returns table(id uuid, naam text, rol text)
language sql
security definer
set search_path = public
as $$
  select c.id, c.naam, c.rol
  from gebruikers c
  join gebruikers ik on ik.id = p_gebruiker_id and ik.actief = true and ik.bedrijf_id = c.bedrijf_id
  where c.actief = true
  order by c.naam;
$$;

grant execute on function public.rpc_collegas(uuid) to anon;
