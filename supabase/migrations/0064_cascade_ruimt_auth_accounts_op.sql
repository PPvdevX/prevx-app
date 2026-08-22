-- Aan het licht gekomen doordat pvdweb@outlook.com op "nog niet gekoppeld"
-- bleef hangen: het bedrijf Jerry Ver Eecke BV is verwijderd, de cascade uit
-- 0043 wiste netjes de gebruikers-rij, maar de auth-account bleef staan.
--
-- Twee gevolgen, en het tweede is het zwaarste:
--
-- 1. Die login blijft werken. Er lekt niets -- huidig_bedrijf_id() geeft null
--    zonder gebruikers-rij, dus alle policies laten nul rijen door -- maar een
--    account van een klant die je niet meer bedient hoort niet te blijven
--    bestaan, en hij kan zijn wachtwoord nog altijd laten herstellen.
--
-- 2. Het e-mailadres blijft in auth.users staan. Dat is een persoonsgegeven.
--    Je vertelt de klant dat zijn dossier verwijderd is terwijl je nog altijd
--    zijn contactgegevens bijhoudt. Dat is het echte probleem hier, niet de
--    toegang.
--
-- Daarom ruimt de cascade voortaan ook de auth-accounts op. Met twee remmen,
-- want dit is onomkeerbaar:
--   - alleen accounts die na het wissen van deze klant nergens anders nog een
--     gebruikers-rij hebben. Iemand die bij twee klanten in het bestand staat,
--     verliest zijn login niet.
--   - nooit een superbeheerder. Dat ben jij; jouw eigen account mag nooit
--     sneuvelen omdat je een klant verwijdert.
--
-- Bestaande wezen (zoals pvdweb@outlook.com) ruimt dit NIET automatisch op --
-- zie de losse opdracht onderaan, die je bewust zelf uitvoert.

-- Onderweg gevonden en meteen meegenomen: trg_antwoord_onwijzigbaar (0057)
-- vuurt ook bij DELETE. Zodra een klant één vuurvergunning had afgesloten, liep
-- "bedrijf verwijderen" dus vast op "de vergunning is afgesloten" -- een fout
-- die niets met verwijderen te maken heeft en die pas zou opduiken bij de
-- eerste klant die de module echt gebruikt had.
--
-- De deleteregel gewoon schrappen zou werken (er is enkel een SELECT-policy op
-- vergunning_antwoorden, dus via de API kan niemand er iets wissen), maar dan
-- verdwijnt ook de bescherming tegen een fout in een toekomstige RPC. In plaats
-- daarvan maak ik de uitzondering expliciet: de trigger laat een delete door
-- wanneer de transactie zichzelf gemarkeerd heeft als bedrijfsverwijdering.
-- Alleen de cascade hieronder zet die vlag, ze geldt enkel binnen die ene
-- transactie, en ze staat leesbaar in de code in plaats van als stille
-- uitzondering.
create or replace function public.blokkeer_antwoord_afgesloten_vergunning()
returns trigger
language plpgsql
as $$
declare
  v_status text;
begin
  if coalesce(current_setting('prevx.bedrijf_verwijderen', true), '') = 'aan' then
    return coalesce(new, old);
  end if;

  select status into v_status from vuurvergunningen
  where id = coalesce(new.vergunning_id, old.vergunning_id);
  if v_status = 'afgesloten' then
    raise exception 'De vergunning is afgesloten; antwoorden kunnen niet meer wijzigen';
  end if;
  return coalesce(new, old);
end;
$$;

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

  -- Enkel geldig binnen deze transactie; valt vanzelf weg, ook bij een fout.
  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  -- Eerst vastleggen wélke auth-accounts aan deze klant hangen; na de delete
  -- hieronder is dat niet meer te achterhalen.
  select coalesce(array_agg(g.auth_user_id), '{}')
    into v_auth_ids
  from gebruikers g
  where g.bedrijf_id = p_bedrijf_id
    and g.auth_user_id is not null;

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
      where s.bedrijf_id = p_bedrijf_id
    );
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

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;

  -- Pas nu de auth-accounts, en enkel die geen enkele band meer hebben.
  delete from auth.users u
  where u.id = any(v_auth_ids)
    and not exists (select 1 from gebruikers g where g.auth_user_id = u.id)
    and not exists (select 1 from superbeheerders s where s.auth_user_id = u.id);
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
