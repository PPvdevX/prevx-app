-- Koppelt een gebruikers-rij aan een Supabase Auth-account voor portaaltoegang.
-- Chauffeurs loggen in via PIN (zie rpc_login_chauffeur in 0006) en hebben geen
-- auth.users-rij, dus deze kolom blijft voor hen NULL.

alter table gebruikers
  add column if not exists auth_user_id uuid references auth.users(id);

create index if not exists idx_gebruikers_auth_user_id on gebruikers(auth_user_id);
