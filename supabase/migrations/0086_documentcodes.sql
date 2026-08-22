-- Documentcodes volgens PX-ADM-PRO-001 "Documentcodesysteem PrevX", met de
-- klantcode ervoor:
--
--   EU3T8U-PX-RPT-001
--
-- De klantcode vooraan sluit aan bij wat er al is -- vuurvergunningen heten
-- EU3T8U-2026-0006 -- en ze verdient haar plaats juist wanneer een document het
-- portaal verlaat: doorgestuurd, afgedrukt, opgeborgen bij de klant. Dan zegt de
-- code nog altijd bij wie het hoort en van wie het komt. Ze beantwoordt meteen
-- de vraag waar het brondocument over zwijgt: er wordt per klant genummerd, niet
-- over de hele praktijk heen. Een nieuwe klant die zijn eerste verslag als
-- PX-RPT-087 ziet, denkt dat er iets ontbreekt.
--
-- De acht types komen uit PX-ADM-PRO-001. GPP en JAP zijn toegevoegd: het
-- globaal preventieplan en het jaaractieplan bestaan bij elke klant en zijn geen
-- adviesnota's. Een codesysteem dat de twee zwaarstwegende documenten van de
-- dienstverlening niet kent, pas je binnen het jaar toch aan.
-- LET OP: PX-ADM-PRO-001 in SharePoint vermeldt die twee nog niet. Vul dat aan,
-- anders lopen het document en de praktijk uiteen.
--
-- Nummeren gebeurt met een tellertabel en niet met max()+1, om dezelfde reden
-- als bij de vergunningsnummers (0057): twee gelijktijdige uploads zouden anders
-- hetzelfde nummer krijgen.

alter table documenten
  add column if not exists code text;

create unique index if not exists idx_documenten_code on documenten (code) where code is not null;

create table if not exists document_nummers (
  bedrijf_id uuid not null references bedrijven(id),
  type text not null,
  laatste_nummer int not null default 0,
  primary key (bedrijf_id, type)
);

alter table document_nummers enable row level security;

-- Enkel via de functie hieronder; niemand hoeft deze tellers zelf te zien.
revoke all on document_nummers from anon, authenticated;

