-- SPOEDHERSTEL. Migratie 0053 verwijderde rpc_login_chauffeur terwijl de
-- chauffeurs-app die nog gebruikte: die app was op dat moment nog niet
-- uitgerold met de klantcode-versie. Gevolg: geen enkele chauffeur raakte nog
-- binnen. Deze migratie zet die functie exact terug zoals ze in 0051 stond,
-- inclusief de begrenzing op mislukte pogingen.
--
-- Na deze migratie werken beide wegen naast elkaar:
--   oude app  -> rpc_login_chauffeur        (pincode alleen, platformbreed)
--   nieuwe app -> rpc_login_chauffeur_klant  (klantcode + pincode)
--
-- 0053 blijft klaarliggen en mag pas opnieuw uitgevoerd worden wanneer:
--   1. de nieuwe app live staat, EN
--   2. elke chauffeur zijn klantcode één keer heeft ingevoerd.
-- Pas dan is de platformbrede ingang echt dicht. Controleer punt 2 door bij de
-- klanten na te vragen of iedereen ingelogd raakt; er is geen betrouwbare
-- meting in de databank die het verschil tussen beide apps toont.

create or replace function public.rpc_login_chauffeur(p_pincode text)
returns table(id uuid, naam text, rol text, bedrijf_id uuid, rol_label text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip text;
begin
  v_ip := public.verzoek_ip();

  if public.login_begrenzing_overschreden(v_ip, 'login') then
    perform public.noteer_login_poging(v_ip, 'login', false, true);
    raise exception 'Te veel mislukte pogingen. Probeer het over een kwartier opnieuw.'
      using errcode = 'P0001';
  end if;

  return query
    select g.id, g.naam, g.rol, g.bedrijf_id,
      case g.rol
        when 'chauffeur' then b.rol_label_chauffeur
        when 'leidinggevende' then b.rol_label_leidinggevende
        when 'preventieadviseur' then b.rol_label_preventieadviseur
        when 'beheerder' then b.rol_label_beheerder
      end as rol_label
    from gebruikers g
    join bedrijven b on b.id = g.bedrijf_id
    where g.pincode = p_pincode and g.actief = true
    limit 1;

  perform public.noteer_login_poging(v_ip, 'login', found, false);
  return;
end;
$$;

grant execute on function public.rpc_login_chauffeur(text) to anon;
