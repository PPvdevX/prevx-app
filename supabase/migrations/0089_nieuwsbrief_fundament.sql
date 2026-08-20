-- Nieuwsbrief, deel 1: tabellen, afscherming en de publieke aan-/afmeldweg.
--
-- Dit is de eerste van vier stappen. Hier staat alleen wat draagt: wie er
-- abonnee is, wat een campagne is, en wie welke mail kreeg. Het versturen zelf
-- (deel 2) en het portaalscherm (deel 3) komen erbovenop.
--
-- ---------------------------------------------------------------------------
-- Waarom dit geen bedrijfsmodule is
-- ---------------------------------------------------------------------------
-- Elke andere tabel in dit schema hangt aan een bedrijf_id, want elke andere
-- module gaat over een klant. Een nieuwsbriefabonnee is precies het
-- tegenovergestelde: meestal iemand die nog geen klant is. Er is dus geen
-- bedrijf om aan te hangen en geen rij in bedrijf_modules -- dit is
-- platformbreed en enkel voor de superbeheerder, zoals de codelijsten.
--
-- Praktisch gevolg om te onthouden: rpc_verwijder_bedrijf_cascade (0086) raakt
-- deze tabellen bewust niet aan. Een klant verwijderen wist zijn nieuwsbrief-
-- inschrijving niet, want die stond los van zijn dossier. Wie zich uitschrijft
-- doet dat via de link in de mail, niet door klant-af te worden.
--
-- ---------------------------------------------------------------------------
-- Waarom afmelden een status is en geen delete
-- ---------------------------------------------------------------------------
-- De verleiding is groot om een afgemelde abonnee gewoon te wissen. Doe dat
-- niet: bij de eerstvolgende import of hersteloperatie staat hij er weer in en
-- krijgt hij opnieuw mail die hij uitdrukkelijk geweigerd heeft. De rij met
-- status 'afgemeld' is de blokkeerlijst. Echt wissen kan wel, bewust en apart,
-- via rpc_nieuwsbrief_wissen onderaan -- dat is het recht op vergetelheid, een
-- ander geval dan een uitschrijving.

-- ---------------------------------------------------------------------------
-- Tokens
-- ---------------------------------------------------------------------------
-- Zelfde afweging als in 0052: willekeur uit gen_random_uuid(), want dat zit
-- sinds Postgres 13 in de kern en is cryptografisch sterk. Niet
-- gen_random_bytes() (pgcrypto staat niet op het zoekpad) en zeker niet
-- random() (per sessie geseed, geen bron voor iets dat toegang verleent).
--
-- Twee UUID's aan elkaar: 64 hextekens. Dit token staat in een e-mail en
-- daarmee in de logs van elke tussenliggende mailserver, dus het mag nooit
-- meer verlenen dan het hier doet -- uitschrijven of bevestigen, niets anders.
create or replace function public.nieuwsbrief_token()
returns text
language sql
volatile
as $$
  select replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
$$;

-- Postgres geeft EXECUTE standaard aan PUBLIC; intrekken zoals in 0020 en 0052.
revoke execute on function public.nieuwsbrief_token() from public;

