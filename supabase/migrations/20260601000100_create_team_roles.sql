-- Create team-specific service role definitions.
-- This migration only defines the role configuration table.
-- It does not seed production data and does not modify existing service slots.

create table if not exists public.team_roles (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  role_name text not null,
  quantity integer not null default 1,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint team_roles_role_name_not_blank
    check (length(trim(role_name)) > 0),
  constraint team_roles_quantity_positive
    check (quantity > 0)
);

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
