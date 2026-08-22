-- De wegen waarlangs de app een LMRA afwerkt. Zoals alle driver-RPC's:
-- security definer, aanroepbaar door anon, en elk controleert zelf of de
-- gebruiker bestaat en bij welk bedrijf hij hoort.
--
-- Bewust TWEE aanroepen om een LMRA af te werken -- starten en afronden -- en
-- niet één. De duur is een van de weinige eerlijke signalen die we hebben over
-- of er echt gekeken is; die kan je alleen meten als de databank weet wanneer
-- het scherm openging. Zou de app zelf een duur meesturen, dan meet je wat de
-- app beweert in plaats van wat er gebeurd is.

insert into modules (key, naam, volgorde) values ('lmra', 'LMRA', 3)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- De risico's die deze klant gekozen heeft
-- ---------------------------------------------------------------------------
create or replace function public.rpc_lmra_risicos(p_gebruiker_id uuid)
returns table(id uuid, naam text, categorie text, toelichting text)
language sql
security definer
set search_path = public
as $$
  select r.id, r.naam, r.categorie, r.toelichting
  from lmra_risicos r
  join bedrijf_lmra_risicos b on b.risico_id = r.id
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true and g.bedrijf_id = b.bedrijf_id
  where r.actief = true
  order by r.volgorde, r.naam;
$$;

