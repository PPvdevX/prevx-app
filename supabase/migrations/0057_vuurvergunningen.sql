-- Fase B van de vuurvergunning: de vergunningen zelf. Aanvraag, nummering en
-- goedkeuring. De TIJDENS- en NA-fase met de nazorgtimers volgen in fase C.
--
-- Bouwt voort op 0050 (werktypes, vragenlijst) en gebruikt dezelfde
-- security definer-opzet als de andere chauffeurs-RPC's: de app heeft geen
-- Supabase Auth-sessie, dus de pincode is het identiteitsbewijs en alle
-- schrijfacties lopen via functies, nooit rechtstreeks op de tabellen.

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------
create table if not exists vuurvergunningen (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  vergunningsnummer text not null unique,
  werktype_id uuid not null references werktypes(id),
  locatie_omschrijving text not null,
  uitvoerders text,
  aanvrager_id uuid not null references gebruikers(id),
  bewaker_id uuid references gebruikers(id),

  status text not null default 'aangevraagd' check (status in
    ('aangevraagd','afgewezen','voorbehoud','actief','afgesloten','verlopen_niet_opgestart','ingetrokken')),

  geldig_van timestamptz not null,
  geldig_tot timestamptz not null,

  -- Beslissing van de goedkeurder
  goedgekeurd_door_id uuid references gebruikers(id),
  goedgekeurd_op timestamptz,
  beslissing_toelichting text,
  handtekening text,
  -- Legt vast HOE er getekend is. Belandt dit dossier ooit bij een verzekeraar,
  -- dan staat er zwart op wit hoe hard die handtekening is -- je wil niet dat
  -- het meer zekerheid suggereert dan het waarmaakt.
  handtekening_methode text check (handtekening_methode in ('pincode','pincode_emailcode','portaal_login')),

  -- Bij voorbehoud: de aanvrager moet de voorwaarden eerst aanvaarden. Een
  -- voorwaarde die niemand hoeft af te vinken, is geen voorwaarde.
  voorwaarden_bevestigd_op timestamptz,
  voorwaarden_bevestigd_door_id uuid references gebruikers(id),

  afgesloten_door_id uuid references gebruikers(id),
  afgesloten_op timestamptz,
  escalatie_vereist boolean not null default false,
  escalatie_sinds timestamptz,

  ingetrokken_door_id uuid references gebruikers(id),
  ingetrokken_op timestamptz,
  ingetrokken_reden text,
  vroegtijdig_beeindigd boolean not null default false,

  aangemaakt_op timestamptz not null default now(),

  -- Zonder toelichting weet de aanvrager niet wat hij moet aanpassen, en bij
  -- voorbehoud zijn er domweg geen voorwaarden. Afdwingen in de databank, niet
  -- enkel in de interface.
  constraint toelichting_verplicht_bij_beslissing check (
    status not in ('afgewezen','voorbehoud')
    or (beslissing_toelichting is not null and btrim(beslissing_toelichting) <> '')
  )
);

create index if not exists idx_vuurvergunningen_bedrijf on vuurvergunningen (bedrijf_id, status);
create index if not exists idx_vuurvergunningen_aanvrager on vuurvergunningen (aanvrager_id);

create table if not exists vergunning_antwoorden (
  id uuid primary key default gen_random_uuid(),
  vergunning_id uuid not null references vuurvergunningen(id) on delete cascade,
  vraag_id uuid not null references vergunning_vragen(id),
  fase text not null check (fase in ('voor','tijdens','na')),
  antwoord text,
  motivering text,
  foto_url text,
  tijdstip timestamptz not null default now(),
  gebruiker_id uuid references gebruikers(id),

  -- 'afwijking' betekent: het klopt niet, maar we doen het toch, om deze reden.
  -- Zonder die reden is het gewoon een NOK zonder spoor.
  constraint motivering_verplicht_bij_afwijking check (
    antwoord is distinct from 'afwijking'
    or (motivering is not null and btrim(motivering) <> '')
  )
);

create index if not exists idx_vergunning_antwoorden_vergunning on vergunning_antwoorden (vergunning_id, fase);

-- Volgnummer per klant per jaar. De atomische upsert hieronder verhoogt en
-- levert in één bewerking, zodat twee gelijktijdige aanvragen nooit hetzelfde
-- nummer krijgen.
create table if not exists vergunning_nummers (
  bedrijf_id uuid not null references bedrijven(id),
  jaar int not null,
  laatste_nummer int not null default 0,
  primary key (bedrijf_id, jaar)
);

