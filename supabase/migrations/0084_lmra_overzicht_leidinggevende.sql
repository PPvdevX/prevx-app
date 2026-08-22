-- Een leidinggevende zag in de app niets van wat zijn mensen vaststelden.
--
-- De gegevens bestonden wel, maar alleen in het portaal -- en dat is precies de
-- plaats waar een leidinggevende op een werf niet komt. Hij kreeg dus wel een
-- pushmelding wanneer iemand stopte, maar de gewone vaststellingen ("vloer is
-- nat bij de ingang") bereikten hem nergens. Dat is de helft van de waarde van
-- de module: niet elke opmerking is een stop, maar samen tekenen ze wel het
-- beeld van de werkdag.
--
-- Deze functie geeft dat beeld, met dezelfde rolvoorwaarde als goedkeuren en
-- pincodeherstel: leidinggevende, preventieadviseur of beheerder. Een chauffeur
-- krijgt niets -- die ziet al wat er op zijn eigen werkplek gemeld is via
-- rpc_lmra_recent, en dat is wat hij nodig heeft om veilig te starten.
--
-- Bewust alleen VANDAAG. Een leidinggevende hoort te kijken naar wat er nu
-- speelt; geschiedenis staat in het portaal. Zou dit een lange lijst worden,
-- dan wordt ze niet meer gelezen en verliest de stop zijn opvallendheid.

create or replace function public.rpc_lmra_overzicht(p_gebruiker_id uuid)
returns table(
  id uuid,
  wie text,
  taak text,
  locatie text,
  soort text,
  status text,
  vaststelling text,
  stop_reden text,
  hervat_op timestamptz,
  gestart_op timestamptz,
  seconden int
)
language sql
security definer
set search_path = public
as $$
  select l.id, g.naam, l.taak, l.locatie, l.soort, l.status,
         nullif(btrim(coalesce(l.eigen_vaststelling,'')),''),
         l.stop_reden,
         l.hervat_op,
         l.gestart_op,
         case when l.afgerond_op is null then null
              else extract(epoch from (l.afgerond_op - l.gestart_op))::int end
  from lmras l
  join gebruikers g on g.id = l.gebruiker_id
  join gebruikers ik
    on ik.id = p_gebruiker_id
   and ik.actief = true
   and ik.bedrijf_id = l.bedrijf_id
   and ik.rol in ('leidinggevende','preventieadviseur','beheerder')
  where l.gestart_op::date = current_date
  -- Gestopt werk eerst: dat is waar iemand nu iets aan moet doen.
  order by (l.status = 'gestopt' and l.hervat_op is null) desc, l.gestart_op desc
  limit 50;
$$;

grant execute on function public.rpc_lmra_overzicht(uuid) to anon, authenticated;
