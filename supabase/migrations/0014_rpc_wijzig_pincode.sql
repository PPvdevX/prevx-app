-- Laat een chauffeur (zonder Supabase Auth-sessie) zelf zijn pincode wijzigen,
-- met verplichte bevestiging van de huidige pincode (voorkomt dat iemand met een
-- ontgrendelde telefoon de PIN van een collega kan overnemen).

create or replace function public.rpc_wijzig_pincode(
  p_gebruiker_id uuid,
  p_huidige_pincode text,
  p_nieuwe_pincode text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_nieuwe_pincode !~ '^[0-9]{4}$' then
    raise exception 'Pincode moet exact 4 cijfers zijn';
  end if;

  update gebruikers
  set pincode = p_nieuwe_pincode
  where id = p_gebruiker_id and pincode = p_huidige_pincode and actief = true;

  if not found then
    raise exception 'Huidige pincode is onjuist';
  end if;

  return true;
end;
$$;

grant execute on function public.rpc_wijzig_pincode(uuid, text, text) to anon;
