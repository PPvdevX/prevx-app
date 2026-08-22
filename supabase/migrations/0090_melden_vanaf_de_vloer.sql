-- Melden vanaf de werkvloer.
--
-- De module bestaat sinds 0022: een tabel, een RPC en een knop in het portaal.
-- Alleen leunt `rpc_meld_incident` op auth.uid(), en dat betekent dat enkel
-- iemand met portaaltoegang kan melden. De persoon die de losse leuning ziet
-- heeft de app, niet het portaal. Er stond dus een meldmodule klaar zonder de
-- mensen die ze zouden gebruiken.
--
-- Deze migratie voegt de weg vanuit de app toe: klantcode + pincode, geen
-- sessie, dus een security definer-RPC voor `anon` -- exact hetzelfde patroon
-- als de LMRA-RPC's (0083) en de vergunningen (0057).
--
-- Waarom een aparte functie en niet de bestaande uitbreiden: die twee
-- verschillen in hoe ze de melder vaststellen. In het portaal komt de naam uit
-- auth.uid(), in de app uit p_gebruiker_id. Dat samenpersen in één functie
-- levert een functie op die van zichzelf niet weet in welke wereld ze draait,
-- en dat is precies het soort functie waar later een gat in valt.

alter table meldingen
  add column if not exists gebruiker_id uuid references gebruikers(id),
  add column if not exists locatie text,
  add column if not exists foto_url text;

-- 'onveilige-situatie' komt erbij naast ongeval, bijna-ongeval en vraag. Dat is
-- het geval dat op de vloer het vaakst voorkomt en vandaag in WhatsApp belandt:
-- iets dat nog niet misging maar wel gaat mislopen.
create or replace function public.rpc_meld_incident_app(
  p_gebruiker_id uuid,
  p_type text,
  p_omschrijving text,
  p_locatie text,
  p_foto_url text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_naam text;
  v_type text;
  v_id uuid;
begin
  select bedrijf_id, naam into v_bedrijf_id, v_naam
  from gebruikers
  where id = p_gebruiker_id and actief = true;

  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  v_type := lower(btrim(coalesce(p_type, '')));
  if v_type not in ('onveilige-situatie', 'bijna-ongeval', 'ongeval', 'vraag') then
    raise exception 'Ongeldig type melding';
  end if;

  if coalesce(btrim(p_omschrijving), '') = '' then
    raise exception 'Beschrijf kort wat u ziet';
  end if;

  -- De naam komt uit de databank en niet uit het toestel: bij een
  -- ongevalmelding mag niet ter discussie staan wie ze deed.
  insert into meldingen (bedrijf_id, gebruiker_id, type, omschrijving, locatie, foto_url, melder_naam)
  values (v_bedrijf_id, p_gebruiker_id, v_type, btrim(p_omschrijving),
          nullif(btrim(coalesce(p_locatie, '')), ''), nullif(btrim(coalesce(p_foto_url, '')), ''),
          v_naam)
  returning id into v_id;

  return v_id;
end;
$$;

-- Twee lagen rechten, zoals vastgesteld in 0067/0068: Postgres geeft bij het
-- aanmaken EXECUTE aan PUBLIC, en Supabase' standaardrechten geven het aan
-- anon en authenticated. Allebei intrekken en dan gericht teruggeven.
revoke execute on function public.rpc_meld_incident_app(uuid, text, text, text, text) from public;
grant execute on function public.rpc_meld_incident_app(uuid, text, text, text, text) to anon;

-- ---------------------------------------------------------------------------
-- Dezelfde vier types in het portaal
-- ---------------------------------------------------------------------------
-- Anders heet hetzelfde ding op twee plaatsen anders en valt een melding uit de
-- app buiten de filter van het portaal.
create or replace function public.rpc_meld_incident(p_type text, p_omschrijving text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_melder_naam text;
  v_type text;
  v_melding_id uuid;
begin
  v_bedrijf_id := public.huidig_bedrijf_id();
  if v_bedrijf_id is null then
    raise exception 'Niet geautoriseerd';
  end if;

  v_type := lower(btrim(coalesce(p_type, '')));
  if v_type not in ('onveilige-situatie', 'bijna-ongeval', 'ongeval', 'vraag') then
    raise exception 'Ongeldig type melding';
  end if;

  if coalesce(btrim(p_omschrijving), '') = '' then
    raise exception 'Beschrijf kort wat u ziet';
  end if;

  select naam into v_melder_naam from gebruikers where auth_user_id = auth.uid() and actief = true limit 1;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam)
  values (v_bedrijf_id, v_type, btrim(p_omschrijving), v_melder_naam)
  returning id into v_melding_id;

  return v_melding_id;
end;
$$;

revoke execute on function public.rpc_meld_incident(text, text) from public, anon;
grant execute on function public.rpc_meld_incident(text, text) to authenticated;
