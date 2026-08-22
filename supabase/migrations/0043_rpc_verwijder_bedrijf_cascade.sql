-- "Verwijder bedrijf" bleek keer op keer tegen een nieuwe, onzichtbare
-- foreign-key-blokkade te lopen (eerst bedrijf_modules, dan planning, ...) --
-- elke klantendossier-module (actiepunten/documenten/meldingen/planning/
-- bedrijf_kennisbank) heeft immers geen eigen "verwijderen"-knop. Gebruiker
-- bevestigde: bij een expliciete "bedrijf verwijderen" mag dit een echte
-- cascade zijn -- alles wat bij dit bedrijf hoort in één keer weg, i.p.v.
-- één voor één telkens een nieuwe tabel moeten opruimen.
--
-- Als één SQL-functie (security definer, één transactie) i.p.v. losse
-- client-side deletes: atomair (alles of niets), en één centrale plek om de
-- juiste volgorde te bewaken als er later een nieuwe bedrijf_id-tabel bijkomt.
-- Volgorde: eerst de "bladeren" (resultaten, koppeltabellen), dan hun ouders,
-- tot uiteindelijk het bedrijf zelf.

create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

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

  delete from bedrijven where id = p_bedrijf_id;
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
