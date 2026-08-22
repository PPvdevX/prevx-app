-- De oude vrije-tekst 'type'-kolom op voertuigen (van vóór voertuig_types/
-- type_id, zie 0003_voertuig_types.sql) staat nog steeds "not null", maar
-- noch nieuwBedrijfsmiddel() noch de bulk-import vult dat oude veld nog in --
-- ze werken uitsluitend met type_id. Elke nieuwe rij (handmatig of via
-- bulk-import) botste daardoor op de not-null-constraint.
--
-- Kolom blijft bewust bestaan (rollback-veiligheid, zoals 0003 al aangaf),
-- enkel de verplichting wordt losgelaten.

alter table voertuigen alter column type drop not null;
