-- Een aanvraag blijft liggen tot iemand toevallig gaat kijken. De aanvrager
-- krijgt sinds 0078 wel een melding zodra er beslist is, maar de goedkeurders
-- horen niets wanneer er iets op hen ligt te wachten.
--
-- Dat is de vervelendste kant van de twee: een chauffeur staat klaar om te
-- beginnen en wacht op iemand die niet weet dat er gewacht wordt.
--
-- De melding gaat naar iedereen bij dat bedrijf met een goedkeurende rol --
-- dezelfde rollen die rpc_vergunning_beslissen aanvaardt. Wie geen meldingen
-- aan heeft, krijgt niets; send-push logt dat en gaat door. Bewust geen keuze
-- van één ontvanger: wie er op dat moment beschikbaar is, weten wij niet.
--
-- Alles gebeurt na het wegschrijven van de vergunning en de antwoorden. Een
-- mislukte melding mag een aanvraag nooit tegenhouden -- de vergunning staat
-- dan gewoon in de lijst, precies zoals vandaag.

create or replace function public.rpc_vergunning_aanvragen(
  p_gebruiker_id uuid,
  p_werktype_id uuid,
  p_locatie text,
  p_uitvoerders text,
  p_geldig_van timestamptz,
  p_geldig_tot timestamptz,
  p_bewaker_id uuid,
  p_antwoorden jsonb
)
returns table(vergunning_id uuid, vergunningsnummer text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_id uuid;
  v_nummer text;
  r jsonb;
  v_ontbreekt int;
  v_blokkerend text;
  v_aanvrager text;
  v_werktype text;
  v_ontvanger uuid;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  if not exists (select 1 from werktypes where id = p_werktype_id and bedrijf_id = v_bedrijf_id and actief = true) then
    raise exception 'Onbekend werktype voor dit bedrijf';
  end if;

  if p_locatie is null or btrim(p_locatie) = '' then
    raise exception 'Geef een werkplek op';
  end if;

  if p_geldig_tot <= p_geldig_van then
    raise exception 'De einddatum moet na de startdatum liggen';
  end if;

  select string_agg(vr.vraagtekst, ' / ') into v_blokkerend
  from jsonb_array_elements(p_antwoorden) a
  join vergunning_vragen vr on vr.id = (a->>'vraag_id')::uuid
  where vr.blokkerend = true and (a->>'antwoord') = 'nok';

  if v_blokkerend is not null then
    raise exception 'Kan niet worden aangevraagd zolang dit niet in orde is: %', v_blokkerend;
  end if;

  select count(*) into v_ontbreekt
  from vergunning_vragen vr
  where vr.bedrijf_id = v_bedrijf_id
    and vr.actief = true
    and vr.fase = 'voor'
    and vr.verplicht = true
    and (
      not exists (select 1 from vergunning_vraag_werktypes w where w.vraag_id = vr.id)
      or exists (select 1 from vergunning_vraag_werktypes w where w.vraag_id = vr.id and w.werktype_id = p_werktype_id)
    )
    and not exists (
      select 1 from jsonb_array_elements(p_antwoorden) a
      where (a->>'vraag_id')::uuid = vr.id
        and coalesce(btrim(a->>'antwoord'), '') <> ''
    );

  if v_ontbreekt > 0 then
    raise exception 'Er zijn nog % verplichte vragen onbeantwoord', v_ontbreekt;
  end if;

  v_nummer := public.volgend_vergunningsnummer(v_bedrijf_id);

  insert into vuurvergunningen (
    bedrijf_id, vergunningsnummer, werktype_id, locatie_omschrijving, uitvoerders,
    aanvrager_id, bewaker_id, status, geldig_van, geldig_tot
  ) values (
    v_bedrijf_id, v_nummer, p_werktype_id, btrim(p_locatie), nullif(btrim(coalesce(p_uitvoerders,'')),''),
    p_gebruiker_id, p_bewaker_id, 'aangevraagd', p_geldig_van, p_geldig_tot
  )
  returning id into v_id;

  for r in select * from jsonb_array_elements(p_antwoorden)
  loop
    insert into vergunning_antwoorden (vergunning_id, vraag_id, fase, antwoord, motivering, foto_url, gebruiker_id)
    values (
      v_id,
      (r->>'vraag_id')::uuid,
      'voor',
      r->>'antwoord',
      nullif(btrim(coalesce(r->>'motivering','')),''),
      nullif(btrim(coalesce(r->>'foto_url','')),''),
      p_gebruiker_id
    );
  end loop;

  -- Naam en werktype erbij: op een vergrendeld scherm wil je kunnen zien of dit
  -- iets is waarvoor je meteen opstaat. De werkplek blijft er bewust af.
  select naam into v_aanvrager from gebruikers where id = p_gebruiker_id;
  select naam into v_werktype from werktypes where id = p_werktype_id;

  for v_ontvanger in
    select g.id from gebruikers g
    where g.bedrijf_id = v_bedrijf_id
      and g.actief = true
      and g.rol in ('leidinggevende','preventieadviseur','beheerder')
  loop
    perform net.http_post(
      url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', public.geheim('webhook_secret')
      ),
      body := jsonb_build_object(
        'gebruiker_id', v_ontvanger,
        'titel', 'Vuurvergunning ter goedkeuring',
        'tekst', v_nummer || ' - ' || coalesce(v_werktype,'heet werk') ||
                 ', aangevraagd door ' || coalesce(v_aanvrager,'een medewerker') || '.',
        'tag', 'vergunning-' || v_id
      ),
      timeout_milliseconds := 10000
    );
  end loop;

  return query select v_id, v_nummer;
end;
$$;

grant execute on function public.rpc_vergunning_aanvragen(uuid, uuid, text, text, timestamptz, timestamptz, uuid, jsonb) to anon;
grant execute on function public.rpc_vergunning_aanvragen(uuid, uuid, text, text, timestamptz, timestamptz, uuid, jsonb) to authenticated;
