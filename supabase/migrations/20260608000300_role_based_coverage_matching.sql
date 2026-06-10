-- Build 3 enhancement: role-based coverage matching.
--
-- Add user role assignments and update coverage requests to match by
-- service_slots.team_role_id instead of team membership.

create table if not exists public.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  team_role_id uuid not null references public.team_roles(id) on delete cascade,
  assigned_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists ux_user_role_assignments_user_role
on public.user_role_assignments (user_id, team_role_id);

create index if not exists idx_user_role_assignments_user_id
on public.user_role_assignments (user_id);

create index if not exists idx_user_role_assignments_team_role_id
on public.user_role_assignments (team_role_id);

alter table public.user_role_assignments enable row level security;

drop policy if exists "Users can view own role assignments"
  on public.user_role_assignments;

create policy "Users can view own role assignments"
on public.user_role_assignments
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Admins can manage user role assignments"
  on public.user_role_assignments;

create policy "Admins can manage user role assignments"
on public.user_role_assignments
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

grant select, insert, update, delete on public.user_role_assignments
to authenticated;

drop policy if exists "Users can view team coverage requests"
  on public.coverage_requests;

drop policy if exists "Users can view role coverage requests"
  on public.coverage_requests;

create policy "Users can view role coverage requests"
on public.coverage_requests
for select
to authenticated
using (
  status = 'open'
  and requesting_user_id <> auth.uid()
  and exists (
    select 1
    from public.service_slots
    join public.user_role_assignments
      on user_role_assignments.team_role_id = service_slots.team_role_id
    where service_slots.id = coverage_requests.service_slot_id
      and user_role_assignments.user_id = auth.uid()
  )
);

drop policy if exists "Eligible users can claim open coverage requests"
  on public.coverage_requests;

create policy "Eligible users can claim open coverage requests"
on public.coverage_requests
for update
to authenticated
using (
  status = 'open'
  and requesting_user_id <> auth.uid()
  and (
    public.is_admin()
    or exists (
      select 1
      from public.service_slots
      join public.user_role_assignments
        on user_role_assignments.team_role_id = service_slots.team_role_id
      where service_slots.id = coverage_requests.service_slot_id
        and user_role_assignments.user_id = auth.uid()
    )
  )
)
with check (
  status in ('claimed', 'cancelled')
  and (
    public.is_admin()
    or claimed_by_user_id = auth.uid()
  )
);

