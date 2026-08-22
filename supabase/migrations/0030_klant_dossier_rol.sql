-- Klantendossier-rol (Klant-beheerder / Klant-medewerker), los van de
-- bestaande gebruikers.rol (die blijft voor de chauffeurs-app/pre-inspectie:
-- chauffeur/leidinggevende/preventieadviseur/beheerder -- zie de naamconflict-
-- waarschuwing in het geheugen). Toegekend door de superbeheerder, niet door
-- de klant zelf.
--
-- Geen aparte RLS-policy nodig: de bestaande update-policies op gebruikers
-- (portal_update_gebruikers, superbeheerder_update_gebruikers uit 0029)
-- dekken deze kolom al. Dit veld beperkt vandaag nog niets functioneel --
-- enkel het toekennen zelf. Zodra er effectief tabbladen/acties op gegated
-- worden, moet dit veld strenger afgeschermd worden (bv. via een aparte RPC,
-- zoals bij rpc_actiepunt_bewijs_opladen), want dan wordt het pas een echt
-- beveiligingsrelevant veld.

alter table gebruikers add column if not exists dossier_rol text;
