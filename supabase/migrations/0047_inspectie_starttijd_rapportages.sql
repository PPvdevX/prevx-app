-- Voegt een starttijdstip toe aan inspecties (moment waarop de chauffeur het
-- voertuig koos en de checklist opende), nodig voor de nieuwe Rapportages-tab
-- om verdacht korte inspectieduur te kunnen detecteren.

alter table public.inspecties add column if not exists gestart_op timestamptz;

comment on column public.inspecties.gestart_op is
  'Tijdstip waarop de chauffeur het voertuig koos en de checklist opende (pre-insp.html). Gebruikt door de Rapportages-tab om verdacht korte inspectieduur te detecteren. Null voor inspecties van vóór migratie 0047.';

-- p_gestart_op toevoegen wijzigt de argumenttype-signatuur van de functie,
-- niet enkel de body. Een kale "create or replace function" met een andere
-- argumentenlijst maakt in Postgres een NIEUWE, overlappende overload i.p.v.
-- de bestaande te vervangen (functie-identiteit = naam + argtypes) -- de oude
-- 5-argumenten-versie zou dan stilzwijgend blijven bestaan en gegrant blijven
-- aan anon. Daarom defensief eerst de exacte oude signatuur droppen, zoals
-- ook gedaan in migratie 0042/de retry ervan (toen ging het mis met een
-- return-type-wijziging; hier is het de argumentenlijst, risico is analoog).
drop function if exists public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb);

create function public.rpc_verzend_inspectie(
  p_gebruiker_id uuid,
  p_voertuig_id uuid,
  p_verdict text,
  p_handtekening text,
  p_resultaten jsonb,
  p_gestart_op timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_inspectie_id uuid;
  r jsonb;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  if not exists (select 1 from voertuigen where id = p_voertuig_id and bedrijf_id = v_bedrijf_id) then
    raise exception 'Voertuig hoort niet bij dit bedrijf';
  end if;

  insert into inspecties (bedrijf_id, gebruiker_id, voertuig_id, datum, tijdstip, verdict, handtekening, verzonden_op, gestart_op)
  values (v_bedrijf_id, p_gebruiker_id, p_voertuig_id, current_date, current_time, p_verdict, p_handtekening, now(), p_gestart_op)
  returning id into v_inspectie_id;

  for r in select * from jsonb_array_elements(p_resultaten)
  loop
    -- Let op: inspectie_resultaten.fotos is text[], geen jsonb (zie
    -- 0017_fix_inspectie_resultaten_fotos_type.sql) -- deze omzetting hieronder
    -- moet bij elke create/replace van deze functie behouden blijven.
    insert into inspectie_resultaten (inspectie_id, punt_id, status, opmerking, fotos)
    values (
      v_inspectie_id,
      (r->>'punt_id')::uuid,
      r->>'status',
      r->>'opmerking',
      array(select jsonb_array_elements_text(coalesce(r->'fotos', '[]'::jsonb)))
    );
  end loop;

  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-inspectie-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '<stond hier; sinds migratie 0055 komt de sleutel uit Vault en is deze waarde vervangen>'
    ),
    body := jsonb_build_object('inspectie_id', v_inspectie_id),
    timeout_milliseconds := 10000
  );

  return v_inspectie_id;
end;
$$;

grant execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb, timestamptz) to anon;