create or replace function public.request_coverage(
  p_service_slot_id uuid,
  p_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid;
  v_service_instance_id uuid;
  v_team_id uuid;
  v_team_role_id uuid;
  v_role_name text;
  v_service_date date;
  v_start_time time;
begin
  select
    service_slots.service_instance_id,
    service_instances.team_id,
    service_slots.team_role_id,
    coalesce(service_slots.role_name, service_slots.slot_name, 'Assignment'),
    service_instances.service_date,
    service_instances.start_time
  into
    v_service_instance_id,
    v_team_id,
    v_team_role_id,
    v_role_name,
    v_service_date,
    v_start_time
  from public.service_slots
  join public.service_instances
    on service_instances.id = service_slots.service_instance_id
  where service_slots.id = p_service_slot_id
    and service_slots.assigned_user_id = auth.uid()
    and service_slots.slot_status in ('taken', 'pending')
  for update of service_slots;

  if v_service_instance_id is null then
    raise exception 'No assigned slot found for coverage request.';
  end if;

  if v_team_role_id is null then
    raise exception 'This assignment is not linked to a role yet.';
  end if;

  if exists (
    select 1
    from public.coverage_requests
    where coverage_requests.service_slot_id = p_service_slot_id
      and coverage_requests.status = 'open'
  ) then
    raise exception 'Coverage has already been requested for this assignment.';
  end if;

  update public.service_slots
  set
    slot_status = 'open',
    assigned_user_id = null,
    color_code = 'amber'
  where id = p_service_slot_id;

  insert into public.coverage_requests (
    service_slot_id,
    service_instance_id,
    team_id,
    requesting_user_id,
    message
  )
  values (
    p_service_slot_id,
    v_service_instance_id,
    v_team_id,
    auth.uid(),
    nullif(p_message, '')
  )
  returning id into v_request_id;

  insert into public.notifications (
    user_id,
    title,
    message,
    notification_type,
    related_service_instance_id
  )
  select distinct
    eligible_users.user_id,
    'Coverage Needed',
    v_role_name || ' for ' ||
      to_char(v_service_date, 'Dy, Mon FMDD') || ' at ' ||
      to_char(v_start_time, 'FMHH12:MI AM') || ' needs coverage.',
    'coverage_needed',
    v_service_instance_id
  from (
    select user_role_assignments.user_id
    from public.user_role_assignments
    where user_role_assignments.team_role_id = v_team_role_id

    union

    select profiles.id as user_id
    from public.profiles
    where lower(coalesce(profiles.role, '')) = 'admin'
      and coalesce(profiles.status, 'active') <> 'inactive'
  ) as eligible_users
  where eligible_users.user_id <> auth.uid()
    and not exists (
      select 1
      from public.service_slots
      where service_slots.service_instance_id = v_service_instance_id
        and service_slots.assigned_user_id = eligible_users.user_id
        and service_slots.slot_status in ('pending', 'taken')
    );

  return v_request_id;
end;
$$;

create or replace function public.claim_coverage_request(
  p_coverage_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_service_slot_id uuid;
  v_service_instance_id uuid;
  v_team_role_id uuid;
  v_requesting_user_id uuid;
  v_request_status text;
  v_slot_status text;
  v_role_name text;
  v_claimant_name text;
  v_updated_count integer;
begin
  select
    coverage_requests.service_slot_id,
    coverage_requests.service_instance_id,
    service_slots.team_role_id,
    coverage_requests.requesting_user_id,
    coverage_requests.status,
    service_slots.slot_status,
    coalesce(service_slots.role_name, service_slots.slot_name, 'Assignment')
  into
    v_service_slot_id,
    v_service_instance_id,
    v_team_role_id,
    v_requesting_user_id,
    v_request_status,
    v_slot_status,
    v_role_name
  from public.coverage_requests
  join public.service_slots
    on service_slots.id = coverage_requests.service_slot_id
  where coverage_requests.id = p_coverage_request_id
  for update of coverage_requests, service_slots;

  if v_service_slot_id is null then
    raise exception 'Coverage request is no longer available.';
  end if;

  if v_request_status <> 'open' or v_slot_status <> 'open' then
    raise exception 'This coverage request has already been claimed.';
  end if;

  if v_team_role_id is null then
    raise exception 'This coverage request is not linked to a role yet.';
  end if;

  if v_requesting_user_id = auth.uid() then
    raise exception 'You cannot claim your own coverage request.';
  end if;

  if not (
    public.is_admin()
    or exists (
      select 1
      from public.user_role_assignments
      where user_role_assignments.team_role_id = v_team_role_id
        and user_role_assignments.user_id = auth.uid()
    )
  ) then
    raise exception 'You are not eligible to claim this coverage request.';
  end if;

  if exists (
    select 1
    from public.service_slots
    where service_slots.service_instance_id = v_service_instance_id
      and service_slots.assigned_user_id = auth.uid()
      and service_slots.slot_status in ('pending', 'taken')
  ) then
    raise exception 'You already have a position assigned or pending for this service.';
  end if;

  update public.service_slots
  set
    slot_status = 'taken',
    assigned_user_id = auth.uid(),
    color_code = 'green'
  where id = v_service_slot_id
    and slot_status = 'open'
    and assigned_user_id is null;

  get diagnostics v_updated_count = row_count;

  if v_updated_count <> 1 then
    raise exception 'This coverage request has already been claimed.';
  end if;

  update public.coverage_requests
  set
    status = 'claimed',
    claimed_by_user_id = auth.uid(),
    claimed_at = now(),
    updated_at = now()
  where id = p_coverage_request_id
    and status = 'open';

  get diagnostics v_updated_count = row_count;

  if v_updated_count <> 1 then
    raise exception 'This coverage request has already been claimed.';
  end if;

  select trim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
  into v_claimant_name
  from public.profiles
  where id = auth.uid();

  if v_claimant_name is null or v_claimant_name = '' then
    select coalesce(email, 'A volunteer')
    into v_claimant_name
    from public.profiles
    where id = auth.uid();
  end if;

  insert into public.notifications (
    user_id,
    title,
    message,
    notification_type,
    related_service_instance_id
  )
  values (
    v_requesting_user_id,
    'Coverage Claimed',
    'Your coverage request has been claimed.',
    'coverage_claimed',
    v_service_instance_id
  );

  insert into public.notifications (
    user_id,
    title,
    message,
    notification_type,
    related_service_instance_id
  )
  select
    profiles.id,
    'Coverage Claimed',
    coalesce(v_claimant_name, 'A volunteer') || ' claimed coverage for ' ||
      v_role_name || '.',
    'coverage_claimed',
    v_service_instance_id
  from public.profiles
  where lower(coalesce(profiles.role, '')) = 'admin'
    and coalesce(profiles.status, 'active') <> 'inactive'
    and profiles.id <> auth.uid();
end;
$$;

revoke all on function public.request_coverage(uuid, text) from public;
grant execute on function public.request_coverage(uuid, text) to authenticated;

revoke all on function public.claim_coverage_request(uuid) from public;
grant execute on function public.claim_coverage_request(uuid) to authenticated;
