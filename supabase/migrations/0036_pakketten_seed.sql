-- Seed van pakketten (0035), overgenomen uit "PrevX Startersgids v1.1"
-- (SharePoint, 02 Interne documenten) -- de drie standaardpakketten uit dat
-- document, met de PrevX Partner-formules als aparte, toewijsbare opties
-- omdat dat is wat effectief per klant wordt afgesproken.

insert into pakketten (naam,volgorde) values
  ('PrevX Partner - Light',10),
  ('PrevX Partner - Standaard',20),
  ('PrevX Partner - Intensief',30),
  ('PrevX Project',40),
  ('PrevX Vorming',50)
on conflict (naam) do nothing;
