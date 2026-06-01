-- Upgrade existing team-specific service role definitions.
-- The live team_roles table already exists with:
-- id, team_id, role_name, display_order, created_at.
-- It does not seed production data and does not modify existing service slots.

alter table public.team_roles
add column if not exists quantity integer;

update public.team_roles
set quantity = 1
where quantity is null;

alter table public.team_roles
alter column quantity set default 1;

alter table public.team_roles
alter column quantity set not null;

alter table public.team_roles
add column if not exists is_active boolean;

update public.team_roles
set is_active = true
where is_active is null;

alter table public.team_roles
alter column is_active set default true;

alter table public.team_roles
alter column is_active set not null;

alter table public.team_roles
add column if not exists updated_at timestamptz;

update public.team_roles
set updated_at = created_at
where updated_at is null;

alter table public.team_roles
alter column updated_at set default now();

alter table public.team_roles
alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'team_roles_role_name_not_blank'
      and conrelid = 'public.team_roles'::regclass
  ) then
    alter table public.team_roles
    add constraint team_roles_role_name_not_blank
    check (length(trim(role_name)) > 0)
    not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'team_roles_quantity_positive'
      and conrelid = 'public.team_roles'::regclass
  ) then
    alter table public.team_roles
    add constraint team_roles_quantity_positive
    check (quantity > 0)
    not valid;
  end if;
end;
$$;

alter table public.team_roles
validate constraint team_roles_role_name_not_blank;

alter table public.team_roles
validate constraint team_roles_quantity_positive;

create index if not exists idx_team_roles_team_active_order
on public.team_roles (team_id, is_active, display_order);

create index if not exists idx_team_roles_team_id
on public.team_roles (team_id);

create unique index if not exists ux_team_roles_team_role_name_active
on public.team_roles (team_id, lower(role_name))
where is_active = true;

comment on table public.team_roles is
  'Team-specific role templates used to generate service_slots for new service_instances.';

comment on column public.team_roles.role_name is
  'Base role label, such as Worship Leader, Backup Singer, Teacher, or Check-In.';

comment on column public.team_roles.quantity is
  'Number of service_slots generated for this role per service_instance.';

alter table public.team_roles enable row level security;

drop policy if exists "Authenticated users can read team roles" on public.team_roles;
create policy "Authenticated users can read team roles"
on public.team_roles
for select
to authenticated
using (true);

drop policy if exists "Admins can insert team roles" on public.team_roles;
create policy "Admins can insert team roles"
on public.team_roles
for insert
to authenticated
with check (
  exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and lower(coalesce(profiles.role, '')) = 'admin'
  )
);

drop policy if exists "Admins can update team roles" on public.team_roles;
create policy "Admins can update team roles"
on public.team_roles
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and lower(coalesce(profiles.role, '')) = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and lower(coalesce(profiles.role, '')) = 'admin'
  )
);

drop policy if exists "Admins can delete team roles" on public.team_roles;
create policy "Admins can delete team roles"
on public.team_roles
for delete
to authenticated
using (
  exists (
    select 1
    from public.profiles
    where profiles.id = auth.uid()
      and lower(coalesce(profiles.role, '')) = 'admin'
  )
);
