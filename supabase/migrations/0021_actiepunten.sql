-- Actiepunten: de eerste echte klantendossier-module (naast pre-inspecties).
-- Enkel de superbeheerder (adviseur) maakt aan en valideert; de klant mag
-- enkel afvinken/bewijsstuk opladen. Bron-veld staat klaar voor latere
-- modules (WPI, risicoanalyse, melding) zonder schema-wijziging.

create table if not exists actiepunten (
  id uuid primary key default gen_random_uuid(),
  bedrijf_id uuid not null references bedrijven(id),
  omschrijving text not null,
  bron text not null default 'handmatig',
  verantwoordelijke text,
  deadline date,
  status text not null default 'open',
  bewijsstuk_url text,
  aangemaakt_op timestamptz not null default now()
);

alter table actiepunten enable row level security;

create policy portal_select_actiepunten on actiepunten for select to authenticated
  using (bedrijf_id = public.huidig_bedrijf_id() or public.is_superbeheerder());

create policy superbeheerder_insert_actiepunten on actiepunten for insert to authenticated
  with check (public.is_superbeheerder());

create policy superbeheerder_update_actiepunten on actiepunten for update to authenticated
  using (public.is_superbeheerder())
  with check (public.is_superbeheerder());

create policy superbeheerder_delete_actiepunten on actiepunten for delete to authenticated
  using (public.is_superbeheerder());

-- Enige schrijfpad voor een gewone (niet-superbeheerder) klantgebruiker: enkel
-- bewijsstuk opladen op een open actiepunt van het eigen bedrijf, nooit direct
-- naar 'afgesloten' (dat blijft voorbehouden aan de superbeheerder-only
-- update-policy hierboven).
create function public.rpc_actiepunt_bewijs_opladen(p_actiepunt_id uuid, p_bewijsstuk_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update actiepunten
  set bewijsstuk_url = p_bewijsstuk_url, status = 'ter_validatie'
  where id = p_actiepunt_id
    and bedrijf_id = public.huidig_bedrijf_id()
    and status = 'open';

  if not found then
    raise exception 'Actiepunt niet gevonden, hoort niet bij uw bedrijf, of staat niet op open';
  end if;
end;
$$;

grant execute on function public.rpc_actiepunt_bewijs_opladen(uuid, text) to authenticated;

insert into storage.buckets (id, name, public)
values ('actiepunt-bewijsstukken', 'actiepunt-bewijsstukken', true)
on conflict (id) do nothing;

insert into bedrijf_modules (bedrijf_id, module_key, actief)
select id, 'actiepunten', true from bedrijven
on conflict do nothing;
