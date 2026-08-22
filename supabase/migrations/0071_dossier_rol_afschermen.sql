-- In 0030 stond deze waarschuwing bij het aanmaken van gebruikers.dossier_rol:
--
--   "Dit veld beperkt vandaag nog niets functioneel -- enkel het toekennen
--    zelf. Zodra er effectief tabbladen/acties op gegated worden, moet dit
--    veld strenger afgeschermd worden, want dan wordt het pas een echt
--    beveiligingsrelevant veld."
--
-- Dat moment is nu. Het klantgezicht dat we gaan bouwen leest dit veld om te
-- bepalen wat iemand mag zien en doen.
--
-- Het gat: portal_update_gebruikers (0013) laat élke ingelogde gebruiker van
-- een bedrijf élke gebruikersrij van dat bedrijf bijwerken, zolang het bedrijf
-- klopt. Dat was redelijk zolang die rijen alleen naam, rol en pincode
-- bevatten. Met dossier_rol erbij kan een klant-medewerker zichzelf tot
-- klant-beheerder maken. Zolang het veld niets stuurde was dat onschuldig;
-- vanaf het moment dat het wél iets stuurt, is het een weg naar meer rechten.
--
-- Bewust een trigger en geen aangepaste policy: een policy moet je aanpassen
-- op elk pad dat schrijft, en er zijn er drie (portal_update, superbeheerder_
-- update, insert). Een trigger vangt ze alle drie, ook toekomstige.

create or replace function public.blokkeer_dossier_rol_wijziging()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null buiten een ingelogde sessie: de SQL Editor, een
  -- security definer-RPC, een Edge Function met de service-role. Dat zijn
  -- allemaal wegen die al beheerderstoegang veronderstellen; daar hoort deze
  -- drempel niet. Wat we tegenhouden is de ingelogde klantgebruiker die
  -- zichzelf opwaardeert.
  if auth.uid() is null or public.is_superbeheerder() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.dossier_rol is not null then
      raise exception 'Enkel de superbeheerder kent een dossierrol toe';
    end if;
    return new;
  end if;

  -- is distinct from, niet <>: een wijziging van of naar NULL moet ook gevangen
  -- worden, en <> geeft daar NULL terug i.p.v. true.
  if new.dossier_rol is distinct from old.dossier_rol then
    raise exception 'Enkel de superbeheerder wijzigt een dossierrol';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_dossier_rol_afgeschermd on gebruikers;
create trigger trg_dossier_rol_afgeschermd
  before insert or update on gebruikers
  for each row execute function public.blokkeer_dossier_rol_wijziging();

-- Wat dit NIET afdekt: een gebruiker die al klant-beheerder is en dat blijft.
-- Deze trigger bewaakt het toekennen, niet het gebruiken. Wie de rol terecht
-- heeft, houdt hem tot jij hem weghaalt.
