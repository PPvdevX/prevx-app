-- Roept na elke geslaagde rapport-indiening de send-inspectie-email Edge
-- Function aan (asynchroon via pg_net), die de leidinggevenden van het bedrijf
-- mailt. Faalt de mail-aanroep, dan blijft het rapport wel gewoon opgeslagen
-- (de aanroep gebeurt na de inserts, en pg_net faalt nooit de transactie zelf
-- af aangezien het async is).

create extension if not exists pg_net;

-- Instelbaar afzenderadres per bedrijf (bv. rapporten@klantdomein.be), zodat een
-- klant zijn eigen domein kan gebruiken zodra dat geverifieerd is in Resend.
-- Valt terug op een prevx.be-adres zolang dat niet ingesteld/geverifieerd is.
alter table bedrijven add column if not exists afzender_email text;

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
      coalesce(r->'fotos', '[]'::jsonb)
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
