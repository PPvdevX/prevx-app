-- Een chauffeur heeft zelden een werkmailadres, en zonder adres werkt "Pincode
-- vergeten" niet: die weg stuurt een code per e-mail. De zelfbediening werkte
-- dus precies niet voor de groep die ze het meest nodig heeft, en de enige
-- uitweg was iemand met portaaltoegang bellen.
--
-- Voortaan herstelt de leidinggevende het ter plaatse in de app, met zijn eigen
-- pincode. Hij staat toch op de werf.
--
-- BEPERKING DIE ER BEWUST IN ZIT: alleen pincodes van CHAUFFEURS.
-- Kon een leidinggevende die van een andere leidinggevende herstellen, dan kent
-- hij die code en kan hij in diens naam vuurvergunningen goedkeuren -- en sinds
-- 0078 is die pincode de enige factor bij een goedkeuring. Dat zou een
-- achterdeur zijn naar precies de handtekening die het dossier moet dragen.
-- Wie zelf mag goedkeuren, krijgt zijn pincode via het portaal.
--
-- Wie het deed en wanneer wordt vastgelegd. Een pincode ondertekent een
-- vuurvergunning; dat er stilletjes een nieuwe uitgedeeld kan worden zonder
-- spoor, past niet bij een dossier dat achteraf iets moet kunnen aantonen.

alter table gebruikers
  add column if not exists pincode_gewijzigd_op timestamptz,
  add column if not exists pincode_gewijzigd_door_id uuid references gebruikers(id);

create or replace function public.rpc_pincode_herstellen_collega(
  p_klantcode text,
  p_pincode text,
  p_gebruiker_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
  v_bedrijf_id uuid;
  v_hersteller_id uuid;
  v_doel_rol text;
  v_code text;
  v_poging int := 0;
begin
  v_ip := public.verzoek_ip();

  -- Eigen teller: mislukte herstelpogingen mogen de login van een werkende
  -- chauffeur niet blokkeren.
  if public.login_begrenzing_overschreden(v_ip, 'pinherstel') then
    perform public.noteer_login_poging(v_ip, 'pinherstel', false, true);
    raise exception 'Te veel mislukte pogingen. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
  end if;

  select b.id into v_bedrijf_id from bedrijven b
  where upper(b.klantcode) = upper(btrim(coalesce(p_klantcode, '')));

  if v_bedrijf_id is null then
    perform public.noteer_login_poging(v_ip, 'pinherstel', false, false);
    raise exception 'Ongeldige pincode of geen recht om een pincode te herstellen';
  end if;

  select g.id into v_hersteller_id
  from gebruikers g
  where g.pincode = p_pincode
    and g.actief = true
    and g.bedrijf_id = v_bedrijf_id
    and g.rol in ('leidinggevende','preventieadviseur','beheerder')
  limit 1;

  perform public.noteer_login_poging(v_ip, 'pinherstel', v_hersteller_id is not null, false);

  if v_hersteller_id is null then
    -- Eén melding voor beide gevallen: wie geen recht heeft, hoort niet te
    -- kunnen aflezen of een pincode bestond.
    raise exception 'Ongeldige pincode of geen recht om een pincode te herstellen';
  end if;

  select g.rol into v_doel_rol
  from gebruikers g
  where g.id = p_gebruiker_id and g.actief = true and g.bedrijf_id = v_bedrijf_id;

  if v_doel_rol is null then
    raise exception 'Die collega hoort niet bij dit bedrijf';
  end if;

  if v_doel_rol <> 'chauffeur' then
    raise exception 'Alleen de pincode van een chauffeur kan hier hersteld worden. Voor iemand die vergunningen mag goedkeuren, gebeurt dat via het portaal.';
  end if;

  if p_gebruiker_id = v_hersteller_id then
    raise exception 'Gebruik "Pincode wijzigen" om je eigen pincode aan te passen';
  end if;

  -- Uniek binnen dit bedrijf: sinds de klantcode (0052) gelden pincodes per
  -- klant, dus platformbrede uniciteit is niet nodig en verbruikt de voorraad
  -- van 10.000 codes over alle klanten samen.
  loop
    v_poging := v_poging + 1;
    if v_poging > 200 then
      raise exception 'Geen vrije pincode gevonden voor dit bedrijf';
    end if;
    v_code := lpad(((public.willekeurige_byte() * 256 + public.willekeurige_byte()) % 10000)::text, 4, '0');
    exit when not exists (
      select 1 from gebruikers
      where pincode = v_code and actief = true and bedrijf_id = v_bedrijf_id
    );
  end loop;

  update gebruikers set
    pincode = v_code,
    pincode_gewijzigd_op = now(),
    pincode_gewijzigd_door_id = v_hersteller_id
  where id = p_gebruiker_id;

  return v_code;
end;
$$;

revoke execute on function public.rpc_pincode_herstellen_collega(text, text, uuid) from public;
grant execute on function public.rpc_pincode_herstellen_collega(text, text, uuid) to anon;
grant execute on function public.rpc_pincode_herstellen_collega(text, text, uuid) to authenticated;