-- Maar anders dan willekeurige_byte() in 0052 wordt deze functie gebruikt als
-- kolomstandaardwaarde hieronder, en die wordt uitgevoerd met de rechten van
-- wie de rij invoegt -- niet die van de eigenaar. Zonder deze twee grants
-- faalt elke insert met "permission denied for function nieuwsbrief_token":
-- de superbeheerder voegt in als authenticated, de edge-functie als
-- service_role.
--
-- Dat verzwakt niets. De functie geeft willekeur terug en neemt geen invoer;
-- ze uitvoeren leert je niets over het token van iemand anders. anon blijft er
-- wel buiten, want anon heeft op deze tabellen sowieso niets te zoeken.
grant execute on function public.nieuwsbrief_token() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Abonnees
-- ---------------------------------------------------------------------------
create table if not exists nieuwsbrief_abonnees (
  id uuid primary key default gen_random_uuid(),

  -- Altijd in kleine letters. Dat is geen kosmetiek: het laat de edge-functie
  -- toe om met een gewone gelijkheid te zoeken in plaats van met ilike, en in
  -- een ilike-patroon is _ een jokerteken. Onderstrepingstekens zitten in echte
  -- e-mailadressen, dus "ja_@x.be" zou de rij van "jan@x.be" opleveren en die
  -- van iemand anders overschrijven. Deze constraint sluit dat pad af, ook voor
  -- rijen die ooit met de hand of via een import binnenkomen.
  email text not null check (email = lower(email)),
  naam text,
  bedrijfsnaam text,

  -- bevestiging_open : heeft zich aangemeld, bevestigingsmail verstuurd
  -- aangemeld        : bevestigd, mag mail krijgen
  -- afgemeld         : heeft zelf uitgeschreven
  -- bounce           : adres bestaat niet (hard bounce), door de webhook gezet
  -- klacht           : heeft ons als spam gemarkeerd, door de webhook gezet
  status text not null default 'bevestiging_open'
    check (status in ('bevestiging_open', 'aangemeld', 'afgemeld', 'bounce', 'klacht')),

  -- Waar de aanmelding vandaan kwam ('website', 'piloot', 'handmatig', ...).
  -- Vul dit altijd in: bij een klacht is de eerste vraag "hoe kwam dit adres
  -- hier?", en die vraag beantwoord je niet achteraf.
  bron text,

  -- Het bewijs van toestemming. toestemming_op wordt gezet op het moment van
  -- bevestigen, niet van aanmelden -- pas dan heeft iemand aantoonbaar zelf
  -- iets gedaan. toestemming_bewijs bewaart het IP-adres van die bevestiging.
  toestemming_op timestamptz,
  toestemming_bewijs text,

  -- Stabiel, voor de uitschrijflink in elke mail. Verandert nooit.
  token text not null default public.nieuwsbrief_token(),

  -- Eenmalig, voor de bevestigingslink. Wordt op nul gezet zodra hij gebruikt
  -- is, zodat dezelfde link niet later nog eens werkt.
  bevestig_token text default public.nieuwsbrief_token(),
  bevestig_verloopt_op timestamptz default now() + interval '7 days',

  -- Wanneer de laatste bevestigingsmail vertrok. Dit is de rem op het
  -- aanmeldformulier: dat staat open op het internet, en zonder rem kan iemand
  -- het adres van een ander honderd keer indienen en zo honderd mails
  -- veroorzaken. De edge-functie stuurt hoogstens eens per tien minuten een
  -- nieuwe bevestiging naar hetzelfde adres.
  bevestiging_gestuurd_op timestamptz,

  aangemaakt_op timestamptz not null default now(),
  afgemeld_op timestamptz,
  laatste_mail_op timestamptz
);

-- E-mailadressen zijn hoofdletterongevoelig genoeg om "Jan@X.be" en "jan@x.be"
-- als een persoon te behandelen; twee rijen betekent twee keer dezelfde mail.
create unique index if not exists idx_nieuwsbrief_abonnees_email
  on nieuwsbrief_abonnees (lower(email));

create unique index if not exists idx_nieuwsbrief_abonnees_token
  on nieuwsbrief_abonnees (token);

create index if not exists idx_nieuwsbrief_abonnees_bevestig
  on nieuwsbrief_abonnees (bevestig_token) where bevestig_token is not null;

-- ---------------------------------------------------------------------------
-- Campagnes
-- ---------------------------------------------------------------------------
create table if not exists nieuwsbrief_campagnes (
  id uuid primary key default gen_random_uuid(),
  onderwerp text not null,

  -- Het regeltje dat Gmail en Outlook naast het onderwerp tonen. Laat je het
  -- leeg, dan tonen ze de eerste woorden van de mail -- meestal iets nutteloos
  -- als "Bekijk deze mail in je browser".
  voorbeeldtekst text,

  html text,

  -- De platte-tekstversie hoort erbij, niet als bijzaak: een mail zonder
  -- text/plain-deel scoort slechter bij spamfilters, en sommige mensen lezen
  -- nog steeds zo.
  tekst text,

  -- klad      : in opbouw, mag niet verzonden worden
  -- wachtrij  : ontvangers klaargezet, klaar om te vertrekken
  -- bezig     : de verzendfunctie werkt de wachtrij af
  -- verzonden : niets meer in de wachtrij
  -- gestopt   : handmatig stilgelegd
  status text not null default 'klad'
    check (status in ('klad', 'wachtrij', 'bezig', 'verzonden', 'gestopt')),

  aangemaakt_op timestamptz not null default now(),
  aangemaakt_door uuid,
  verzonden_op timestamptz
);