-- Eenmalige codes voor de goedkeuringshandtekening. RLS aan, bewust geen
-- policies: enkel de security definer-functies hieronder raken deze tabel aan
-- (zelfde patroon als pincode_reset_codes in 0038).
create table if not exists vergunning_goedkeuring_codes (
  id uuid primary key default gen_random_uuid(),
  vergunning_id uuid not null references vuurvergunningen(id) on delete cascade,
  gebruiker_id uuid not null references gebruikers(id),
  code text not null,
  aangemaakt_op timestamptz not null default now(),
  verloopt_op timestamptz not null,
  gebruikt boolean not null default false
);

alter table vuurvergunningen enable row level security;
alter table vergunning_antwoorden enable row level security;
alter table vergunning_nummers enable row level security;
alter table vergunning_goedkeuring_codes enable row level security;

-- Het portaal leest mee; schrijven gebeurt uitsluitend via de RPC's hieronder.
create policy portal_select_vuurvergunningen on vuurvergunningen for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy portal_select_vergunning_antwoorden on vergunning_antwoorden for select to authenticated
  using (exists (
    select 1 from vuurvergunningen v
    where v.id = vergunning_antwoorden.vergunning_id
      and (v.bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder())
  ));

-- ---------------------------------------------------------------------------
-- Onwijzigbaarheid van een afgesloten dossier
-- ---------------------------------------------------------------------------
-- De RPC's zijn security definer en omzeilen RLS, dus een policy volstaat hier
-- niet. Een trigger geldt voor iedereen, ook voor mezelf in een latere functie
-- die dit vergeet. Een bewijsdossier dat je achteraf stil kan bijwerken is geen
-- bewijs.
create or replace function public.blokkeer_wijziging_afgesloten_vergunning()
returns trigger
language plpgsql
as $$
begin
  if old.status = 'afgesloten' then
    raise exception 'Deze vergunning is afgesloten en kan niet meer gewijzigd worden (nummer %)', old.vergunningsnummer;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_vergunning_onwijzigbaar on vuurvergunningen;
create trigger trg_vergunning_onwijzigbaar
  before update on vuurvergunningen
  for each row execute function public.blokkeer_wijziging_afgesloten_vergunning();

create or replace function public.blokkeer_antwoord_afgesloten_vergunning()
returns trigger
language plpgsql
as $$
declare
  v_status text;
begin
  select status into v_status from vuurvergunningen
  where id = coalesce(new.vergunning_id, old.vergunning_id);
  if v_status = 'afgesloten' then
    raise exception 'De vergunning is afgesloten; antwoorden kunnen niet meer wijzigen';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_antwoord_onwijzigbaar on vergunning_antwoorden;
create trigger trg_antwoord_onwijzigbaar
  before insert or update or delete on vergunning_antwoorden
  for each row execute function public.blokkeer_antwoord_afgesloten_vergunning();

