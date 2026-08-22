-- Opkuis na de Security Advisor. Nul fouten, 69 waarschuwingen -- waarvan het
-- grootste deel terecht is en zo hoort te blijven. Deze migratie pakt alleen
-- wat echt te verbeteren valt.
--
-- WAT WE NIET AANRAKEN, EN WAAROM:
--
-- "Public Can Execute SECURITY DEFINER Function" op de chauffeurs-RPC's
-- (rpc_login_chauffeur_klant, rpc_voertuigen, rpc_checklist, rpc_verzend_inspectie,
-- de vergunning-RPC's, ...). Dat is geen gebrek maar het ontwerp: de app heeft
-- geen sessie en komt uitsluitend via deze functies binnen, die elk zelf
-- controleren wie er belt. Zou je ze afschermen, dan werkt de app niet meer.
-- De advisor kan dat onderscheid niet maken; wij wel. In 0067/0068 is de lijst
-- teruggebracht tot exact wat app.html en account.html aanroepen.
--
-- "Extension in Public" op pg_net. Al eerder bewust uitgesteld: pg_net
-- verplaatsen riskeert elke net.http_post te breken, en dat is de weg waarlangs
-- alle mail en alle meldingen vertrekken. Niet waard voor een WARN.
--
-- WAT WE WEL DOEN:
--
-- 1. `set search_path` op de drie functies die het missen. Bij een SECURITY
--    DEFINER-functie is dat geen formaliteit: zonder vast zoekpad bepaalt de
--    aanroeper welke `gebruikers` of `now()` de functie te zien krijgt, en die
--    draait met de rechten van de eigenaar. Bij willekeurige_byte weegt dat
--    het zwaarst -- die levert de willekeur voor pincodes en herstelcodes.
--
-- 2. Het EXECUTE-recht weghalen bij de triggerfuncties. Via de API zijn ze niet
--    bereikbaar (PostgREST kan een functie die `trigger` teruggeeft niet
--    aanroepen), dus dit is opruimen en geen gat dichten. Maar een recht dat
--    niemand nodig heeft, hoort er niet te staan -- en het haalt vier regels
--    uit de lijst zodat wat overblijft ook echt aandacht verdient.
--
-- De drie functie-inhouden hieronder zijn ONGEWIJZIGD overgenomen uit 0052,
-- 0057 en 0064; alleen de regel `set search_path = public` is toegevoegd. Ze
-- zijn programmatisch uit die bestanden gehaald en niet overgetypt -- bij een
-- eerste poging had ik daarbij het vergunningsnummer uit een foutmelding laten
-- vallen zonder het te merken.

-- ---------------------------------------------------------------------------
-- 1. Vast zoekpad
-- ---------------------------------------------------------------------------

create or replace function public.willekeurige_byte()
returns int
language sql
volatile
set search_path = public
as $$
  select get_byte(decode(substr(replace(gen_random_uuid()::text, '-', ''), 1, 2), 'hex'), 0);
$$;

create or replace function public.blokkeer_wijziging_afgesloten_vergunning()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.status = 'afgesloten' then
    raise exception 'Deze vergunning is afgesloten en kan niet meer gewijzigd worden (nummer %)', old.vergunningsnummer;
  end if;
  return new;
end;
$$;

create or replace function public.blokkeer_antwoord_afgesloten_vergunning()
returns trigger
language plpgsql
set search_path = public
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

-- ---------------------------------------------------------------------------
-- 2. Overbodige rechten op triggerfuncties
-- ---------------------------------------------------------------------------
-- Een create or replace hierboven zet de standaardrechten opnieuw, dus dit moet
-- erna komen.

revoke execute on function public.willekeurige_byte() from public, anon, authenticated;
revoke execute on function public.blokkeer_wijziging_afgesloten_vergunning() from public, anon, authenticated;
revoke execute on function public.blokkeer_antwoord_afgesloten_vergunning() from public, anon, authenticated;
revoke execute on function public.blokkeer_dossier_rol_wijziging() from public, anon, authenticated;
revoke execute on function public.zet_standaard_bedrijf_modules() from public, anon, authenticated;

-- Een trigger draait met de rechten van de tabeleigenaar, niet van wie de
-- INSERT of UPDATE doet. Deze intrekking raakt de werking van de triggers dus
-- niet -- controleer dat na het uitvoeren wel even door een vergunning aan te
-- passen en een dossierrol te wijzigen.
