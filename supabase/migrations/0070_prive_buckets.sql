-- Vier van de vijf buckets gaan van publiek naar privé.
--
-- Publiek betekent hier niet "vindbaar" -- opsommen wordt door RLS geweigerd en
-- elk pad bestaat uit twee UUID's, dus raden kan niet. Het betekent: wie ooit
-- een URL ziet, kan dat bestand voor altijd openen, zonder in te loggen, en dat
-- recht is niet meer in te trekken. Bij inspectiefoto's, klantdocumenten en
-- vooral handtekeningen is dat te veel weggegeven voor te weinig gemak.
--
-- bedrijfsmiddel-fotos blijft bewust WEL publiek. Die foto's toont de
-- chauffeurs-app op de keuzekaarten, en die app heeft geen sessie -- ze kan dus
-- geen tijdelijke link ondertekenen. Dat oplossen vraagt een nieuw eindpunt dat
-- aan anonieme aanroepers ondertekende links uitdeelt, en dat voegt meer
-- aanvalsoppervlak toe dan het wegneemt voor een foto van een bestelwagen
-- waar geen mens op staat. Bewuste uitzondering, geen vergetelheid.
--
-- Let op: vandaag bestaat er GEEN ENKELE select-policy op storage.objects. Al
-- het lezen liep via de publieke vlag. Privé zetten zonder die policies zou
-- betekenen dat ook het portaal niets meer kan tonen.

update storage.buckets set public = false
where id in ('inspectie-media','documenten','kennisbank','actiepunt-bewijsstukken');

-- Lezen (en dus ondertekenen) mag wie bij het bedrijf hoort waarvan het pad
-- begint met dat bedrijf_id -- zo legt elke uploadfunctie het aan -- plus de
-- superbeheerder, die dossiers van klanten moet kunnen openen.
drop policy if exists portal_select_prive_media on storage.objects;
create policy portal_select_prive_media on storage.objects for select to authenticated
using (
  bucket_id in ('inspectie-media','documenten','kennisbank','actiepunt-bewijsstukken')
  and (
    public.is_superbeheerder()
    or name like public.huidig_bedrijf_id()::text || '/%'
  )
);

-- De uploadfuncties draaien met de service-role en gaan om RLS heen, dus er is
-- geen insert-policy nodig. Verwijderen gebeurt in rpc_verwijder_bedrijf_cascade
-- (0069), ook security definer. Bewust niets extra's opengezet.