-- ---------------------------------------------------------------------------
-- Vergunningsnummer
-- ---------------------------------------------------------------------------
-- Formaat: KLANTCODE-JAAR-VOLGNUMMER, bv. K7M2QP-2026-0001. Het nummer wordt
-- toegekend bij de AANVRAAG, niet bij de goedkeuring, zodat ook een geweigerde
-- of verlopen aanvraag traceerbaar blijft.
create or replace function public.volgend_vergunningsnummer(p_bedrijf_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jaar int := extract(year from now())::int;
  v_nummer int;
  v_klantcode text;
begin
  insert into vergunning_nummers (bedrijf_id, jaar, laatste_nummer)
  values (p_bedrijf_id, v_jaar, 1)
  on conflict (bedrijf_id, jaar)
  do update set laatste_nummer = vergunning_nummers.laatste_nummer + 1
  returning laatste_nummer into v_nummer;

  select coalesce(klantcode, 'PVX') into v_klantcode from bedrijven where id = p_bedrijf_id;

  return v_klantcode || '-' || v_jaar || '-' || lpad(v_nummer::text, 4, '0');
end;
$$;

-- ---------------------------------------------------------------------------
-- Vragen ophalen voor de app
-- ---------------------------------------------------------------------------
-- Geeft de vragen van één fase terug, met de conditionele vervolgvragen die bij
-- het gekozen werktype horen. Geen koppelrijen = geldt voor elk werktype.
create or replace function public.rpc_vergunning_vragen(
  p_gebruiker_id uuid, p_werktype_id uuid, p_fase text
)
returns table(
  vraag_id uuid, vraagtekst text, antwoordtype text,
  verplicht boolean, blokkerend boolean, toelichting text, volgorde int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    return;
  end if;

  return query
    select v.id, v.vraagtekst, v.antwoordtype, v.verplicht, v.blokkerend, v.toelichting, v.volgorde
    from vergunning_vragen v
    where v.bedrijf_id = v_bedrijf_id
      and v.actief = true
      and v.fase = p_fase
      and (
        not exists (select 1 from vergunning_vraag_werktypes w where w.vraag_id = v.id)
        or exists (select 1 from vergunning_vraag_werktypes w where w.vraag_id = v.id and w.werktype_id = p_werktype_id)
      )
    order by v.volgorde;
end;
$$;

grant execute on function public.rpc_vergunning_vragen(uuid, uuid, text) to anon;

-- Werktypes voor de keuzelijst in de app.
create or replace function public.rpc_werktypes(p_gebruiker_id uuid)
returns table(id uuid, key text, naam text, toelichting text, volgorde int)
language sql
security definer
set search_path = public
as $$
  select w.id, w.key, w.naam, w.toelichting, w.volgorde
  from werktypes w
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true and g.bedrijf_id = w.bedrijf_id
  where w.actief = true
  order by w.volgorde;
$$;

grant execute on function public.rpc_werktypes(uuid) to anon;

-- Eerder ingetypte locaties, voor de autoaanvulling. Vrije tekst blijft vrije
-- tekst, maar zo groeit er vanzelf consistentie zonder een vaste indeling op te
-- leggen.
create or replace function public.rpc_vergunning_locaties(p_gebruiker_id uuid)
returns table(locatie text)
language sql
security definer
set search_path = public
as $$
  select distinct v.locatie_omschrijving
  from vuurvergunningen v
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true and g.bedrijf_id = v.bedrijf_id
  order by 1
  limit 50;
$$;

grant execute on function public.rpc_vergunning_locaties(uuid) to anon;

-- ---------------------------------------------------------------------------
-- Aanvraag
-- ---------------------------------------------------------------------------
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

  -- Een blokkerende vraag met NOK betekent dat het werk niet veilig kan
  -- beginnen; die aanvraag hoort niet eens ter goedkeuring aangeboden te worden.
  select string_agg(vr.vraagtekst, ' / ') into v_blokkerend
  from jsonb_array_elements(p_antwoorden) a
  join vergunning_vragen vr on vr.id = (a->>'vraag_id')::uuid
  where vr.blokkerend = true and (a->>'antwoord') = 'nok';

  if v_blokkerend is not null then
    raise exception 'Kan niet worden aangevraagd zolang dit niet in orde is: %', v_blokkerend;
  end if;

  -- Verplichte vragen moeten beantwoord zijn.
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

  return query select v_id, v_nummer;
end;
$$;

grant execute on function public.rpc_vergunning_aanvragen(uuid, uuid, text, text, timestamptz, timestamptz, uuid, jsonb) to anon;

-- ---------------------------------------------------------------------------
-- Goedkeuring: eenmalige code aanvragen
-- ---------------------------------------------------------------------------
-- De goedkeurder identificeert zich met zijn pincode en bevestigt met een code
-- uit zijn mailbox. Twee factoren: iets dat hij weet, en iets waar hij toegang
-- toe heeft. Zonder dat tweede is een handtekening niet meer waard dan vier
-- cijfers die een collega over je schouder meeleest.
create or replace function public.rpc_goedkeuring_code_aanvragen(
  p_vergunning_id uuid, p_pincode text, p_klantcode text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_gebruiker record;
  v_code text;
  v_status text;
begin
  select b.id into v_bedrijf_id from bedrijven b
  where upper(b.klantcode) = upper(btrim(coalesce(p_klantcode,'')));
  if v_bedrijf_id is null then
    return false;
  end if;

  select g.id, g.naam, g.email, g.rol into v_gebruiker
  from gebruikers g
  where g.pincode = p_pincode and g.actief = true and g.bedrijf_id = v_bedrijf_id
  limit 1;

  if v_gebruiker.id is null then
    return false;
  end if;

  -- Enkel wie mag goedkeuren, en enkel met een e-mailadres om de code naartoe
  -- te sturen.
  if v_gebruiker.rol not in ('leidinggevende','preventieadviseur','beheerder') then
    raise exception 'Deze gebruiker mag geen vuurvergunning goedkeuren';
  end if;
  if v_gebruiker.email is null or btrim(v_gebruiker.email) = '' then
    raise exception 'Er staat geen e-mailadres bij deze gebruiker; zonder mailbox kan er geen code verstuurd worden';
  end if;

  select status into v_status from vuurvergunningen
  where id = p_vergunning_id and bedrijf_id = v_bedrijf_id;
  if v_status is null then
    raise exception 'Onbekende vergunning';
  end if;
  if v_status <> 'aangevraagd' then
    raise exception 'Deze vergunning wacht niet op een beslissing (status: %)', v_status;
  end if;

  v_code := lpad(((public.willekeurige_byte() * 65536
                 + public.willekeurige_byte() * 256
                 + public.willekeurige_byte()) % 1000000)::text, 6, '0');

  insert into vergunning_goedkeuring_codes (vergunning_id, gebruiker_id, code, verloopt_op)
  values (p_vergunning_id, v_gebruiker.id, v_code, now() + interval '15 minutes');

  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-goedkeuring-code-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.geheim('webhook_secret')
    ),
    body := jsonb_build_object('gebruiker_id', v_gebruiker.id, 'vergunning_id', p_vergunning_id, 'code', v_code),
    timeout_milliseconds := 10000
  );

  return true;
end;
$$;

grant execute on function public.rpc_goedkeuring_code_aanvragen(uuid, text, text) to anon;

-- ---------------------------------------------------------------------------
-- Goedkeuring: beslissen
-- ---------------------------------------------------------------------------
create or replace function public.rpc_vergunning_beslissen(
  p_vergunning_id uuid,
  p_pincode text,
  p_klantcode text,
  p_code text,
  p_beslissing text,
  p_toelichting text,
  p_handtekening text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_gebruiker_id uuid;
  v_code_id uuid;
  v_nieuwe_status text;
begin
  if p_beslissing not in ('goedgekeurd','afgewezen','voorbehoud') then
    raise exception 'Ongeldige beslissing';
  end if;
  if p_beslissing in ('afgewezen','voorbehoud')
     and (p_toelichting is null or btrim(p_toelichting) = '') then
    raise exception 'Geef een toelichting: bij een weigering weet de aanvrager anders niet wat hij moet aanpassen, en bij voorbehoud zijn er geen voorwaarden';
  end if;

  select b.id into v_bedrijf_id from bedrijven b
  where upper(b.klantcode) = upper(btrim(coalesce(p_klantcode,'')));

  select g.id into v_gebruiker_id
  from gebruikers g
  where g.pincode = p_pincode and g.actief = true and g.bedrijf_id = v_bedrijf_id
    and g.rol in ('leidinggevende','preventieadviseur','beheerder')
  limit 1;

  if v_gebruiker_id is null then
    raise exception 'Ongeldige pincode of geen recht om goed te keuren';
  end if;

  select id into v_code_id
  from vergunning_goedkeuring_codes
  where vergunning_id = p_vergunning_id
    and gebruiker_id = v_gebruiker_id
    and code = p_code
    and gebruikt = false
    and verloopt_op > now()
  order by aangemaakt_op desc
  limit 1;

  if v_code_id is null then
    raise exception 'De code is ongeldig of verlopen';
  end if;

  if not exists (select 1 from vuurvergunningen
                 where id = p_vergunning_id and bedrijf_id = v_bedrijf_id and status = 'aangevraagd') then
    raise exception 'Deze vergunning wacht niet (meer) op een beslissing';
  end if;

  -- Bij voorbehoud NIET meteen actief: de aanvrager moet de voorwaarden eerst
  -- bevestigen (zie rpc_voorwaarden_bevestigen).
  v_nieuwe_status := case p_beslissing
    when 'goedgekeurd' then 'actief'
    when 'afgewezen' then 'afgewezen'
    else 'voorbehoud'
  end;

  update vuurvergunningen set
    status = v_nieuwe_status,
    goedgekeurd_door_id = v_gebruiker_id,
    goedgekeurd_op = now(),
    beslissing_toelichting = nullif(btrim(coalesce(p_toelichting,'')),''),
    handtekening = p_handtekening,
    handtekening_methode = 'pincode_emailcode'
  where id = p_vergunning_id;

  update vergunning_goedkeuring_codes set gebruikt = true where id = v_code_id;

  return v_nieuwe_status;
end;
$$;

grant execute on function public.rpc_vergunning_beslissen(uuid, text, text, text, text, text, text) to anon;

-- ---------------------------------------------------------------------------
-- Voorwaarden aanvaarden
-- ---------------------------------------------------------------------------
create or replace function public.rpc_voorwaarden_bevestigen(
  p_vergunning_id uuid, p_gebruiker_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  update vuurvergunningen set
    status = 'actief',
    voorwaarden_bevestigd_op = now(),
    voorwaarden_bevestigd_door_id = p_gebruiker_id
  where id = p_vergunning_id
    and bedrijf_id = v_bedrijf_id
    and status = 'voorbehoud'
    and aanvrager_id = p_gebruiker_id;

  if not found then
    raise exception 'Deze vergunning staat niet op voorbehoud, of u bent niet de aanvrager';
  end if;

  return true;
end;
$$;

grant execute on function public.rpc_voorwaarden_bevestigen(uuid, uuid) to anon;

-- ---------------------------------------------------------------------------
-- Intrekken (noodstop)
-- ---------------------------------------------------------------------------
-- Bewust een brede bevoegdheid: bij een noodstop moet niemand eerst op zoek
-- naar de ene persoon die mag beslissen.
create or replace function public.rpc_vergunning_intrekken(
  p_vergunning_id uuid, p_gebruiker_id uuid, p_reden text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_status text;
begin
  if p_reden is null or btrim(p_reden) = '' then
    raise exception 'Geef een reden op voor het intrekken';
  end if;

  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  select status into v_status from vuurvergunningen
  where id = p_vergunning_id and bedrijf_id = v_bedrijf_id;

  if v_status is null then
    raise exception 'Onbekende vergunning';
  end if;
  if v_status in ('afgesloten','ingetrokken','afgewezen') then
    raise exception 'Deze vergunning is al beëindigd (status: %)', v_status;
  end if;

  update vuurvergunningen set
    status = 'ingetrokken',
    ingetrokken_door_id = p_gebruiker_id,
    ingetrokken_op = now(),
    ingetrokken_reden = btrim(p_reden),
    -- Was het werk al bezig, dan blijft de nazorgplicht gelden: intrekken stopt
    -- het werk, niet de controle op nagloeiend materiaal. Fase C pikt dit op.
    vroegtijdig_beeindigd = (v_status = 'actief')
  where id = p_vergunning_id;

  return true;
end;
$$;

grant execute on function public.rpc_vergunning_intrekken(uuid, uuid, text) to anon;

-- ---------------------------------------------------------------------------
-- Opvragen vanuit de app
-- ---------------------------------------------------------------------------
-- Lichte statusbevraging waar de wachtende aanvrager op polst.
create or replace function public.rpc_vergunning_status(p_vergunning_id uuid, p_gebruiker_id uuid)
returns table(status text, beslissing_toelichting text, vergunningsnummer text)
language sql
security definer
set search_path = public
as $$
  select v.status, v.beslissing_toelichting, v.vergunningsnummer
  from vuurvergunningen v
  join gebruikers g on g.id = p_gebruiker_id and g.actief = true and g.bedrijf_id = v.bedrijf_id
  where v.id = p_vergunning_id;
$$;

grant execute on function public.rpc_vergunning_status(uuid, uuid) to anon;

-- Lijst voor de app: eigen aanvragen, plus wat op mijn beslissing wacht als ik
-- mag goedkeuren.
create or replace function public.rpc_mijn_vergunningen(p_gebruiker_id uuid)
returns table(
  id uuid, vergunningsnummer text, status text, werktype_naam text,
  locatie_omschrijving text, aanvrager_naam text, geldig_van timestamptz,
  geldig_tot timestamptz, beslissing_toelichting text, ben_aanvrager boolean
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
    select v.id, v.vergunningsnummer, v.status, w.naam, v.locatie_omschrijving,
           g.naam, v.geldig_van, v.geldig_tot, v.beslissing_toelichting,
           (v.aanvrager_id = p_gebruiker_id)
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

-- ---------------------------------------------------------------------------
-- Cascade bijwerken (zie de waarschuwing in 0043/0049/0050)
-- ---------------------------------------------------------------------------
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  delete from pincode_reset_codes
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id);

  delete from inspectie_resultaten
    where inspectie_id in (select id from inspecties where bedrijf_id = p_bedrijf_id);
  delete from inspecties where bedrijf_id = p_bedrijf_id;

  delete from inspectie_punt_types
    where punt_id in (
      select p.id from inspectie_punten p
      join inspectie_secties s on s.id = p.sectie_id
      where s.bedrijf_id = p_bedrijf_id
    );
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  -- Vergunningen vóór de vragen en werktypes: de antwoorden en codes hangen met
  -- cascade aan de vergunning, maar de vergunning verwijst zelf naar werktypes.
  delete from vuurvergunningen where bedrijf_id = p_bedrijf_id;
  delete from vergunning_nummers where bedrijf_id = p_bedrijf_id;
  delete from vergunning_vragen where bedrijf_id = p_bedrijf_id;
  delete from werktypes where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
