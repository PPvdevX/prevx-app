-- Fix: inspectie_resultaten.fotos is een text[]-kolom, geen jsonb. De vorige
-- versie van rpc_verzend_inspectie probeerde er rechtstreeks een jsonb-array in
-- te schrijven, wat altijd faalde zodra het effectief werd getest ("column
-- fotos is of type text[] but expression is of type jsonb").

create or replace function public.rpc_verzend_inspectie(
  p_gebruiker_id uuid,
  p_voertuig_id uuid,
  p_verdict text,
  p_handtekening text,
  p_resultaten jsonb
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

  insert into inspecties (bedrijf_id, gebruiker_id, voertuig_id, datum, tijdstip, verdict, handtekening, verzonden_op)
  values (v_bedrijf_id, p_gebruiker_id, p_voertuig_id, current_date, current_time, p_verdict, p_handtekening, now())
  returning id into v_inspectie_id;

  for r in select * from jsonb_array_elements(p_resultaten)
  loop
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
    body := jsonb_build_object('inspectie_id', v_inspectie_id)
  );

  return v_inspectie_id;
end;
$$;

grant execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb) to anon;