-- ---------------------------------------------------------------------------
-- Verzendingen: een rij per ontvanger per campagne
-- ---------------------------------------------------------------------------
-- Dit is de tabel die het vaakst wordt overgeslagen en het meest oplevert.
-- Zonder deze rijen weet je na een half mislukte verzending niet wie wel mail
-- kreeg, en durf je niet opnieuw te sturen. Met deze rijen is opnieuw sturen
-- gewoon "doe de wachtrij nog eens" en krijgt niemand dubbele post.
create table if not exists nieuwsbrief_verzendingen (
  id uuid primary key default gen_random_uuid(),
  campagne_id uuid not null references nieuwsbrief_campagnes(id) on delete cascade,

  -- on delete set null, want een gewiste abonnee mag het verzendlogboek niet
  -- meeslepen: hoeveel mail er vertrok blijft een feit.
  abonnee_id uuid references nieuwsbrief_abonnees(id) on delete set null,

  -- Momentopname van het adres op het ogenblik van verzenden. Wijzigt iemand
  -- later zijn adres, dan blijft hier staan waar de mail echt heen ging.
  email text not null,

  status text not null default 'wachtrij'
    check (status in ('wachtrij', 'verzonden', 'mislukt', 'bounce', 'klacht')),

  -- Het id dat Resend teruggeeft. Hierop matcht de webhook zijn gebeurtenissen.
  resend_id text,
  fout text,
  verzonden_op timestamptz,

  -- De grendel tegen dubbele post: klaarzetten mag je zo vaak herhalen als je
  -- wil, tweemaal dezelfde ontvanger in dezelfde campagne kan niet.
  unique (campagne_id, abonnee_id)
);

-- Waar de verzendfunctie elke ronde op zoekt.
create index if not exists idx_nieuwsbrief_verzendingen_wachtrij
  on nieuwsbrief_verzendingen (campagne_id) where status = 'wachtrij';

-- Waar de webhook op zoekt.
create index if not exists idx_nieuwsbrief_verzendingen_resend
  on nieuwsbrief_verzendingen (resend_id) where resend_id is not null;

-- ---------------------------------------------------------------------------
-- Afscherming
-- ---------------------------------------------------------------------------
-- Alle drie enkel voor de superbeheerder. De publieke kant (aanmelden,
-- bevestigen, uitschrijven) loopt NIET via anon-rechten op deze tabellen maar
-- via de edge-functie 'nieuwsbrief', die met de service-rol werkt. Anders dan
-- bij de chauffeurs-RPC's is er hier geen reden om anon iets te geven: de
-- website hoeft nooit een abonneelijst te lezen, enkel een adres toe te voegen
-- of een rij op afgemeld te zetten. Hoe minder anon mag, hoe minder er te
-- misbruiken valt -- en een abonneelijst is precies wat een spammer wil.
alter table nieuwsbrief_abonnees enable row level security;
alter table nieuwsbrief_campagnes enable row level security;
alter table nieuwsbrief_verzendingen enable row level security;

revoke all on nieuwsbrief_abonnees from anon;
revoke all on nieuwsbrief_campagnes from anon;
revoke all on nieuwsbrief_verzendingen from anon;

create policy superbeheerder_alles_abonnees on nieuwsbrief_abonnees for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_alles_campagnes on nieuwsbrief_campagnes for all to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

-- Enkel lezen: verzendingen worden gezet door rpc_nieuwsbrief_klaarzetten en
-- door de verzendfunctie. Een logboek dat de schrijver zelf mag bijwerken, is
-- geen logboek.
create policy superbeheerder_select_verzendingen on nieuwsbrief_verzendingen for select to authenticated
  using (public.is_superbeheerder());

