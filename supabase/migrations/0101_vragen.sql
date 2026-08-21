-- ===========================================================================
-- 0100_vragen.sql
-- Vragen die niet meteen een antwoord hebben
-- ===========================================================================
-- Een vraag waarop je meteen kan antwoorden, is een goed telefoongesprek. Een
-- vraag waarop je moet opzoeken, is een slecht telefoongesprek: er wordt beloofd
-- terug te bellen, de klant onthoudt de helft, en het antwoord bestaat daarna
-- alleen nog in twee hoofden.
--
-- Deze tabel geeft zo'n vraag uitstel zonder verlies. Ze blijft staan tot ze
-- beantwoord is, het antwoord komt in het dossier terecht, en het draagt een
-- datum en een naam. Dat laatste is voor de preventieadviseur geen administratie
-- maar dekking: er staat zwart op wit welk advies wanneer gegeven is.
--
-- WAAROM GEEN GESPREK MAAR ÉÉN ANTWOORDVELD
-- Een reeks berichten heen en weer wordt een chat, en een chat belooft
-- aanwezigheid. Dat is precies wat hier niet beloofd wordt: het bestaansrecht
-- van dit scherm is dat een vraag mág blijven liggen tot ze goed beantwoord is.
-- Volstaat één antwoord niet, dan is dat geen chat maar een gesprek -- daarvoor
-- staat het telefoonnummer in het portaal.
--
-- WAAROM IEDEREEN BIJ DE KLANT ALLE VRAGEN ZIET
-- Bewuste keuze: het scheelt dubbele vragen en het maakt het dossier rijker.
-- Wie iets vraagt wat een collega vorig jaar al vroeg, vindt het antwoord zelf.
-- De keerzijde is dat een vraag van de zaakvoerder zichtbaar is voor de
-- magazijnier -- daarom staat er bij het stellen expliciet dat de vraag in het
-- dossier komt, en gaan gevoelige zaken niet langs hier maar langs de telefoon.
-- ===========================================================================

create table if not exists vragen (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),

  -- Naam én verwijzing. De verwijzing kan wegvallen wanneer iemand het bedrijf
  -- verlaat; de naam hoort in het dossier te blijven staan, net als bij
  -- keuringen (0087).
  gebruiker_id uuid references gebruikers(id) on delete set null,
  gesteld_door text not null,
  vraag text not null,
  gesteld_op timestamptz not null default now(),

  antwoord text,
  beantwoord_op timestamptz,
  beantwoord_door text,

  status text not null default 'open' check (status in ('open','beantwoord')),

  constraint vraag_niet_leeg check (btrim(vraag) <> ''),
  -- Beantwoord zonder antwoord bestaat niet. In de databank afdwingen, niet
  -- alleen in het scherm.
  constraint antwoord_bij_beantwoord check (
    status <> 'beantwoord' or (antwoord is not null and btrim(antwoord) <> '')
  )
);

create index if not exists idx_vragen_bedrijf on vragen (bedrijf_id, status, gesteld_op desc);

alter table vragen enable row level security;

-- Iedereen bij de klant leest alle vragen van zijn bedrijf.
create policy portal_select_vragen on vragen
  for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

-- En mag er zelf een stellen. Bewust niet beperkt tot de klant-beheerder: de
-- vraag komt vaak van wie het werk doet, niet van wie het dossier beheert.
create policy portal_insert_vragen on vragen
  for insert to authenticated
  with check (
    public.is_superbeheerder()
    or bedrijf_id = public.huidig_bedrijf_id()
  );

-- Antwoorden doet PrevX. Een klant die zijn eigen vraag kan bijwerken, kan ook
-- een antwoord overschrijven, en dan is het dossier geen dossier meer.
create policy superbeheerder_update_vragen on vragen
  for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_vragen on vragen
  for delete to authenticated
  using (public.is_superbeheerder());


