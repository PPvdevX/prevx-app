-- E-mailveld voor notificaties (los van Supabase Auth-login). Leidinggevenden
-- gebruiken de chauffeurs-PIN om in te loggen, maar krijgen hier een e-mailadres
-- waarnaar inspectierapporten van hun bedrijf automatisch verstuurd worden.

alter table gebruikers add column if not exists email text;
