-- Zelfde soort gat als 0064, nu bij de opslag: rpc_verwijder_bedrijf_cascade
-- wist de rijen, maar laat de bestanden staan. Foto's van vaststellingen,
-- handtekeningen, klantdocumenten en kennisbankstukken blijven na het
-- verwijderen van een klant gewoon bestaan.
--
-- Dat weegt hier zwaarder dan bij de auth-accounts, want alle vijf de buckets
-- staan op `public`. De inhoud is niet te doorzoeken -- opsommen wordt door RLS
-- geweigerd en elk pad bestaat uit twee UUID's, dus raden is uitgesloten --
-- maar wie een URL heeft, houdt hem. Zonder inloggen, voor altijd. En die
-- URL's reizen: de inspectiemail zet de handtekening rechtstreeks in het
-- bericht met <img src="...">, dus elke doorgestuurde mail draagt een blijvende
-- publieke link naar een handtekening.
--
-- Een klant die vraagt zijn dossier te verwijderen, hoort niet achteraf te
-- ontdekken dat de handtekeningen van zijn chauffeurs nog online staan.
--
-- Let op de beperking: dit wist de rijen in storage.objects, waardoor de
-- bestanden via de API onbereikbaar worden en elke publieke URL een 404 geeft.
-- Of het onderliggende bestand ook fysiek uit de opslag verdwijnt, beheert
-- Supabase zelf; er kan een niet-benaderbaar restant achterblijven dat enkel
-- opslagruimte kost. De toegang is dicht, dat is wat hier telt.

create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_ids uuid[];
  v_prefix text := p_bedrijf_id::text || '/';
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  select coalesce(array_agg(g.auth_user_id), '{}')
    into v_auth_ids
  from gebruikers g
  where g.bedrijf_id = p_bedrijf_id
    and g.auth_user_id is not null;

  -- Elke uploadfunctie zet het bedrijf_id vooraan in het pad, dus één prefix
  -- volstaat. Blijft dat zo bij een nieuwe bucket, dan hoeft hier enkel de
  -- bucketnaam bij.
  delete from storage.objects
  where bucket_id in ('inspectie-media','documenten','kennisbank',
                      'bedrijfsmiddel-fotos','actiepunt-bewijsstukken')
    and name like v_prefix || '%';

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

  delete from auth.users u
  where u.id = any(v_auth_ids)
    and not exists (select 1 from gebruikers g where g.auth_user_id = u.id)
    and not exists (select 1 from superbeheerders s where s.auth_user_id = u.id);
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