-- ---------------------------------------------------------------------------
-- Starten
-- ---------------------------------------------------------------------------
create or replace function public.rpc_lmra_start(
  p_gebruiker_id uuid,
  p_taak text,
  p_locatie text,
  p_voertuig_id uuid,
  p_soort text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_id uuid;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;
  if coalesce(btrim(p_taak),'') = '' or coalesce(btrim(p_locatie),'') = '' then
    raise exception 'Geef op wat je gaat doen en waar';
  end if;
  if coalesce(p_soort,'volledig') not in ('volledig','bevestiging') then
    raise exception 'Ongeldig soort';
  end if;

  insert into lmras (bedrijf_id, gebruiker_id, taak, locatie, voertuig_id, soort)
  values (v_bedrijf_id, p_gebruiker_id, btrim(p_taak), btrim(p_locatie), p_voertuig_id,
          coalesce(p_soort,'volledig'))
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Afronden
-- ---------------------------------------------------------------------------
-- De eigen vaststelling of een foto is verplicht bij een volledige LMRA. Dat is
-- het enige wat afvinken echt tegenhoudt: een foto van een werkplek kan je niet
-- maken waar je niet staat, en een eigen zin moet je zelf bedenken.
create or replace function public.rpc_lmra_afronden(
  p_lmra_id uuid,
  p_gebruiker_id uuid,
  p_eigen_vaststelling text,
  p_foto_url text,
  p_antwoorden jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_soort text;
  r jsonb;
begin
  select soort into v_soort
  from lmras
  where id = p_lmra_id and gebruiker_id = p_gebruiker_id and afgerond_op is null and status = 'veilig';

  if v_soort is null then
    raise exception 'Deze LMRA is niet (meer) af te ronden';
  end if;

  if v_soort = 'volledig'
     and coalesce(btrim(p_eigen_vaststelling),'') = ''
     and coalesce(btrim(p_foto_url),'') = '' then
    raise exception 'Voeg een eigen vaststelling of een foto van de werkplek toe';
  end if;

  for r in select * from jsonb_array_elements(coalesce(p_antwoorden,'[]'::jsonb))
  loop
    insert into lmra_risico_antwoorden (lmra_id, risico_id, in_orde, opmerking)
    values (
      p_lmra_id,
      (r->>'risico_id')::uuid,
      coalesce((r->>'in_orde')::boolean, true),
      nullif(btrim(coalesce(r->>'opmerking','')),'')
    );
  end loop;

  update lmras set
    eigen_vaststelling = nullif(btrim(coalesce(p_eigen_vaststelling,'')),''),
    foto_url = nullif(btrim(coalesce(p_foto_url,'')),''),
    afgerond_op = now()
  where id = p_lmra_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Stoppen
-- ---------------------------------------------------------------------------
-- Het hart van de module. Maakt een melding aan en waarschuwt de leidinggevenden,
-- zodat stoppen gevolg heeft in plaats van een knop te zijn die niets doet.
create or replace function public.rpc_lmra_stoppen(
  p_lmra_id uuid,
  p_gebruiker_id uuid,
  p_reden text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_naam text;
  v_taak text;
  v_locatie text;
  v_ontvanger uuid;
begin
  if coalesce(btrim(p_reden),'') = '' then
    raise exception 'Zeg waarom je stopt; zonder reden kan niemand er iets aan doen';
  end if;

  update lmras set
    status = 'gestopt',
    stop_reden = btrim(p_reden),
    afgerond_op = coalesce(afgerond_op, now())
  where id = p_lmra_id and gebruiker_id = p_gebruiker_id and status = 'veilig'
  returning bedrijf_id, taak, locatie into v_bedrijf_id, v_taak, v_locatie;

  if v_bedrijf_id is null then
    raise exception 'Deze LMRA is niet (meer) te stoppen';
  end if;

  select naam into v_naam from gebruikers where id = p_gebruiker_id;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam)
  values (v_bedrijf_id, 'werk_gestopt',
          'Werk gestopt bij LMRA. Taak: ' || v_taak || '. Plek: ' || v_locatie ||
          '. Reden: ' || btrim(p_reden),
          v_naam);

  for v_ontvanger in
    select g.id from gebruikers g
    where g.bedrijf_id = v_bedrijf_id and g.actief = true
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
        'titel', 'Werk gestopt',
        -- Wie en waar wel, de reden niet: dit verschijnt op een vergrendeld
        -- scherm en de reden kan gevoelig liggen. Wie het moet weten, opent de app.
        'tekst', coalesce(v_naam,'Een medewerker') || ' is gestopt bij ' || v_locatie || '.',
        'tag', 'lmra-' || p_lmra_id
      ),
      timeout_milliseconds := 10000
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Hervatten
-- ---------------------------------------------------------------------------
-- Wie stopt mag zelf hervatten -- geen vrijgave door een leidinggevende. Elke
-- drempel op stoppen is een reden om niet te stoppen, en een procedure die het
-- gedrag onderdrukt dat ze moet aanmoedigen is erger dan geen procedure. Wat we
-- wel vragen is wat er veranderd is; dat kost vijf seconden en levert een
-- eerlijker spoor dan een vrijgave die iemand van op afstand aanklikt.
create or replace function public.rpc_lmra_hervatten(
  p_lmra_id uuid,
  p_gebruiker_id uuid,
  p_reden text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(btrim(p_reden),'') = '' then
    raise exception 'Zeg wat er veranderd is voor je hervat';
  end if;

  update lmras set
    hervat_op = now(),
    hervat_reden = btrim(p_reden)
  where id = p_lmra_id and gebruiker_id = p_gebruiker_id
    and status = 'gestopt' and hervat_op is null;

  if not found then
    raise exception 'Deze LMRA staat niet gestopt';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Wat collega's hier vandaag vastgesteld hebben
-- ---------------------------------------------------------------------------
-- Hierdoor bouwen zes LMRA's voor hetzelfde werk op elkaar voort in plaats van
-- zes kopieën te zijn. Alleen van vandaag en alleen op dezelfde plek: ouder of
-- elders is ruis, en ruis leert mensen wegkijken.
create or replace function public.rpc_lmra_recent(p_gebruiker_id uuid, p_locatie text)
returns table(wie text, wanneer timestamptz, vaststelling text, gestopt boolean)
language sql
security definer
set search_path = public
as $$
  select g.naam, l.gestart_op,
         coalesce(nullif(btrim(coalesce(l.eigen_vaststelling,'')),''), l.stop_reden),
         l.status = 'gestopt'
  from lmras l
  join gebruikers g on g.id = l.gebruiker_id
  join gebruikers ik on ik.id = p_gebruiker_id and ik.actief = true and ik.bedrijf_id = l.bedrijf_id
  where lower(btrim(l.locatie)) = lower(btrim(coalesce(p_locatie,'')))
    and l.gestart_op::date = current_date
    and l.gebruiker_id <> p_gebruiker_id
    and (coalesce(btrim(l.eigen_vaststelling),'') <> '' or l.status = 'gestopt')
  order by l.gestart_op desc
  limit 5;
$$;

-- ---------------------------------------------------------------------------
-- Wat deed ik vandaag al?
-- ---------------------------------------------------------------------------
-- Bepaalt of een korte bevestiging volstaat: dezelfde persoon, dezelfde taak,
-- dezelfde plek, vandaag, en niet gestopt.
create or replace function public.rpc_lmra_vandaag(p_gebruiker_id uuid)
returns table(taak text, locatie text, laatste timestamptz)
language sql
security definer
set search_path = public
as $$
  select l.taak, l.locatie, max(l.gestart_op)
  from lmras l
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true and g.bedrijf_id = l.bedrijf_id
  where l.gebruiker_id = p_gebruiker_id
    and l.gestart_op::date = current_date
    and l.status = 'veilig'
    and l.afgerond_op is not null
  group by l.taak, l.locatie
  order by max(l.gestart_op) desc
  limit 5;
$$;

-- ---------------------------------------------------------------------------
-- Rechten: enkel wat de app nodig heeft
-- ---------------------------------------------------------------------------
grant execute on function public.rpc_lmra_risicos(uuid) to anon, authenticated;
grant execute on function public.rpc_lmra_start(uuid, text, text, uuid, text) to anon, authenticated;
grant execute on function public.rpc_lmra_afronden(uuid, uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.rpc_lmra_stoppen(uuid, uuid, text) to anon, authenticated;
grant execute on function public.rpc_lmra_hervatten(uuid, uuid, text) to anon, authenticated;
grant execute on function public.rpc_lmra_recent(uuid, text) to anon, authenticated;
grant execute on function public.rpc_lmra_vandaag(uuid) to anon, authenticated;
