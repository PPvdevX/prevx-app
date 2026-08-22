-- Naast de bestaande notificatie (elke actieve gebruiker met rol
-- leidinggevende, zie send-inspectie-email/index.ts:55-61) kan nu ook per
-- individueel bedrijfsmiddel een losse lijst vrije e-mailadressen ingesteld
-- worden (bv. een externe wagenparkbeheerder zonder portaal-account). Bewust
-- gewoon een tekstkolom (komma-gescheiden), geen aparte tabel -- typisch maar
-- een handvol adressen per bedrijfsmiddel, geen aparte CRUD-schermen nodig.

alter table voertuigen add column if not exists notificatie_emails text;
