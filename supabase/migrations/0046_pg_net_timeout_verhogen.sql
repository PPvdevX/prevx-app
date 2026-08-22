-- pg_net.http_post() gebruikt standaard maar 1 seconde timeout. De
-- send-inspectie-email-functie doet 3 databank-query's + een Resend-aanroep
-- na elkaar, wat die seconde makkelijk overschrijdt (vooral bij een cold
-- start) -- pg_net brak de verbinding dan af vóór de functie klaar was
-- ("EarlyDrop" in de Edge Function-logs), zonder dat de e-mail ooit
-- daadwerkelijk faalde qua inhoud/rechten. Fix: expliciet een ruimere
-- timeout doorgeven aan elke net.http_post-aanroep.
--
-- Let op: de fotos-kolom op inspectie_resultaten is text[], geen jsonb (zie
-- 0017_fix_inspectie_resultaten_fotos_type.sql) -- de "array(select
-- jsonb_array_elements_text(...))"-omzetting hieronder komt uit die eerdere
-- fix en moet bij elke create-or-replace van deze functie behouden blijven.

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
    body := jsonb_build_object('inspectie_id', v_inspectie_id),
    timeout_milliseconds := 10000
  );

  return v_inspectie_id;
end;
$$;

grant execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb) to anon;

-- Zelfde potentiële probleem in de pincode-reset-mail, preventief meteen mee opgelost.
create or replace function public.rpc_pincode_reset_aanvragen(p_naam text, p_email text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gebruiker_id uuid;
  v_code text;
begin
  select id into v_gebruiker_id
  from gebruikers
  where actief = true
    and lower(trim(naam)) = lower(trim(p_naam))
    and email is not null
    and lower(trim(email)) = lower(trim(p_email))
  limit 1;

  if v_gebruiker_id is null then
    return false;
  end if;

  v_code := lpad(floor(random() * 1000000)::text, 6, '0');

  insert into pincode_reset_codes (gebruiker_id, code, verloopt_op)
  values (v_gebruiker_id, v_code, now() + interval '15 minutes');

  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-pincode-reset-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', '<stond hier; sinds migratie 0055 komt de sleutel uit Vault en is deze waarde vervangen>'
    ),
    body := jsonb_build_object('gebruiker_id', v_gebruiker_id, 'code', v_code),
    timeout_milliseconds := 10000
  );

  return true;
end;
$$;

grant execute on function public.rpc_pincode_reset_aanvragen(text, text) to anon;
