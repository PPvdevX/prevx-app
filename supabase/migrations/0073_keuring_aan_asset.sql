-- Een keuring optioneel aan een asset koppelen. Optioneel, want beide gevallen
-- komen even vaak voor: een heftruck of een laadbrug hoort bij een asset, maar
-- een EHBO-attest, de elektrische installatie of de brandblussers in het pand
-- horen dat niet. Een verplichte koppeling zou dwingen om voor die tweede soort
-- een asset te verzinnen die niet bestaat.
--
-- on delete set null, bewust niet cascade: assets worden in dit portaal écht
-- verwijderd (niet gearchiveerd). Een keuringshistoriek mag niet verdwijnen
-- omdat iemand een bestelwagen uit de lijst haalt -- de vaststelling dat er
-- gekeurd is, blijft waar. De omschrijving staat op de keuring zelf, dus na het
-- wegvallen van de koppeling is nog altijd leesbaar waar het over ging.
--
-- Ook geen aanpassing nodig aan rpc_verwijder_bedrijf_cascade: die verwijdert
-- voertuigen vóór keuringen, en dankzij set null loopt dat niet vast op de
-- verwijzing.

alter table keuringen
  add column if not exists voertuig_id uuid references voertuigen(id) on delete set null;

create index if not exists idx_keuringen_voertuig on keuringen (voertuig_id);