-- ---------------------------------------------------------------------------
-- De wachtrij vullen
-- ---------------------------------------------------------------------------
-- Aparte stap, met opzet: tussen "klaarzetten" en "versturen" zit het moment
-- waarop je ziet hoeveel mensen het gaan krijgen en je nog kan terugkrabbelen.
-- Herhalen is veilig -- de unique-index hierboven vangt dubbels op, dus wie
-- zich aanmeldde nadat je de eerste keer klaarzette, wordt gewoon toegevoegd.
create or replace function public.rpc_nieuwsbrief_klaarzetten(p_campagne_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_aantal int;
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder beheert de nieuwsbrief';
  end if;

  select status into v_status from nieuwsbrief_campagnes where id = p_campagne_id;
  if v_status is null then
    raise exception 'Onbekende campagne';
  end if;
  if v_status = 'verzonden' then
    raise exception 'Deze campagne is al verzonden';
  end if;

  insert into nieuwsbrief_verzendingen (campagne_id, abonnee_id, email)
  select p_campagne_id, a.id, a.email
  from nieuwsbrief_abonnees a
  where a.status = 'aangemeld'
  on conflict (campagne_id, abonnee_id) do nothing;

  get diagnostics v_aantal = row_count;

  update nieuwsbrief_campagnes set status = 'wachtrij'
  where id = p_campagne_id and status in ('klad', 'gestopt');

  return v_aantal;
end;
$$;

revoke execute on function public.rpc_nieuwsbrief_klaarzetten(uuid) from public, anon;
grant execute on function public.rpc_nieuwsbrief_klaarzetten(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Echt wissen (recht op vergetelheid)
-- ---------------------------------------------------------------------------
-- Uitdrukkelijk iets anders dan uitschrijven. Wie hierom vraagt, wil uit de
-- lijst verdwijnen -- ook uit de blokkeerlijst. Het gevolg moet je erbij
-- zeggen: schrijft hij zich later opnieuw in, dan is er niets meer dat hem
-- tegenhoudt, want we hebben net weggegooid wat dat zou doen. Daarom is dit
-- een aparte handeling en niet de knop waar je per ongeluk op duwt.
--
-- Het verzendlogboek blijft bestaan met '(gewist)' als adres: dat er op een
-- dag 340 mails vertrokken, is een boekhoudkundig feit dat losstaat van de
-- vraag naar wie ze gingen.
create or replace function public.rpc_nieuwsbrief_wissen(p_abonnee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder beheert de nieuwsbrief';
  end if;

  update nieuwsbrief_verzendingen set email = '(gewist)' where abonnee_id = p_abonnee_id;
  delete from nieuwsbrief_abonnees where id = p_abonnee_id;
end;
$$;

revoke execute on function public.rpc_nieuwsbrief_wissen(uuid) from public, anon;
grant execute on function public.rpc_nieuwsbrief_wissen(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Na deze migratie: wat er nog met de hand moet gebeuren
-- ---------------------------------------------------------------------------
-- 1. In Resend een apart verzenddomein aanmaken voor de nieuwsbrief en de
--    DNS-records bij Cloudflare zetten. Neem NIET het domein waarlangs de
--    rapporten en de inloglinks vertrekken -- dat is de hele reden waarom dit
--    apart staat.
--
-- 2. Functie-geheimen zetten (Dashboard > Edge Functions > Secrets):
--
--      NIEUWSBRIEF_AFZENDER    bv. PrevX <nieuws@prevx.be>
--      NIEUWSBRIEF_ANTWOORD    een adres dat iemand leest; leeg mag ook
--      SITE_URL                https://prevx.be
--      RESEND_WEBHOOK_SECRET   de whsec_-waarde uit Resend, stap 4
--
--    RESEND_API_KEY staat er al voor de andere functies.
--
-- 3. De twee functies uitrollen, allebei zonder JWT-controle -- de ene wordt
--    door bezoekers aangeroepen, de andere door Resend, en geen van beide kan
--    een Supabase-token meesturen:
--
--      supabase functions deploy nieuwsbrief --no-verify-jwt
--      supabase functions deploy nieuwsbrief-webhook --no-verify-jwt
--
--    Controleer die schakelaar na ELKE herimplementatie: hij springt terug aan
--    en dan krijgt iedereen UNAUTHORIZED_NO_AUTH_HEADER.
--
-- 4. In Resend een webhook aanmaken naar
--    https://<project>.supabase.co/functions/v1/nieuwsbrief-webhook
--    met minstens de gebeurtenissen email.bounced en email.complained.
--
-- 5. Jezelf als eerste abonnee inschrijven en de hele weg aflopen:
--    aanmelden > bevestigingsmail > bevestigen > uitschrijven. Duurt vijf
--    minuten en vangt alles wat hierboven verkeerd getypt staat.
