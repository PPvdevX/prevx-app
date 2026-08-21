-- Opslag voor afbeeldingen in de nieuwsbrief.
--
-- ---------------------------------------------------------------------------
-- Waarom deze bucket WEL publiek is
-- ---------------------------------------------------------------------------
-- Migratie 0070 heeft vier van de vijf buckets bewust privé gezet, met als
-- argument: wie ooit een URL ziet, kan dat bestand voor altijd openen. Dat
-- argument geldt hier ook -- en toch moet deze bucket publiek.
--
-- De reden is dat een mailprogramma geen sessie heeft. Outlook, Gmail en Apple
-- Mail halen de afbeeldingen in een mail anoniem op, soms weken nadat de mail
-- verstuurd is, soms via een tussenserver (Gmail cachet elke afbeelding op zijn
-- eigen domein). Een ondertekende link met een vervaltermijn werkt daar niet:
-- die is verlopen tegen de tijd dat iemand de mail opent, en dan staat er een
-- kapot kadertje in plaats van je logo.
--
-- Dat is geen verzwakking van 0070, want wat hier in gaat is per definitie al
-- openbaar: het staat in een mail die naar honderden mensen buiten je
-- organisatie gaat, en die mail wordt doorgestuurd. Het verschil met
-- inspectiefoto's of handtekeningen is niet gradueel maar wezenlijk.
--
-- Vandaar ook een APARTE bucket en niet een mapje in een bestaande. Zo kan er
-- niets anders per ongeluk in belanden: alles wat hier ligt, is bedoeld om
-- gezien te worden.
--
-- Zelfde afweging als bij bedrijfsmiddel-fotos in 0070: bewuste uitzondering,
-- geen vergetelheid.

insert into storage.buckets (id, name, public)
values ('nieuwsbrief-media', 'nieuwsbrief-media', true)
on conflict (id) do update set public = true;

-- ---------------------------------------------------------------------------
-- Wie mag hier schrijven
-- ---------------------------------------------------------------------------
-- Anders dan bij de andere buckets loopt het uploaden hier NIET via een
-- edge-functie met de service-rol. Dat hoeft niet: er is geen bedrijf_id om te
-- controleren en geen klantscheiding om te bewaken -- enkel de superbeheerder
-- raakt hieraan. Een policy is dan eenvoudiger dan een functie, en minder code
-- is minder plek om iets fout te doen.
--
-- Lezen staat er niet bij: de bucket is publiek, dus dat loopt buiten RLS om.
-- De select-policy hieronder is er enkel zodat het portaal de lijst kan tonen.
drop policy if exists superbeheerder_select_nieuwsbrief_media on storage.objects;
create policy superbeheerder_select_nieuwsbrief_media on storage.objects for select to authenticated
using (bucket_id = 'nieuwsbrief-media' and public.is_superbeheerder());

drop policy if exists superbeheerder_insert_nieuwsbrief_media on storage.objects;
create policy superbeheerder_insert_nieuwsbrief_media on storage.objects for insert to authenticated
with check (bucket_id = 'nieuwsbrief-media' and public.is_superbeheerder());

drop policy if exists superbeheerder_update_nieuwsbrief_media on storage.objects;
create policy superbeheerder_update_nieuwsbrief_media on storage.objects for update to authenticated
using (bucket_id = 'nieuwsbrief-media' and public.is_superbeheerder())
with check (bucket_id = 'nieuwsbrief-media' and public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- Verwijderen: bewust WEL toegestaan, maar denk na voor je het doet
-- ---------------------------------------------------------------------------
-- Een afbeelding wissen breekt haar in elke reeds verzonden nieuwsbrief, ook in
-- de mailbox van iemand die hem volgende maand nog eens opent. Een verzonden
-- mail is niet meer te herstellen; het bestand waar hij naar wijst wel -- door
-- het te laten staan. Wis dus enkel wat nooit verstuurd is.
drop policy if exists superbeheerder_delete_nieuwsbrief_media on storage.objects;
create policy superbeheerder_delete_nieuwsbrief_media on storage.objects for delete to authenticated
using (bucket_id = 'nieuwsbrief-media' and public.is_superbeheerder());
