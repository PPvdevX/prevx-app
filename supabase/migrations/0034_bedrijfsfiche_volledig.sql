-- Volledige klantendossier-fiche (Identificatie, Facturatie, Contract en
-- formule, Bedrijfsprofiel, Contacten, Vrije informatie), naar het ontwerp uit
-- Presentatie1.pptx. Vervangt het beperkte 9-velden-kaartje uit 0031 op het
-- Overzicht-tabblad. Enkel superbeheerder bewerkt dit -- de bestaande
-- superbeheerder_update_bedrijven-policy (0029) dekt elke kolom hier al, geen
-- nieuwe RLS nodig. Bewust allemaal text (op de contractdata na): puur
-- informatieve velden, geen berekeningen erop.
--
-- Een aantal PPTX-velden hergebruiken bewust een bestaande kolom uit 0031 i.p.v.
-- een dubbele kolom aan te maken, want het is in de praktijk hetzelfde gegeven:
--   Ondernemingsnummer*        -> btw_nummer
--   Maatschappelijke zetel*    -> adres
--   Telefoon algemeen*         -> telefoon
--   Aantal werknemers*         -> aantal_werknemers
--   NACE-code(s)*              -> sector (bestaande sector_codes-keuzelijst, 0032)
--   Hoofdcontactpersoon/Mail/Tel* -> contact_naam / contact_email / contact_gsm
-- paritair_comite (0031) komt niet voor in de PPTX-mockup maar blijft staan --
-- een net gebouwde, functionerende koppeling (0033) verwijderen zonder dat
-- gevraagd is, is nodeloos destructief.

alter table bedrijven
  -- Identificatie
  add column if not exists juridische_benaming text,
  add column if not exists handelsnaam text,
  add column if not exists vestigingsadres_1 text,
  add column if not exists vestigingsadres_2 text,
  add column if not exists vestigingsadres_3 text,
  add column if not exists vestigingsadres_4 text,
  add column if not exists vestigingsadres_5 text,
  add column if not exists email_algemeen text,
  add column if not exists website text,
  add column if not exists klantnummer text,
  add column if not exists status text,
  -- Facturatie
  add column if not exists facturatieadres text,
  add column if not exists peppol_id text,
  add column if not exists facturatie_mail_fallback text,
  add column if not exists crediteuren_contact text,
  add column if not exists crediteuren_email text,
  add column if not exists crediteuren_tel text,
  add column if not exists po_nummer text,
  add column if not exists interne_referentie text,
  add column if not exists betalingstermijn text,
  -- Contract en formule
  add column if not exists type_samenwerking text,
  add column if not exists pakket text,
  add column if not exists contract_startdatum date,
  add column if not exists contract_einddatum date,
  add column if not exists opzegtermijn text,
  add column if not exists verlengingsdatum date,
  add column if not exists tarief text,
  -- Bedrijfsprofiel (incl. EDPBW)
  add column if not exists sector_categorie text,
  add column if not exists groep text,
  add column if not exists cpbw text,
  add column if not exists interne_preventieadviseur text,
  add column if not exists niveau_preventieadviseur text,
  add column if not exists mail_preventieadviseur text,
  add column if not exists tel_preventieadviseur text,
  add column if not exists edpbw text,
  add column if not exists dossierbeheerder_edpbw text,
  add column if not exists mail_dossierbeheerder text,
  add column if not exists tel_dossierbeheerder text,
  add column if not exists arbeidsongevallenverzekeraar text,
  -- Contacten
  add column if not exists functie_hoofdcontact text,
  add column if not exists ops_contact text,
  add column if not exists functie_ops_contact text,
  add column if not exists mail_ops_contact text,
  add column if not exists tel_ops_contact text,
  add column if not exists hr_contact text,
  add column if not exists functie_hr_contact text,
  add column if not exists mail_hr_contact text,
  -- Vrije informatie
  add column if not exists vrije_informatie text;
