-- Goedkeuren gebeurt voortaan met de pincode alleen; de eenmalige code per
-- e-mail vervalt.
--
-- Beslissing van de gebruiker na het in de praktijk te hebben gebruikt: bij
-- meerdere vergunningen per dag is wachten op een mail en een code overtypen
-- geen beveiliging meer maar een hindernis, en hindernissen worden omzeild --
-- dan liggen er straks briefjes met pincodes naast de computer en is de
-- toestand slechter dan met één factor.
--
-- Wat er niet verandert: de controle zit nog steeds hier, niet in de app. De
-- pincode wordt in de databank geverifieerd, samen met de vraag of die persoon
-- de rol heeft om goed te keuren. Dat de knoppen in de app pas verschijnen na
-- een geldige pincode is gemak, geen beveiliging.
--
-- Wat wél verandert, en dat hoort het dossier te tonen: handtekening_methode
-- wordt 'pincode' en niet meer 'pincode_emailcode'. Een goedkeuring van vandaag
-- en een van vorige maand zijn niet even sterk, en dan moet je dat achteraf
-- kunnen zien. Oude vergunningen houden hun eigen vermelding.
--
-- rpc_goedkeuring_code_aanvragen en vergunning_goedkeuring_codes blijven
-- bestaan. Ze worden niet meer aangeroepen, maar de codes die er staan horen
-- bij vergunningen die er al zijn, en dat is bewijsmateriaal.

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

  -- p_code blijft in de handtekening staan om de aanroep vanuit oudere
  -- app-versies niet te breken, maar wordt niet meer gecontroleerd.

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
    handtekening_methode = 'pincode'
  where id = p_vergunning_id
  returning aanvrager_id, vergunningsnummer into v_aanvrager_id, v_nummer;

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
