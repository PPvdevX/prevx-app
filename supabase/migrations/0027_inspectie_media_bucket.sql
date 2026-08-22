-- Storage-bucket voor foto's en handtekening uit de chauffeurs-app, i.p.v. de
-- huidige base64-opslag rechtstreeks in inspectie_resultaten.fotos/
-- inspecties.handtekening (inefficiënt: ~33% groter, sleept mee in elke query
-- en in de e-mailnotificatie). Geen RLS-policies nodig: de upload-functie
-- schrijft met service_role, en rpc_verzend_inspectie (al security definer)
-- blijft de enige weg naar de tabellen zelf.

insert into storage.buckets (id, name, public)
values ('inspectie-media', 'inspectie-media', true)
on conflict (id) do nothing;
