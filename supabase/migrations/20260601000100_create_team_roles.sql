-- Create or upgrade team-specific service role definitions.
-- Supports fresh databases where team_roles is missing and existing cloud
-- schemas where team_roles already has:
-- id, team_id, role_name, display_order, created_at.
-- It does not seed production data and does not modify existing service slots.

create table if not exists public.team_roles (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  role_name text not null,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  quantity integer not null default 1,
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

do $$
begin
  if to_regclass('public.teams') is not null
    and not exists (
      select 1
      from pg_constraint
      where conrelid = 'public.team_roles'::regclass
        and confrelid = 'public.teams'::regclass
        and contype = 'f'
    )
  then
    alter table public.team_roles
    add constraint team_roles_team_id_fkey
    foreign key (team_id)
    references public.teams(id)
    on delete cascade;
  end if;
end;
$$;

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

with ranked_roles as (
  select
    id,
    count(*) over (
      partition by team_id, lower(trim(role_name))
    ) as duplicate_count,
    min(display_order) over (
      partition by team_id, lower(trim(role_name))
    ) as minimum_display_order,
    row_number() over (
      partition by team_id, lower(trim(role_name))
      order by display_order, created_at, id
    ) as role_rank
  from public.team_roles
)
update public.team_roles
set
  quantity = case
    when ranked_roles.role_rank = 1 then ranked_roles.duplicate_count
    else 1
  end,
  is_active = ranked_roles.role_rank = 1,
  display_order = case
    when ranked_roles.role_rank = 1
      then ranked_roles.minimum_display_order
    else public.team_roles.display_order
  end,
  updated_at = now()
from ranked_roles
where public.team_roles.id = ranked_roles.id
  and ranked_roles.duplicate_count > 1
  and (
    public.team_roles.quantity is distinct from case
      when ranked_roles.role_rank = 1 then ranked_roles.duplicate_count
      else 1
    end
    or public.team_roles.is_active is distinct from (
      ranked_roles.role_rank = 1
    )
    or public.team_roles.display_order is distinct from case
      when ranked_roles.role_rank = 1
        then ranked_roles.minimum_display_order
      else public.team_roles.display_order
    end
  );

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
on public.team_roles (team_id, lower(trim(role_name)))
where is_active = true;

comment on table public.team_roles is
  'Team-specific role templates used to generate service_slots for new service_instances.';

comment on column public.team_roles.role_name is
  'Base role label, such as Worship Leader, Backup Singer, Teacher, or Check-In.';

comment on column public.team_roles.quantity is
  'Number of service_slots generated for this role per service_instance.';

alter table public.team_roles enable row level security;

do $$
begin
  if to_regclass('public.profiles') is not null then
    drop policy if exists "Authenticated users can read team roles"
    on public.team_roles;

    create policy "Authenticated users can read team roles"
    on public.team_roles
    for select
    to authenticated
    using (true);

    drop policy if exists "Admins can insert team roles"
    on public.team_roles;

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

    drop policy if exists "Admins can update team roles"
    on public.team_roles;

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

    drop policy if exists "Admins can delete team roles"
    on public.team_roles;

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
  end if;
end;
$$;
