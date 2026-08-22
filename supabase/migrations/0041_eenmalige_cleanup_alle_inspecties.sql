-- Eenmalige data-cleanup (geen schemawijziging): verwijdert alle inspecties
-- en hun resultaten, over alle bedrijven heen. Gevraagd door de gebruiker om
-- alle testdata te wissen vóór de echte opstart. Onomkeerbaar -- geen
-- backup/restore in de app zelf.
--
-- Volgorde is belangrijk: inspectie_resultaten.inspectie_id heeft geen
-- "on delete cascade" naar inspecties, dus eerst de resultaten verwijderen,
-- dan pas de inspecties zelf (anders foreign key violation, code 23503 --
-- zelfde constraint die elders in de app net bewust behouden blijft als
-- veiligheidsnet tegen per ongeluk verwijderen).
--
-- Dit wist enkel de databasekant. Eventuele foto's/handtekeningen die al via
-- Storage (i.p.v. base64) zijn opgeslagen (zie 0027_inspectie_media_bucket.sql)
-- blijven als losse bestanden in de bucket staan -- die worden hier bewust
-- niet aangeraakt, want dat vraagt Storage-API-aanroepen, niet gewoon SQL.

delete from inspectie_resultaten;
delete from inspecties;
