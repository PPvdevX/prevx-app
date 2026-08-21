-- ===========================================================================
-- 0099_vib_bucket.sql
-- Opslag voor de veiligheidsinformatiebladen
-- ===========================================================================
-- WAAROM DEZE BUCKET PUBLIEK IS, EN DE ANDERE VIER NIET
--
-- 0070 zette vier buckets op privé en liet er één publiek: bedrijfsmiddel-fotos.
-- De reden daar gold niet de gevoeligheid maar de app: de chauffeurs-app heeft
-- geen sessie, dus ze kan geen tijdelijke link ondertekenen. Een privébucket is
-- voor haar onbereikbaar.
--
-- Voor het VIB speelt precies dezelfde beperking -- en dit keer is het de kern
-- van de module. Iemand staat aan de machine met een bus in zijn hand en wil
-- weten wat erin zit. Kan de app dat blad niet openen, dan is de module een
-- inventaris voor het bureau en verandert er op de vloer niets.
--
-- Het verschil met de andere vier is bovendien dat een VIB naar zijn aard geen
-- klantgegeven is. Het is een blad dat de leverancier verplicht meelevert, dat
-- bij elke afnemer van datzelfde product identiek is, en dat fabrikanten zelf op
-- hun website publiceren. Er staat niets in over déze klant: geen namen, geen
-- vaststellingen, geen handtekeningen. Wat in de vier andere buckets staat --
-- foto's van vaststellingen, verslagen, bewijsstukken, handtekeningen -- is dat
-- allemaal wél.
--
-- Wat publiek hier betekent: wie de URL heeft, kan het blad openen. Opsommen kan
-- niet (RLS weigert dat), en het pad bestaat uit twee UUID's, dus raden kan
-- evenmin. Voor een document dat de fabrikant zelf publiceert, is dat een prijs
-- die niets kost.
--
-- Blijkt later dat een klant er tóch iets vertrouwelijks in legt -- een intern
-- werkvoorschrift bijvoorbeeld -- dan hoort dat in Documenten, niet hier.

insert into storage.buckets (id, name, public)
values ('vib', 'vib', true)
on conflict (id) do nothing;

-- Uploaden gebeurt door de Edge Function upload-vib met de service-role, die om
-- RLS heen gaat; verwijderen loopt via de cascade. Daarom geen insert- of
-- delete-policy: niets extra opengezet, net als bij de andere buckets.

do $$
declare
  r record;
begin
  raise notice '--- buckets ---';
  for r in select id, public from storage.buckets order by id loop
    raise notice '  %  %', rpad(r.id, 30), case when r.public then 'publiek' else 'prive' end;
  end loop;
end
$$;
