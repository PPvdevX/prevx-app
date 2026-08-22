-- Sluit aan op 0055. Daar ging de webhook-sleutel naar Vault, maar dezelfde
-- waarde moest óók als functie-geheim WEBHOOK_SECRET blijven staan: de databank
-- stuurt hem mee, de Edge Function vergeleek met zijn omgeving. Twee plaatsen
-- die identiek moeten blijven -- lopen ze uit elkaar, dan weigert elke functie
-- stilzwijgend en komt er geen enkele mail meer aan, zonder duidelijke oorzaak.
--
-- Vanaf nu halen de Edge Functions de verwachte waarde zélf uit Vault, via hun
-- service-role-verbinding. Eén bron, niets meer te synchroniseren, en later
-- roteren is één update van het geheim in Vault.
--
-- Na deze migratie mag WEBHOOK_SECRET als functie-geheim weg (Dashboard ->
-- Edge Functions -> Secrets). Doe dat pas nadat beide functies opnieuw
-- uitgerold zijn met de nieuwe code, anders vergelijken ze even met niets.

-- Bewust een aparte functie in plaats van geheim() rechtstreeks aan
-- service_role te geven: zo kan deze weg maar één ding opvragen, niet elk
-- geheim in Vault.
create or replace function public.rpc_webhook_secret()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.geheim('webhook_secret');
$$;

revoke execute on function public.rpc_webhook_secret() from public;
grant execute on function public.rpc_webhook_secret() to service_role;
