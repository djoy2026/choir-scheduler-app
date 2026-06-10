-- Build 3: coverage requests beta.
--
-- Additive only. No existing data is deleted or modified.

create table if not exists public.coverage_requests (
  id uuid primary key default gen_random_uuid(),
  service_slot_id uuid not null references public.service_slots(id),
  service_instance_id uuid not null references public.service_instances(id),
  team_id uuid not null references public.teams(id),
  requesting_user_id uuid not null references public.profiles(id),
  claimed_by_user_id uuid null references public.profiles(id),
  status text not null default 'open',
  message text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  claimed_at timestamptz null,
  constraint coverage_requests_status_check
    check (status in ('open', 'claimed', 'cancelled'))
);

create index if not exists idx_coverage_requests_status
  on public.coverage_requests (status);

create index if not exists idx_coverage_requests_team_id
  on public.coverage_requests (team_id);

create index if not exists idx_coverage_requests_requesting_user_id
  on public.coverage_requests (requesting_user_id);

create index if not exists idx_coverage_requests_service_slot_id
  on public.coverage_requests (service_slot_id);

create index if not exists idx_coverage_requests_service_instance_id
  on public.coverage_requests (service_instance_id);

create unique index if not exists ux_coverage_requests_one_open_per_slot
  on public.coverage_requests (service_slot_id)
  where status = 'open';

alter table public.coverage_requests enable row level security;

drop policy if exists "Users can view team coverage requests"
  on public.coverage_requests;

create policy "Users can view team coverage requests"
  on public.coverage_requests
  for select
  to authenticated
  using (
    status = 'open'
    and exists (
      select 1
      from public.team_members
      where team_members.team_id = coverage_requests.team_id
        and team_members.user_id = auth.uid()
    )
  );

drop policy if exists "Requesters can view own coverage requests"
  on public.coverage_requests;

create policy "Requesters can view own coverage requests"
  on public.coverage_requests
  for select
  to authenticated
  using (requesting_user_id = auth.uid());

drop policy if exists "Admins can view all coverage requests"
  on public.coverage_requests;

create policy "Admins can view all coverage requests"
  on public.coverage_requests
  for select
  to authenticated
  using (public.is_admin());

drop policy if exists "Assigned users can create coverage requests"
  on public.coverage_requests;

create policy "Assigned users can create coverage requests"
  on public.coverage_requests
  for insert
  to authenticated
  with check (
    requesting_user_id = auth.uid()
    and exists (
      select 1
      from public.service_slots
      where service_slots.id = coverage_requests.service_slot_id
        and service_slots.assigned_user_id = auth.uid()
        and service_slots.service_instance_id =
          coverage_requests.service_instance_id
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
        from public.team_members
        where team_members.team_id = coverage_requests.team_id
          and team_members.user_id = auth.uid()
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

drop policy if exists "Admins can manage all coverage requests"
  on public.coverage_requests;

create policy "Admins can manage all coverage requests"
  on public.coverage_requests
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

grant select, insert, update on public.coverage_requests to authenticated;

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
  v_role_name text;
  v_service_date date;
  v_start_time time;
begin
  select
    service_slots.service_instance_id,
    service_instances.team_id,
    coalesce(service_slots.role_name, service_slots.slot_name, 'Assignment'),
    service_instances.service_date,
    service_instances.start_time
  into
    v_service_instance_id,
    v_team_id,
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
    select team_members.user_id
    from public.team_members
    join public.profiles
      on profiles.id = team_members.user_id
    where team_members.team_id = v_team_id
      and coalesce(profiles.status, 'active') = 'active'

    union

    select profiles.id as user_id
    from public.profiles
    where lower(coalesce(profiles.role, '')) = 'admin'
      and coalesce(profiles.status, 'active') = 'active'
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
  v_team_id uuid;
  v_requesting_user_id uuid;
  v_role_name text;
  v_claimant_name text;
begin
  select
    coverage_requests.service_slot_id,
    coverage_requests.service_instance_id,
    coverage_requests.team_id,
    coverage_requests.requesting_user_id,
    coalesce(service_slots.role_name, service_slots.slot_name, 'Assignment')
  into
    v_service_slot_id,
    v_service_instance_id,
    v_team_id,
    v_requesting_user_id,
    v_role_name
  from public.coverage_requests
  join public.service_slots
    on service_slots.id = coverage_requests.service_slot_id
  where coverage_requests.id = p_coverage_request_id
    and coverage_requests.status = 'open'
  for update of coverage_requests, service_slots;

  if v_service_slot_id is null then
    raise exception 'Coverage request is no longer available.';
  end if;

  if v_requesting_user_id = auth.uid() then
    raise exception 'You cannot claim your own coverage request.';
  end if;

  if not (
    public.is_admin()
    or exists (
      select 1
      from public.team_members
      where team_members.team_id = v_team_id
        and team_members.user_id = auth.uid()
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
  where id = v_service_slot_id;

  update public.coverage_requests
  set
    status = 'claimed',
    claimed_by_user_id = auth.uid(),
    claimed_at = now(),
    updated_at = now()
  where id = p_coverage_request_id;

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
    and coalesce(profiles.status, 'active') = 'active'
    and profiles.id <> auth.uid();
end;
$$;

revoke all on function public.request_coverage(uuid, text) from public;
grant execute on function public.request_coverage(uuid, text) to authenticated;

revoke all on function public.claim_coverage_request(uuid) from public;
grant execute on function public.claim_coverage_request(uuid) to authenticated;
