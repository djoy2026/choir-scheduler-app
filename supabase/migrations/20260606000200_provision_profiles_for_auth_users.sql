-- Ensure every Supabase auth user has a matching public.profiles row.
--
-- This fixes users who exist in auth.users but are missing from profiles,
-- which causes .single() profile lookups to fail with PGRST116.

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (
    id,
    first_name,
    last_name,
    email,
    role
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'volunteer')
  )
  on conflict (id) do update
  set
    email = coalesce(public.profiles.email, excluded.email),
    role = coalesce(nullif(public.profiles.role, ''), excluded.role);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;

create trigger on_auth_user_created_profile
after insert on auth.users
for each row
execute function public.handle_new_auth_user_profile();

insert into public.profiles (
  id,
  first_name,
  last_name,
  email,
  role
)
select
  auth_users.id,
  coalesce(auth_users.raw_user_meta_data->>'first_name', ''),
  coalesce(auth_users.raw_user_meta_data->>'last_name', ''),
  auth_users.email,
  coalesce(auth_users.raw_user_meta_data->>'role', 'volunteer')
from auth.users as auth_users
left join public.profiles
  on profiles.id = auth_users.id
where profiles.id is null;
