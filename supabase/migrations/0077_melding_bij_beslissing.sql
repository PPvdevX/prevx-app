-- De aanvrager verneemt een beslissing nu alleen doordat de app kort polst
-- zolang hij dat scherm openhoudt (zie vvPolling in app.html). Sluit hij de
-- app -- en dat doet iemand op een werf -- dan hoort hij niets, en blijft een
-- goedgekeurde vergunning liggen tot hij toevallig terugkijkt.
--
-- Dat was een bewuste beperking bij het ontwerp: er bestond toen geen push. Nu
-- wel. Deze migratie stuurt een melding zodra er beslist is, en ook wanneer de
-- aanvrager een voorbehoud bevestigt en het werk dus mag starten.
--
-- De tekst blijft kort en zonder werkplek: dit verschijnt op een vergrendeld
-- scherm. Het vergunningsnummer en de uitkomst volstaan om te weten of je moet
-- handelen; de rest staat in de app.
--
-- Verzenden gebeurt via net.http_post naar send-push, net als de rapportmail.
-- Dat is bewust "afvuren en niet wachten": mislukt de melding, dan mag dat de
-- beslissing zelf niet tegenhouden. De vergunning staat dan gewoon in de app,
-- precies zoals vandaag.

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
  v_aanvrager_id uuid;
  v_nummer text;
  v_titel text;
  v_tekst text;
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
  where id = p_vergunning_id
  returning aanvrager_id, vergunningsnummer into v_aanvrager_id, v_nummer;

  update vergunning_goedkeuring_codes set gebruikt = true where id = v_code_id;

  if v_aanvrager_id is not null then
    if p_beslissing = 'goedgekeurd' then
      v_titel := 'Vuurvergunning goedgekeurd';
      v_tekst := v_nummer || ' is goedgekeurd. Je mag starten.';
    elsif p_beslissing = 'afgewezen' then
      v_titel := 'Vuurvergunning afgewezen';
      v_tekst := v_nummer || ' is afgewezen. Open de app voor de reden.';
    else
      v_titel := 'Vuurvergunning onder voorbehoud';
      v_tekst := v_nummer || ' is goedgekeurd onder voorwaarden. Bevestig ze in de app voor je start.';
    end if;

    perform net.http_post(
      url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', public.geheim('webhook_secret')
      ),
      body := jsonb_build_object(
        'gebruiker_id', v_aanvrager_id,
        'titel', v_titel,
        'tekst', v_tekst,
        'tag', 'vergunning-' || p_vergunning_id
      ),
      timeout_milliseconds := 10000
    );
  end if;

  return v_nieuwe_status;
end;
$$;

grant execute on function public.rpc_vergunning_beslissen(uuid, text, text, text, text, text, text) to anon;
grant execute on function public.rpc_vergunning_beslissen(uuid, text, text, text, text, text, text) to authenticated;
