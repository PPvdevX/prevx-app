-- ===========================================================================
-- 0106_bericht_aan_de_vertrouwenspersoon.sql
-- ===========================================================================
-- Een melding die in het register valt en waar niemand bericht van krijgt,
-- wacht tot iemand toevallig het scherm opent. Bij een vraag over jobstudenten
-- is dat vervelend; hier is het schadelijk -- iemand heeft net iets verteld dat
-- hij moeilijk verteld krijgt, en dan blijft het weken liggen.
--
-- ---------------------------------------------------------------------------
-- WAT ER IN DAT BERICHT STAAT: ZO GOED ALS NIETS
-- ---------------------------------------------------------------------------
-- De mail zegt dat er een verklaring bijgekomen is en waar ze te lezen valt.
-- Meer niet. Geen beschrijving, geen plaats, geen soort feit, geen datum van de
-- feiten. Niet uit voorzichtigheidsdrang, maar omdat een mailbox een andere
-- plaats is dan een afgeschermd scherm: mail wordt doorgestuurd, staat op een
-- vergrendeld scherm te lezen, en bij een zaakvoerder kijkt soms een secretaresse
-- mee. Wat er in het register hoort te blijven, hoort niet in een mail.
--
-- Daarom stuurt de trigger ook alleen het bedrijf-id mee en niet het id van de
-- verklaring. De functie aan de andere kant kán de tekst dus niet opzoeken,
-- ook niet per ongeluk en ook niet als iemand haar later uitbreidt.
--
-- ---------------------------------------------------------------------------
-- NAAR WIE
-- ---------------------------------------------------------------------------
-- Naar de vertrouwenspersonen van dat bedrijf. Is er geen aangewezen, dan naar
-- de klant-beheerders -- dat is de werkgever, en volgens artikel I.3-3 komt het
-- register dan bij hem terecht. In dat geval zegt de mail er ook bij dat er
-- geen vertrouwenspersoon aangewezen is, want dat is zelf iets om aan te pakken.
--
-- Naar PrevX gaat er niets. Ook geen kopie, ook niet "ter info".
--
-- Enkel bij meldingen vanaf de gsm. Tekent de vertrouwenspersoon zelf een
-- verklaring op, dan weet ze het al.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- Wie moet het weten?
-- ---------------------------------------------------------------------------
-- Security definer, want de Edge Function draait met de servicesleutel maar
-- mag niet zelf gaan rondkijken in gebruikers. Ze vraagt hier adressen op en
-- krijgt adressen terug -- geen namen, geen rollen, geen id's.
create or replace function public.rpc_ontvangers_feiten_derden(p_bedrijf_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adressen text[];
  v_heeft_vp boolean;
  v_bedrijf text;
begin
  select naam into v_bedrijf from bedrijven where id = p_bedrijf_id;

  select coalesce(array_agg(email), '{}'), true
    into v_adressen, v_heeft_vp
  from gebruikers
  where bedrijf_id = p_bedrijf_id
    and actief = true
    and vertrouwenspersoon = true
    and email is not null and btrim(email) <> '';

  if v_adressen is null or array_length(v_adressen, 1) is null then
    v_heeft_vp := false;
    select coalesce(array_agg(email), '{}')
      into v_adressen
    from gebruikers
    where bedrijf_id = p_bedrijf_id
      and actief = true
      and dossier_rol = 'klant_beheerder'
      and email is not null and btrim(email) <> '';
  end if;

  return jsonb_build_object(
    'bedrijf', coalesce(v_bedrijf, 'een klant'),
    'adressen', to_jsonb(coalesce(v_adressen, '{}')),
    'vertrouwenspersoon_aangewezen', coalesce(v_heeft_vp, false)
  );
end;
$$;

revoke execute on function public.rpc_ontvangers_feiten_derden(uuid) from public;
-- Enkel de servicesleutel roept dit aan; authenticated heeft er niets te zoeken.
revoke execute on function public.rpc_ontvangers_feiten_derden(uuid) from authenticated;


-- ---------------------------------------------------------------------------
-- De trigger
-- ---------------------------------------------------------------------------
create or replace function public.meld_feit_van_derde()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Alleen wat van de vloer komt. Wie zelf optekent, hoeft geen mail dat zij
  -- iets opgetekend heeft.
  if not new.via_app then
    return new;
  end if;

  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-feit-derden-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.geheim('webhook_secret')
    ),
    -- Alleen het bedrijf. Zie de uitleg bovenaan: zonder het id van de
    -- verklaring kan de andere kant de tekst niet opzoeken.
    body := jsonb_build_object('bedrijf_id', new.bedrijf_id),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$;

drop trigger if exists trg_meld_feit_van_derde on feiten_van_derden;
create trigger trg_meld_feit_van_derde
  after insert on feiten_van_derden
  for each row execute function public.meld_feit_van_derde();


notify pgrst, 'reload schema';