create or replace function public.volgend_documentcode(p_bedrijf_id uuid, p_type text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nummer int;
  v_klantcode text;
begin
  insert into document_nummers (bedrijf_id, type, laatste_nummer)
  values (p_bedrijf_id, upper(btrim(p_type)), 1)
  on conflict (bedrijf_id, type)
  do update set laatste_nummer = document_nummers.laatste_nummer + 1
  returning laatste_nummer into v_nummer;

  select coalesce(klantcode, 'PVX') into v_klantcode from bedrijven where id = p_bedrijf_id;

  return v_klantcode || '-PX-' || upper(btrim(p_type)) || '-' || lpad(v_nummer::text, 3, '0');
end;
$$;

revoke execute on function public.volgend_documentcode(uuid, text) from public, anon;
grant execute on function public.volgend_documentcode(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Bestaande documenten een code geven
-- ---------------------------------------------------------------------------
-- In volgorde van uploaden, zodat de nummering de werkelijke opeenvolging volgt
-- en niet de toevallige volgorde van rijen. AUD_RPT was een samengevoegd type
-- (audit- en bezoekverslag); die worden RPT, want in de praktijk zijn het
-- verslagen. Wie er een echte audit tussen heeft staan, past die ene aan.
do $$
declare
  r record;
  v_type text;
begin
  for r in
    select d.id, d.bedrijf_id,
           case upper(coalesce(d.type,'RPT'))
             when 'AUD_RPT' then 'RPT'
             else upper(coalesce(d.type,'RPT'))
           end as doeltype
    from documenten d
    where d.code is null
    order by d.bedrijf_id, d.geupload_op, d.id
  loop
    update documenten
    set code = public.volgend_documentcode(r.bedrijf_id, r.doeltype),
        type = r.doeltype
    where id = r.id;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Meenemen in het verwijderen van een bedrijf
-- ---------------------------------------------------------------------------
-- Alleen document_nummers is nieuw; de rest is 0082 ongewijzigd. De volledige
-- functie staat hier opnieuw omdat create or replace geen deelwijziging kent.
create or replace function public.rpc_verwijder_bedrijf_cascade(p_bedrijf_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_ids uuid[];
begin
  if not public.is_superbeheerder() then
    raise exception 'Enkel de superbeheerder mag een bedrijf volledig verwijderen';
  end if;

  perform set_config('prevx.bedrijf_verwijderen', 'aan', true);

  select coalesce(array_agg(g.auth_user_id), '{}')
    into v_auth_ids
  from gebruikers g
  where g.bedrijf_id = p_bedrijf_id
    and g.auth_user_id is not null;

  delete from vergunning_herinneringen
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_goedkeuring_codes
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_antwoorden
    where vergunning_id in (select id from vuurvergunningen where bedrijf_id = p_bedrijf_id);
  delete from vuurvergunningen where bedrijf_id = p_bedrijf_id;
  delete from vergunning_nummers where bedrijf_id = p_bedrijf_id;

  delete from vergunning_vraag_werktypes
    where vraag_id in (select id from vergunning_vragen where bedrijf_id = p_bedrijf_id);
  delete from vergunning_vragen where bedrijf_id = p_bedrijf_id;
  delete from werktypes where bedrijf_id = p_bedrijf_id;

  delete from pincode_reset_codes
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id);

  delete from inspectie_resultaten
    where inspectie_id in (select id from inspecties where bedrijf_id = p_bedrijf_id);
  delete from inspecties where bedrijf_id = p_bedrijf_id;

  delete from inspectie_punt_types
    where punt_id in (
      select p.id from inspectie_punten p
      join inspectie_secties s on s.id = p.sectie_id
      where s.bedrijf_id = p_bedrijf_id
    );
  delete from inspectie_sectie_types
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_punten
    where sectie_id in (select id from inspectie_secties where bedrijf_id = p_bedrijf_id);
  delete from inspectie_secties where bedrijf_id = p_bedrijf_id;

  delete from gebruiker_voertuigen
    where gebruiker_id in (select id from gebruikers where bedrijf_id = p_bedrijf_id)
       or voertuig_id in (select id from voertuigen where bedrijf_id = p_bedrijf_id);

  delete from voertuigen where bedrijf_id = p_bedrijf_id;
  delete from voertuig_types where bedrijf_id = p_bedrijf_id;

  delete from gebruikers where bedrijf_id = p_bedrijf_id;

  delete from lmra_risico_antwoorden
    where lmra_id in (select id from lmras where bedrijf_id = p_bedrijf_id);
  delete from lmras where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_lmra_risicos where bedrijf_id = p_bedrijf_id;
  delete from samenwerking where bedrijf_id = p_bedrijf_id;
  delete from keuringen where bedrijf_id = p_bedrijf_id;
  delete from actiepunten where bedrijf_id = p_bedrijf_id;
  delete from document_nummers where bedrijf_id = p_bedrijf_id;
  delete from documenten where bedrijf_id = p_bedrijf_id;
  delete from meldingen where bedrijf_id = p_bedrijf_id;
  delete from planning where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kennisbank where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_modules where bedrijf_id = p_bedrijf_id;
  delete from bedrijf_kpis where bedrijf_id = p_bedrijf_id;

  delete from bedrijven where id = p_bedrijf_id;

  delete from auth.users u
  where u.id = any(v_auth_ids)
    and not exists (select 1 from gebruikers g where g.auth_user_id = u.id)
    and not exists (select 1 from superbeheerders s where s.auth_user_id = u.id);
end;
$$;

grant execute on function public.rpc_verwijder_bedrijf_cascade(uuid) to authenticated;
