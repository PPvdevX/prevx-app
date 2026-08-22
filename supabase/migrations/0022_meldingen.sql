-- Meldingen: laagdrempelig meldformulier (arbeidsongeval/bijna-ongeval/vraag),
-- kanaliseert naar de adviseur i.p.v. losse mails. In tegenstelling tot
-- Actiepunten mag hier elke klantgebruiker zelf een rij aanmaken -- dat is
-- precies de bedoeling van deze module.

create table if not exists meldingen (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  type text not null,
  omschrijving text not null,
  melder_naam text,
  status text not null default 'nieuw',
  actiepunt_id uuid references actiepunten(id),
  aangemaakt_op timestamptz not null default now()
);

alter table meldingen enable row level security;

create policy portal_select_meldingen on meldingen for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_meldingen on meldingen for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_meldingen on meldingen for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_meldingen on meldingen for delete to authenticated
  using (public.is_superbeheerder());

-- Enige schrijfpad voor een gewone (niet-superbeheerder) klantgebruiker:
-- melder_naam wordt server-side bepaald, niet client-side meegegeven, zodat
-- die niet te vervalsen is (relevant bij een arbeidsongeval-melding).
create function public.rpc_meld_incident(p_type text, p_omschrijving text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf_id uuid;
  v_melder_naam text;
  v_melding_id uuid;
begin
  v_bedrijf_id := public.huidig_bedrijf_id();
  if v_bedrijf_id is null then
    raise exception 'Niet geautoriseerd';
  end if;

  select naam into v_melder_naam from gebruikers where auth_user_id = auth.uid() and actief = true limit 1;

  insert into meldingen (bedrijf_id, type, omschrijving, melder_naam)
  values (v_bedrijf_id, p_type, p_omschrijving, v_melder_naam)
  returning id into v_melding_id;

  return v_melding_id;
end;
$$;

grant execute on function public.rpc_meld_incident(text, text) to authenticated;

insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'meldingen', true from bedrijven
on conflict do nothing;
