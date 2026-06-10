-- Build 3: user onboarding and profile provisioning.
--
-- This migration is additive and idempotent. It does not delete existing data.
-- It ensures auth.users and public.profiles stay in sync for new signups and
-- backfills any auth users that are missing profile rows.

alter table public.profiles
add column if not exists phone text;

alter table public.profiles
add column if not exists status text;

update public.profiles
set status = 'active'
where status is null;

alter table public.profiles
alter column status set default 'active';

alter table public.profiles
alter column status set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_status_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
    add constraint profiles_status_check
    check (
      status in (
        'active',
        'inactive',
        'pending'
      )
    );
  end if;
end $$;

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
    phone,
    role,
    status
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    new.email,
    nullif(new.raw_user_meta_data->>'phone', ''),
    'volunteer',
    'active'
  )
  on conflict (id) do update
  set
    first_name = coalesce(nullif(public.profiles.first_name, ''), excluded.first_name),
    last_name = coalesce(nullif(public.profiles.last_name, ''), excluded.last_name),
    email = coalesce(public.profiles.email, excluded.email),
    phone = coalesce(public.profiles.phone, excluded.phone),
    role = coalesce(nullif(public.profiles.role, ''), excluded.role),
    status = coalesce(nullif(public.profiles.status, ''), excluded.status);

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
  phone,
  role,
  status
)
select
  auth_users.id,
  coalesce(auth_users.raw_user_meta_data->>'first_name', ''),
  coalesce(auth_users.raw_user_meta_data->>'last_name', ''),
  auth_users.email,
  nullif(auth_users.raw_user_meta_data->>'phone', ''),
  'volunteer',
  'active'
from auth.users as auth_users
left join public.profiles
  on profiles.id = auth_users.id
where profiles.id is null;

create index if not exists idx_profiles_role_status
on public.profiles (role, status);

create index if not exists idx_profiles_email
on public.profiles (email);

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and lower(coalesce(profiles.role, '')) = 'admin'
      and coalesce(profiles.status, 'active') <> 'inactive'
  );
$$;

alter table public.profiles enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Users can view own profile'
  ) then
    create policy "Users can view own profile"
    on public.profiles
    for select
    to authenticated
    using (id = auth.uid());
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Admins can view all profiles'
  ) then
    create policy "Admins can view all profiles"
    on public.profiles
    for select
    to authenticated
    using (public.is_admin());
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'Admins can update all profiles'
  ) then
    create policy "Admins can update all profiles"
    on public.profiles
    for update
    to authenticated
    using (public.is_admin())
    with check (public.is_admin());
  end if;
end $$;

grant select, update on public.profiles to authenticated;
