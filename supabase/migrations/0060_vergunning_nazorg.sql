-- Fase C: de TIJDENS- en NA-fase van de vuurvergunning, met de nazorgbewaking.
--
-- De kern van dit hele instrument zit hier. Nagloeiend materiaal is een van de
-- belangrijkste oorzaken van uitgestelde brand na heet werk; een vergunning
-- waarvan de nazorg niet bevestigd wordt, mag daarom NOOIT stilzwijgend
-- verdwijnen. Ze blijft 'actief' staan met een vlag, en verschijnt in de
-- openstaande-actielijst tot iemand ze afsluit.
--
-- Vereist pg_cron (Database -> Extensions) voor de geplande controle onderaan.

alter table vuurvergunningen
  add column if not exists werk_beeindigd_op timestamptz,
  add column if not exists nazorg_2u_bevestigd_op timestamptz,
  add column if not exists nazorg_2u_door_id uuid references gebruikers(id),
  add column if not exists nazorg_24u_bevestigd_op timestamptz,
  add column if not exists nazorg_24u_door_id uuid references gebruikers(id);

create table if not exists vergunning_herinneringen (
  id uuid primary key default gen_random_uuid(),
  vergunning_id uuid not null references vuurvergunningen(id) on delete cascade,
  type text not null check (type in ('controle_2u','controle_24u')),
  gepland_op timestamptz not null,
  verstuurd_op timestamptz,
  ontvanger_id uuid references gebruikers(id),
  -- Tweede verzending naar de verantwoordelijke wanneer de eerste onbeantwoord
  -- blijft. Zie de marge in verwerk_nazorg_herinneringen() hieronder.
  geescaleerd_op timestamptz,
  unique (vergunning_id, type)
);

create index if not exists idx_herinneringen_gepland
  on vergunning_herinneringen (gepland_op) where verstuurd_op is null;

alter table vergunning_herinneringen enable row level security;

create policy portal_select_herinneringen on vergunning_herinneringen for select to authenticated
  using (exists (
    select 1 from vuurvergunningen v
    where v.id = vergunning_herinneringen.vergunning_id
      and (v.bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder())
  ));

