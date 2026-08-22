-- Extra identificatieveld per bedrijfsmiddel. "Asset ID" (nummerplaat) en
-- "Asset" (omschrijving) bestonden al -- enkel serienummer is nieuw. Bewust
-- geen kolom hernoemd, enkel labels in de UI (zie feedback_ui_label_renames).

alter table voertuigen add column if not exists serienummer text;
