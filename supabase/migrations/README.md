# Supabase-migraties

Deze bestanden voer je uit in **Supabase Dashboard → SQL Editor**, in volgorde
(0001 → 0006), op het project `axziicyfcghanhvtmgsm`. Ik heb ze niet zelf
kunnen uitvoeren: de app gebruikt enkel de publieke ("publishable") sleutel,
en die mag geen schema-wijzigingen (DDL) doen — terecht.

## Volgorde

1. `0001_gebruikers_auth_link.sql`
2. `0002_enable_rls_policies.sql` — **let op:** vanaf dit punt heeft de
   chauffeurs-app geen directe tabeltoegang meer. Voer daarna meteen 0006 uit
   (of test niet tussentijds met index.html), anders werkt inloggen tijdelijk niet.
3. `0003_voertuig_types.sql`
4. `0004_inspectie_punten_niveau.sql`
5. `0005_inspectie_punt_types.sql`
6. `0006_driver_rpc_functions.sql`

## Verplichte handmatige stap na 0001/0002

De portaal-login (`portaal.html`) gebruikt Supabase Auth (e-mail/wachtwoord).
Om te weten welk bedrijf bij welke ingelogde gebruiker hoort, moet je het
bestaande beheerder-account koppelen aan zijn `gebruikers`-rij:

```sql
update gebruikers
set auth_user_id = (select id from auth.users where email = 'JOUW_BEHEERDER_EMAIL')
where naam = 'Peter Van Deyk';  -- of: where id = '<gebruiker-id>'
```

Doe dit voor elke bestaande Supabase Auth-login die toegang tot het portaal
moet hebben. Zonder deze koppeling ziet het portaal na de RLS-fix **geen
data meer** voor dat account (fail-closed, zoals bedoeld).

## Waarom dit zo is opgezet

- **Chauffeurs-app** logt in met enkel een PIN, zonder Supabase Auth-sessie.
  Daardoor kan RLS op basis van `auth.uid()` haar niet onderscheiden van eender
  welke anonieme bezoeker. Oplossing: alle chauffeurstoegang loopt via
  `SECURITY DEFINER`-functies (`rpc_login_chauffeur`, `rpc_voertuigen`,
  `rpc_checklist`, `rpc_verzend_inspectie`) die zelf de PIN/bedrijf-koppeling
  verifiëren. Directe tabeltoegang voor de `anon`-rol is volledig afgesloten.
- **Portaal** logt wél in via Supabase Auth, dus daar werken gewone
  RLS-policies op `bedrijf_id = huidig_bedrijf_id()`.

## Controleren of het gelukt is

Na het uitvoeren van alle migraties zou dit (met de publieke anon-key, dus
zonder in te loggen) niets meer mogen teruggeven:

```bash
curl "https://axziicyfcghanhvtmgsm.supabase.co/rest/v1/gebruikers?select=*" \
  -H "apikey: sb_publishable_qsdWjzGQnXxt9iH0B_qAjw_wIYGXR2p"
```

Verwacht resultaat: `[]` of een 401/403, niet meer de volledige gebruikerslijst
met pincodes.
