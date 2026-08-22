-- Per-bedrijf aanpasbare weergavenamen voor de 4 vaste gebruikers.rol-waarden.
-- De rol-WAARDE zelf (chauffeur/leidinggevende/preventieadviseur/beheerder)
-- blijft overal functioneel ongewijzigd (stuurt PIN-login-gedrag, de
-- bedrijfsmiddelen-toewijzingsknop, enz.) -- enkel de tekst die getoond wordt
-- mag per klant verschillen (bv. "Bestuurder" i.p.v. "Chauffeur"). Null =
-- gebruik het standaard Nederlandse label.

alter table bedrijven
  add column if not exists rol_label_chauffeur text,
  add column if not exists rol_label_leidinggevende text,
  add column if not exists rol_label_preventieadviseur text,
  add column if not exists rol_label_beheerder text;

-- rpc_login_chauffeur breidt uit met het juiste label voor de ingelogde rol,
-- zodat de chauffeurs-app (geen sessie, kan bedrijven niet los bevragen) het
-- meteen meekrijgt bij het inloggen. Postgres laat "create or replace" geen
-- return-type-wijziging toe (extra kolom) -- eerst de oude functie droppen.
drop function if exists public.rpc_login_chauffeur(text);

create function public.rpc_login_chauffeur(p_pincode text)
returns table(id uuid, naam text, rol text, bedrijf_id uuid, rol_label text)
language sql
security definer
set search_path = public
as $$
  select g.id, g.naam, g.rol, g.bedrijf_id,
    case g.rol
      when 'chauffeur' then b.rol_label_chauffeur
      when 'leidinggevende' then b.rol_label_leidinggevende
      when 'preventieadviseur' then b.rol_label_preventieadviseur
      when 'beheerder' then b.rol_label_beheerder
    end as rol_label
  from gebruikers g
  join bedrijven b on b.id = g.bedrijf_id
  where g.pincode = p_pincode and g.actief = true
  limit 1;
$$;

grant execute on function public.rpc_login_chauffeur(text) to anon;
