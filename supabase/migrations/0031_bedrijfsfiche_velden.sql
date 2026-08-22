-- Uitgebreide bedrijfsfiche op de Overzichtspagina (BTW, adres, contactpersoon,
-- paritair comité, ...). Enkel superbeheerder bewerkt dit -- de bestaande
-- superbeheerder_update_bedrijven-policy (0029) dekt elke kolom hier al, geen
-- nieuwe RLS nodig. Bewust allemaal text: puur informatieve velden, geen
-- berekeningen erop, dus geen strikte int-validatie voor aantal_werknemers.

alter table bedrijven
  add column if not exists btw_nummer text,
  add column if not exists adres text,
  add column if not exists telefoon text,
  add column if not exists contact_naam text,
  add column if not exists contact_gsm text,
  add column if not exists contact_email text,
  add column if not exists paritair_comite text,
  add column if not exists aantal_werknemers text,
  add column if not exists sector text;
