-- Security Advisor meldde terecht: werktype_standaard en
-- vergunning_standaardvragen (beide uit 0050) staan in het public-schema maar
-- zonder RLS. Ik zette die wel op alle bedrijfsgebonden tabellen, maar niet op
-- deze twee sjablonen -- daar dacht ik "dat is toch geen klantdata".
--
-- Dat was de verkeerde vraag. Lezen is inderdaad weinig gevoelig: het is de
-- PrevX-standaardvragenlijst. Maar zonder RLS is een tabel in dit schema óók
-- SCHRIJFBAAR via PostgREST, en die sjablonen worden bij elke activatie naar
-- een nieuwe klant gekopieerd. Iemand die er vragen uit verwijdert, haalt ze
-- stilzwijgend weg uit de veiligheidschecklists van elke klant die daarna
-- aangesloten wordt. Dat is precies het soort schade dat je pas maanden later
-- opmerkt.
--
-- Fail closed: RLS aan, geen schrijfpolicy voor niemand. De superbeheerder mag
-- lezen zodat hij de standaardset in het dashboard kan bekijken; wijzigen
-- gebeurt via een migratie, niet via de API. rpc_vuurvergunning_activeren is
-- security definer en omzeilt RLS, dus het kopiëren blijft gewoon werken.

alter table werktype_standaard enable row level security;
alter table vergunning_standaardvragen enable row level security;

create policy superbeheerder_select_werktype_standaard on werktype_standaard for select to authenticated
  using (public.is_superbeheerder());

create policy superbeheerder_select_vergunning_standaardvragen on vergunning_standaardvragen for select to authenticated
  using (public.is_superbeheerder());