-- ---------------------------------------------------------------------------
-- Antwoorden zet meteen de status en de sporen
-- ---------------------------------------------------------------------------
-- Zo hoeft geen enkel scherm te onthouden dat er drie velden samen horen.
create or replace function public.zet_vraag_beantwoord()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wie text;
begin
  if new.antwoord is not null and btrim(new.antwoord) <> ''
     and (old.antwoord is null or btrim(old.antwoord) = '') then
    select g.naam into v_wie
    from gebruikers g
    where g.auth_user_id = auth.uid() and g.actief = true
    limit 1;

    new.status := 'beantwoord';
    new.beantwoord_op := coalesce(new.beantwoord_op, now());
    new.beantwoord_door := coalesce(new.beantwoord_door, v_wie, 'PrevX');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_vraag_beantwoord on vragen;
create trigger trg_vraag_beantwoord
  before update on vragen
  for each row execute function public.zet_vraag_beantwoord();


-- ---------------------------------------------------------------------------
-- Verwittiging bij een nieuwe vraag
-- ---------------------------------------------------------------------------
-- Zonder bericht ligt een vraag te wachten tot iemand toevallig het scherm
-- opent, en dan is schriftelijk vragen trager dan bellen -- precies het
-- omgekeerde van wat dit moet oplossen.
--
-- Dezelfde weg als de inspectiemail (0016) en de nazorgherinneringen (0060):
-- pg_net roept een Edge Function aan met de sleutel uit Vault. De aanroep is
-- asynchroon, dus een haperende mail houdt nooit een vraag tegen.
create or replace function public.meld_nieuwe_vraag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-vraag-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.geheim('webhook_secret')
    ),
    body := jsonb_build_object('vraag_id', new.id),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists trg_meld_nieuwe_vraag on vragen;
create trigger trg_meld_nieuwe_vraag
  after insert on vragen
  for each row execute function public.meld_nieuwe_vraag();


-- ---------------------------------------------------------------------------
-- Meenemen in het verwijderen van een bedrijf
-- ---------------------------------------------------------------------------
-- Eén regel erbij; de rest van de cascade is die van 0098, ongewijzigd.
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_ids uuid[];
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  select coalesce(array_agg(g.auth_user_id), '{}')
    into v_auth_ids
  from gebruikers g
  where g.bedrijf_id = p_bedrijf_id and g.auth_user_id is not null;

  delete from vergunning_herinneringen
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_goedkeuring_codes
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_antwoorden
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vuurvergunningen where bedrijf_id = p_bedrijf_id;
  delete from vergunning_nummers where bedrijf_id = p_bedrijf_id;

  delete from vergunning_vraag_werktypes
    where vraag_id in (select id from vergunning_vragen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_vragen where bedrijf_id = p_bedrijf_id;
  delete from werktypes where bedrijf_id = p_bedrijf_id;

  delete from pincode_reset_codes
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id);

  delete from inspectie_resultaten
    where inspectie_id in (select id from inspecties where bedrijf_id = p_bedrijf_id);
  delete from inspecties where bedrijf_id = p_bedrijf_id;

  delete from inspectie_punt_types
    where punt_id in (
      select p.id from inspectie_punten p
      join inspectie_secties s on s.id = p.sectie_id
      where s.bedrijf_id = p_bedrijf_id);
  delete from inspectie_sectie_types
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from vragen where bedrijf_id = p_bedrijf_id;
  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from samenwerking where bedrijf_id = p_bedrijf_id;
  delete from lmra_risico_antwoorden
    where lmra_id in (select id from lmras where bedrijf_id = p_bedrijf_id);
  delete from lmras where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_lmra_risicos where bedrijf_id = p_bedrijf_id;
  delete from chemische_producten where bedrijf_id = p_bedrijf_id;
  delete from keuringen where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from document_nummers where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from brandpreventie_status where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;

  if array_length(v_auth_ids, 1) is not null then
    delete from auth.users where id = any (v_auth_ids);
  end if;
end;
$$;

revoke execute on function public.rpc_verwijder_bedrijf_cascade(uuid) from public;
grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;

do $$
begin
  raise notice 'Tabel vragen aangemaakt. Vergeet de Edge Function send-vraag-email niet uit te rollen (Verify JWT uit), anders komt er geen bericht binnen bij een nieuwe vraag.';
end
$$;
