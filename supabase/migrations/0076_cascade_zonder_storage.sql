-- rpc_verwijder_bedrijf_cascade wiste sinds 0069 ook de bestanden, met een
-- rechtstreekse delete op storage.objects. Dat werkt niet meer: Supabase
-- weigert dat nu met "Direct deletion from storage tables is not allowed. Use
-- the Storage API instead."
--
-- Het gevolg was erger dan het probleem dat 0069 oploste: die delete staat
-- vooraan in de functie, dus een bedrijf verwijderen brak volledig af. Geen
-- rijen weg, geen bestanden weg, alleen een foutmelding.
--
-- De databank haalt hier dus haar handen van af. Het opruimen van bestanden
-- verhuist naar een Edge Function die de Storage-API gebruikt zoals het hoort
-- (supabase/functions/verwijder-bedrijf). Die roept daarna deze functie aan.
--
-- Wat blijft staan uit 0069: dat de bestanden weg MOETEN. Een klant die vraagt
-- zijn dossier te verwijderen, hoort niet achteraf te ontdekken dat de
-- handtekeningen van zijn chauffeurs nog online staan. Alleen de weg ernaartoe
-- verandert.

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

  delete from samenwerking where bedrijf_id = p_bedrijf_id;
  delete from keuringen where bedrijf_id = p_bedrijf_id;
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
