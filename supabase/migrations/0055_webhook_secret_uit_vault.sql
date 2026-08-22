-- De webhook-sleutel die de Edge Functions afschermt stond letterlijk in vijf
-- migratiebestanden. Die bestanden zijn nooit gecommit, dus het geheim stond
-- niet in de publieke repo -- maar één `git add .` volstond om dat alsnog te
-- doen. Wie die sleutel heeft kan rechtstreeks mails laten versturen en
-- pincode-resets uitlokken.
--
-- Vanaf nu komt de sleutel uit Supabase Vault. Migratiebestanden bevatten dan
-- geen geheimen meer en zijn gewoon veilig te versioneren.
--
-- VOLGORDE -- lees dit eerst, anders vallen de e-mails stil:
--
--   1. Maak een NIEUWE sleutel aan (de oude is niet meer vertrouwd: die stond
--      in lokale bestanden en is over meerdere kanalen gepasseerd). Bijvoorbeeld
--      met: openssl rand -base64 32
--
--   2. Zet die nieuwe waarde in Vault. Voer dit apart uit in de SQL Editor --
--      NIET in een migratiebestand, want dan staat het geheim er weer in:
--
--        select vault.create_secret(
--          '<NIEUWE WAARDE>',
--          'webhook_secret',
--          'Beschermt de Edge Functions tegen aanroepen van buitenaf'
--        );
--
--   3. Zet dezelfde waarde als functie-geheim: Dashboard -> Edge Functions ->
--      Secrets -> WEBHOOK_SECRET aanpassen. De functies lezen die daar uit.
--
--   4. Voer daarna pas deze migratie uit.
--
--   5. Test: dien een inspectie in en kijk of de rapportmail toekomt.
--
-- Stap 2 en 3 moeten dezelfde waarde bevatten; anders weigeren de Edge
-- Functions elke aanroep en komt er geen enkele mail meer aan.

-- Leest een geheim uit Vault. Security definer, want vault.decrypted_secrets is
-- niet leesbaar voor anon/authenticated -- en dat hoort zo.
create or replace function public.geheim(p_naam text)
returns text
language sql
stable
security definer
set search_path = public, vault
as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_naam limit 1;
$$;

-- Postgres geeft EXECUTE standaard aan PUBLIC; intrekken zoals in 0020.
revoke execute on function public.geheim(text) from public;

-- ---------------------------------------------------------------------------
-- rpc_verzend_inspectie: identiek aan 0047, enkel de sleutel komt nu uit Vault
-- ---------------------------------------------------------------------------
create or replace function public.rpc_verzend_inspectie(
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
    -- Let op: inspectie_resultaten.fotos is text[], geen jsonb (zie 0017) --
    -- deze omzetting moet bij elke create/replace behouden blijven.
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
      'x-webhook-secret', public.geheim('webhook_secret')
    ),
    body := jsonb_build_object('inspectie_id', v_inspectie_id),
    timeout_milliseconds := 10000
  );

  return v_inspectie_id;
end;
$$;

grant execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb, timestamptz) to anon;

-- ---------------------------------------------------------------------------
-- rpc_pincode_reset_aanvragen: identiek aan 0046, sleutel nu uit Vault
-- ---------------------------------------------------------------------------
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

  -- Cryptografisch veilige code, net als in 0052: random() is een per-sessie
  -- geseede PRNG en geen bron voor iets dat toegang verleent.
  -- Drie bytes: twee zouden maar 65.536 mogelijkheden geven, en dan zou deze
  -- zescijferige code nooit boven 65535 uitkomen.
  v_code := lpad(((public.willekeurige_byte() * 65536
                 + public.willekeurige_byte() * 256
                 + public.willekeurige_byte()) % 1000000)::text, 6, '0');

  insert into pincode_reset_codes (gebruiker_id, code, verloopt_op)
  values (v_gebruiker_id, v_code, now() + interval '15 minutes');

  perform net.http_post(
    url := 'https://axziicyfcghanhvtmgsm.supabase.co/functions/v1/send-pincode-reset-email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', public.geheim('webhook_secret')
    ),
    body := jsonb_build_object('gebruiker_id', v_gebruiker_id, 'code', v_code),
    timeout_milliseconds := 10000
  );

  return true;
end;
$$;

grant execute on function public.rpc_pincode_reset_aanvragen(text, text) to anon;
