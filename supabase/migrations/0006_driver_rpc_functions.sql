-- SECURITY DEFINER-functies voor de chauffeurs-app (index.html), die geen
-- Supabase Auth-sessie heeft. Deze functies verifiëren zelf de PIN/bedrijf-
-- koppeling en zijn de ENIGE manier waarop de anon-rol nog bij deze data kan
-- (directe SELECT/INSERT op de tabellen is afgesloten in migratie 0002).

create or replace function public.rpc_login_chauffeur(p_pincode text)
returns table(id uuid, naam text, rol text, bedrijf_id uuid)
language sql
security definer
set search_path = public
as $$
  select g.id, g.naam, g.rol, g.bedrijf_id
  from gebruikers g
  where g.pincode = p_pincode and g.actief = true
  limit 1;
$$;

grant execute on function public.rpc_login_chauffeur(text) to anon;

create or replace function public.rpc_voertuigen(p_gebruiker_id uuid)
returns table(
  id uuid, bedrijf_id uuid, nummerplaat text, omschrijving text,
  actief boolean, aangemaakt_op timestamptz, type_id uuid, type_naam text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gebruiker gebruikers;
begin
  select * into v_gebruiker from gebruikers where id = p_gebruiker_id and actief = true;
  if not found then
    return;
  end if;

  if v_gebruiker.rol = 'chauffeur' then
    return query
      select v.id, v.bedrijf_id, v.nummerplaat, v.omschrijving, v.actief, v.aangemaakt_op, v.type_id, vt.naam
      from voertuigen v
      join gebruiker_voertuigen gv on gv.voertuig_id = v.id
      left join voertuig_types vt on vt.id = v.type_id
      where gv.gebruiker_id = p_gebruiker_id and v.actief = true;
  else
    return query
      select v.id, v.bedrijf_id, v.nummerplaat, v.omschrijving, v.actief, v.aangemaakt_op, v.type_id, vt.naam
      from voertuigen v
      left join voertuig_types vt on vt.id = v.type_id
      where v.bedrijf_id = v_gebruiker.bedrijf_id and v.actief = true;
  end if;
end;
$$;

grant execute on function public.rpc_voertuigen(uuid) to anon;

create or replace function public.rpc_checklist(p_gebruiker_id uuid, p_voertuig_id uuid)
returns table(
  sectie_id uuid, sectie_naam text, sectie_icon text, sectie_volgorde int,
  punt_id uuid, punt_omschrijving text, punt_volgorde int, punt_niveau text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_type_id uuid;
begin
  select bedrijf_id into v_bedrijf_id from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf_id is null then
    return;
  end if;

  select type_id into v_type_id from voertuigen where id = p_voertuig_id and bedrijf_id = v_bedrijf_id;
  if v_type_id is null then
    return; -- voertuig hoort niet bij dit bedrijf, of heeft (nog) geen type
  end if;

  return query
    select s.id, s.naam, s.icon, s.volgorde, p.id, p.omschrijving, p.volgorde, p.niveau
    from inspectie_secties s
    join inspectie_punten p on p.sectie_id = s.id
    join inspectie_punt_types ipt on ipt.punt_id = p.id
    where s.bedrijf_id = v_bedrijf_id and s.actief = true and p.actief = true
      and ipt.type_id = v_type_id
    order by s.volgorde, p.volgorde;
end;
$$;

grant execute on function public.rpc_checklist(uuid, uuid) to anon;

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

  return v_inspectie_id;
end;
$$;

grant execute on function public.rpc_verzend_inspectie(uuid, uuid, text, text, jsonb) to anon;
