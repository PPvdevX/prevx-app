-- Fix: rpc_mijn_vergunningen gaf "column reference id is ambiguous".
--
-- De functie declareert een uitvoerkolom `id` (returns table), en in PL/pgSQL
-- gedraagt zo'n uitvoerkolom zich óók als variabele. De opzoeking van de
-- gebruiker begon met:
--
--   select bedrijf_id, rol into v_bedrijf_id, v_rol
--   from gebruikers where id = p_gebruiker_id and actief = true;
--
-- Die `id` zonder tabelvoorvoegsel kan zowel de kolom als de uitvoervariabele
-- zijn, en daar struikelt Postgres over. De fout zat er al sinds 0057, maar
-- kwam pas boven toen de vergunningenlijst voor het eerst geopend werd -- de
-- functie wordt immers pas uitgevoerd bij het aanroepen, niet bij het aanmaken.
--
-- Oplossing: de tabel een alias geven en elke kolom voorvoegen. Verder is de
-- functie ongewijzigd t.o.v. 0060.
--
-- Les voor volgende functies: geef in een `returns table` liever geen kolom de
-- naam van iets dat je in de body onvoorwaardelijk gebruikt, of voorzie élke
-- kolomverwijzing van een alias.

create or replace function public.rpc_mijn_vergunningen(p_gebruiker_id uuid)
returns table(
  id uuid, vergunningsnummer text, status text, werktype_id uuid, werktype_naam text,
  locatie_omschrijving text, aanvrager_naam text, geldig_van timestamptz,
  geldig_tot timestamptz, beslissing_toelichting text, ben_aanvrager boolean,
  ben_bewaker boolean, werk_beeindigd_op timestamptz,
  nazorg_2u_bevestigd_op timestamptz, nazorg_24u_bevestigd_op timestamptz,
  escalatie_vereist boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_rol text;
begin
  select ik.bedrijf_id, ik.rol into v_bedrijf_id, v_rol
  from gebruikers ik
  where ik.id = p_gebruiker_id and ik.actief = true;

  if v_bedrijf_id is null then
    return;
  end if;

  return query
    select v.id, v.vergunningsnummer, v.status, v.werktype_id, w.naam, v.locatie_omschrijving,
           g.naam, v.geldig_van, v.geldig_tot, v.beslissing_toelichting,
           (v.aanvrager_id = p_gebruiker_id),
           (v.bewaker_id = p_gebruiker_id),
           v.werk_beeindigd_op, v.nazorg_2u_bevestigd_op, v.nazorg_24u_bevestigd_op,
           v.escalatie_vereist
    from vuurvergunningen v
    join werktypes w on w.id = v.werktype_id
    join gebruikers g on g.id = v.aanvrager_id
    where v.bedrijf_id = v_bedrijf_id
      and (
        v.aanvrager_id = p_gebruiker_id
        or v.bewaker_id = p_gebruiker_id
        or (v_rol in ('leidinggevende','preventieadviseur','beheerder') and v.status = 'aangevraagd')
      )
      and v.status not in ('afgesloten','afgewezen','ingetrokken','verlopen_niet_opgestart')
    order by v.aangemaakt_op desc
    limit 50;
end;
$$;

grant execute on function public.rpc_mijn_vergunningen(uuid) to anon;