-- ---------------------------------------------------------------------------
-- Registratie tijdens de werken
-- ---------------------------------------------------------------------------
-- Mag meermaals: een bewakingsagent registreert per controleronde.
create or replace function public.rpc_vergunning_tijdens_registreren(
  p_vergunning_id uuid, p_gebruiker_id uuid, p_antwoorden jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  r jsonb;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  if not exists (select 1 from vuurvergunningen
                 where id = p_vergunning_id and bedrijf_id = v_bedrijf_id and status = 'actief') then
    raise exception 'Deze vergunning is niet actief; er kan niets geregistreerd worden';
  end if;

  for r in select * from jsonb_array_elements(p_antwoorden)
  loop
    insert into vergunning_antwoorden (vergunning_id, vraag_id, fase, antwoord, motivering, foto_url, gebruiker_id)
    values (
      p_vergunning_id, (r->>'vraag_id')::uuid, 'tijdens',
      r->>'antwoord',
      nullif(btrim(coalesce(r->>'motivering','')),''),
      nullif(btrim(coalesce(r->>'foto_url','')),''),
      p_gebruiker_id
    );
  end loop;

  return true;
end;
$$;

grant execute on function public.rpc_vergunning_tijdens_registreren(uuid, uuid, jsonb) to anon;

-- ---------------------------------------------------------------------------
-- Werk beëindigen: NA-checklist invullen en de nazorgklok starten
-- ---------------------------------------------------------------------------
-- Zet de vergunning NIET op afgesloten. Dat gebeurt pas als beide
-- nazorgcontroles bevestigd zijn -- anders zou het afvinken van een formulier
-- de controle vervangen die het net moet afdwingen.
create or replace function public.rpc_vergunning_werk_beeindigen(
  p_vergunning_id uuid, p_gebruiker_id uuid, p_antwoorden jsonb, p_handtekening text
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_nu timestamptz := now();
  v_ontvanger uuid;
  r jsonb;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  if not exists (select 1 from vuurvergunningen
                 where id = p_vergunning_id and bedrijf_id = v_bedrijf_id and status = 'actief') then
    raise exception 'Deze vergunning is niet actief';
  end if;

  if exists (select 1 from vuurvergunningen where id = p_vergunning_id and werk_beeindigd_op is not null) then
    raise exception 'Het werk is al als beëindigd geregistreerd';
  end if;

  for r in select * from jsonb_array_elements(p_antwoorden)
  loop
    insert into vergunning_antwoorden (vergunning_id, vraag_id, fase, antwoord, motivering, foto_url, gebruiker_id)
    values (
      p_vergunning_id, (r->>'vraag_id')::uuid, 'na',
      r->>'antwoord',
      nullif(btrim(coalesce(r->>'motivering','')),''),
      nullif(btrim(coalesce(r->>'foto_url','')),''),
      p_gebruiker_id
    );
  end loop;

  update vuurvergunningen set
    werk_beeindigd_op = v_nu,
    handtekening = coalesce(p_handtekening, handtekening)
  where id = p_vergunning_id;

  -- De brandwacht doet de controle; staat er geen, dan valt het terug op wie
  -- het werk beëindigde.
  select coalesce(bewaker_id, p_gebruiker_id) into v_ontvanger
  from vuurvergunningen where id = p_vergunning_id;

  insert into vergunning_herinneringen (vergunning_id, type, gepland_op, ontvanger_id)
  values
    (p_vergunning_id, 'controle_2u',  v_nu + interval '2 hours',  v_ontvanger),
    (p_vergunning_id, 'controle_24u', v_nu + interval '24 hours', v_ontvanger)
  on conflict (vergunning_id, type) do nothing;

  return v_nu;
end;
$$;

grant execute on function public.rpc_vergunning_werk_beeindigen(uuid, uuid, jsonb, text) to anon;

-- ---------------------------------------------------------------------------
-- Nazorgcontrole bevestigen
-- ---------------------------------------------------------------------------
create or replace function public.rpc_nazorg_bevestigen(
  p_vergunning_id uuid, p_gebruiker_id uuid, p_type text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_v record;
begin
  if p_type not in ('controle_2u','controle_24u') then
    raise exception 'Onbekend type nazorgcontrole';
  end if;

  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  select * into v_v from vuurvergunningen
  where id = p_vergunning_id and bedrijf_id = v_bedrijf_id;
  if v_v.id is null then
    raise exception 'Onbekende vergunning';
  end if;
  if v_v.werk_beeindigd_op is null then
    raise exception 'Het werk is nog niet als beëindigd geregistreerd';
  end if;

  if p_type = 'controle_2u' then
    update vuurvergunningen set nazorg_2u_bevestigd_op = now(), nazorg_2u_door_id = p_gebruiker_id
    where id = p_vergunning_id and nazorg_2u_bevestigd_op is null;
  else
    -- De 24-uurscontrole kan pas nadat de eerste gebeurd is; anders zou iemand
    -- beide in één keer afvinken en is de tussentijdse controle papier.
    if v_v.nazorg_2u_bevestigd_op is null then
      raise exception 'Bevestig eerst de controle na 2 uur';
    end if;
    update vuurvergunningen set nazorg_24u_bevestigd_op = now(), nazorg_24u_door_id = p_gebruiker_id
    where id = p_vergunning_id and nazorg_24u_bevestigd_op is null;
  end if;

  update vergunning_herinneringen set verstuurd_op = coalesce(verstuurd_op, now())
  where vergunning_id = p_vergunning_id and type = p_type;

  -- Beide bevestigd: pas nu is het dossier voldaan en onwijzigbaar.
  update vuurvergunningen set
    status = 'afgesloten',
    afgesloten_op = now(),
    afgesloten_door_id = p_gebruiker_id,
    escalatie_vereist = false,
    escalatie_sinds = null
  where id = p_vergunning_id
    and nazorg_2u_bevestigd_op is not null
    and nazorg_24u_bevestigd_op is not null
    and status = 'actief';

  select status into v_v.status from vuurvergunningen where id = p_vergunning_id;
  return v_v.status;
end;
$$;

grant execute on function public.rpc_nazorg_bevestigen(uuid, uuid, text) to anon;

-- ---------------------------------------------------------------------------
-- Geplande controle
-- ---------------------------------------------------------------------------
-- Draait elk kwartier. Verstuurt herinneringen die vervallen zijn, en zet na
-- een marge de escalatievlag. Een vergunning gaat hier NOOIT automatisch naar
-- een eindstatus: het uitblijven van een bevestiging is precies het signaal dat
-- iemand moet oppikken, niet iets om op te ruimen.
create or replace function public.verwerk_nazorg_herinneringen()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  h record;
begin
  -- Vervallen herinneringen versturen.
  for h in
    select r.*, v.bedrijf_id
    from vergunning_herinneringen r
    join vuurvergunningen v on v.id = r.vergunning_id
    where r.verstuurd_op is null
      and r.gepland_op <= now()
      and v.status = 'actief'
  loop
    perform net.http_post(
      url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-nazorg-herinnering',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', public.geheim('webhook_secret')
      ),
      body := jsonb_build_object(
        'vergunning_id', h.vergunning_id,
        'type', h.type,
        'ontvanger_id', h.ontvanger_id,
        'escalatie', false
      ),
      timeout_milliseconds := 10000
    );

    update vergunning_herinneringen set verstuurd_op = now() where id = h.id;
  end loop;

  -- Blijft de 2-uurscontrole een half uur na de herinnering onbevestigd, dan
  -- gaat er een bericht naar de verantwoordelijke. Eén keer, niet elk kwartier.
  for h in
    select r.*, v.bedrijf_id
    from vergunning_herinneringen r
    join vuurvergunningen v on v.id = r.vergunning_id
    where r.type = 'controle_2u'
      and r.verstuurd_op is not null
      and r.geescaleerd_op is null
      and r.verstuurd_op < now() - interval '30 minutes'
      and v.nazorg_2u_bevestigd_op is null
      and v.status = 'actief'
  loop
    perform net.http_post(
      url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-nazorg-herinnering',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', public.geheim('webhook_secret')
      ),
      body := jsonb_build_object(
        'vergunning_id', h.vergunning_id,
        'type', h.type,
        'ontvanger_id', h.ontvanger_id,
        'escalatie', true
      ),
      timeout_milliseconds := 10000
    );

    update vergunning_herinneringen set geescaleerd_op = now() where id = h.id;
  end loop;

  -- Vlag zetten op alles waarvan een termijn ruim verstreken is zonder
  -- bevestiging. Die vlag voedt de openstaande-actielijst in het portaal.
  update vuurvergunningen v set
    escalatie_vereist = true,
    escalatie_sinds = coalesce(escalatie_sinds, now())
  where v.status = 'actief'
    and v.werk_beeindigd_op is not null
    and v.escalatie_vereist = false
    and (
      (v.nazorg_2u_bevestigd_op is null and v.werk_beeindigd_op < now() - interval '3 hours')
      or (v.nazorg_24u_bevestigd_op is null and v.werk_beeindigd_op < now() - interval '26 hours')
    );
end;
$$;

revoke execute on function public.verwerk_nazorg_herinneringen() from public;

-- Elk kwartier. Fijner heeft geen zin: de marges hierboven zijn uren, en elke
-- draai is een paar query's op een kleine tabel.
select cron.schedule(
  'nazorg-herinneringen',
  '*/15 * * * *',
  $$select public.verwerk_nazorg_herinneringen();$$
);

-- ---------------------------------------------------------------------------
-- Lijst voor de app uitbreiden met de nazorgstand
-- ---------------------------------------------------------------------------
-- De app moet kunnen tonen welke stap aan de beurt is (tussentijdse controle,
-- werk beëindigen, 2u bevestigen, 24u bevestigen). Returntype wijzigt, dus
-- eerst droppen -- create or replace laat dat niet toe.
drop function if exists public.rpc_mijn_vergunningen(uuid);

create function public.rpc_mijn_vergunningen(p_gebruiker_id uuid)
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
  select bedrijf_id, rol into v_bedrijf_id, v_rol
  from gebruikers where id = p_gebruiker_id and actief = true;
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
