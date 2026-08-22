-- Dezelfde blinde vlek als bij de LMRA (0084), nu voor de andere twee modules:
-- een leidinggevende ziet in de app niet wat zijn mensen doen.
--
-- Bij de VUURVERGUNNING ziet hij vandaag wél wat op zijn handtekening wacht,
-- maar niet wat er lóópt. Terwijl dat het gevaarlijkste is wat er op dat moment
-- op zijn terrein gebeurt: actief heet werk, en straks een nazorgcontrole die
-- iemand moet uitvoeren. Een vergunning die in escalatie gaat, ziet hij enkel
-- als hij toevallig de mail leest.
--
-- Bij de PRE-INSPECTIE ziet hij alle assets, maar nergens welke inspecties er
-- uitgevoerd zijn. Een chauffeur meldt 's morgens een voertuig als niet
-- rijklaar, dat komt netjes in het portaal terecht, en de man die er ter plaatse
-- iets aan kan doen weet van niets tot de adviseur belt. Dat is het gat dat het
-- meest kost.
--
-- Beide functies hebben dezelfde rolvoorwaarde als goedkeuren: leidinggevende,
-- preventieadviseur of beheerder. En beide tonen bewust een korte lijst -- wat
-- aandacht vraagt, niet een archief. Geschiedenis staat in het portaal.

-- ---------------------------------------------------------------------------
-- Vuurvergunningen die aandacht vragen
-- ---------------------------------------------------------------------------
-- Niet "vandaag" maar "nog niet afgesloten": een vergunning van gisteren waarvan
-- de nazorg nog loopt, is vandaag nog altijd zijn zorg.
create or replace function public.rpc_vergunning_overzicht(p_gebruiker_id uuid)
returns table(
  id uuid,
  vergunningsnummer text,
  werktype text,
  locatie text,
  aanvrager text,
  status text,
  geldig_tot timestamptz,
  werk_beeindigd_op timestamptz,
  nazorg_2u_ok boolean,
  nazorg_24u_ok boolean,
  escalatie boolean
)
language sql
security definer
set search_path = public
as $$
  select v.id, v.vergunningsnummer, w.naam, v.locatie_omschrijving, g.naam, v.status,
         v.geldig_tot, v.werk_beeindigd_op,
         v.nazorg_2u_bevestigd_op is not null,
         v.nazorg_24u_bevestigd_op is not null,
         coalesce(v.escalatie_vereist, false)
  from vuurvergunningen v
  join werktypes w on w.id = v.werktype_id
  join gebruikers g on g.id = v.aanvrager_id
  join gebruikers ik
    on ik.id = p_gebruiker_id
   and ik.actief = true
   and ik.bedrijf_id = v.bedrijf_id
   and ik.rol in ('leidinggevende','preventieadviseur','beheerder')
  where v.status in ('aangevraagd','voorbehoud','actief')
  -- Escalatie eerst, dan wat op een handtekening wacht, dan de rest.
  order by coalesce(v.escalatie_vereist,false) desc,
           (v.status = 'aangevraagd') desc,
           v.geldig_van desc
  limit 30;
$$;

-- ---------------------------------------------------------------------------
-- Inspecties van vandaag
-- ---------------------------------------------------------------------------
create or replace function public.rpc_inspectie_overzicht(p_gebruiker_id uuid)
returns table(
  id uuid,
  wie text,
  asset text,
  omschrijving text,
  verdict text,
  tijdstip time
)
language sql
security definer
set search_path = public
as $$
  select i.id, g.naam, vt.nummerplaat, vt.omschrijving, i.verdict, i.tijdstip
  from inspecties i
  join gebruikers g on g.id = i.gebruiker_id
  join voertuigen vt on vt.id = i.voertuig_id
  join gebruikers ik
    on ik.id = p_gebruiker_id
   and ik.actief = true
   and ik.bedrijf_id = i.bedrijf_id
   and ik.rol in ('leidinggevende','preventieadviseur','beheerder')
  where i.datum = current_date
  -- Niet rijklaar bovenaan: daar moet iemand nu iets mee.
  order by (i.verdict = 'niet_rijklaar') desc,
           (i.verdict = 'rijklaar_met_opmerkingen') desc,
           i.tijdstip desc
  limit 50;
$$;

grant execute on function public.rpc_vergunning_overzicht(uuid) to anon, authenticated;
grant execute on function public.rpc_inspectie_overzicht(uuid) to anon, authenticated;
