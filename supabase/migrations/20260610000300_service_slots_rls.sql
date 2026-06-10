-- Enable RLS for service_slots and preserve current app workflows.
--
-- Access audit:
-- - Home Page, Admin Dashboard, Monthly Schedule, My Schedule, Coverage
--   Requests, Service Slots, and Pending Assignments read service_slots.
-- - Volunteers update their own rows to claim open slots, unclaim accepted
--   slots, accept pending assignments, or decline pending assignments.
-- - Admins assign, regenerate, clean, and otherwise manage slots.
-- - Existing slot RPCs are SECURITY DEFINER and include their own checks:
--   request_coverage(...), claim_coverage_request(...),
--   generate_slots_from_team_roles(...), cleanup_duplicate_service_slots(...).

alter table public.service_slots enable row level security;

grant select, insert, update, delete
on public.service_slots
to authenticated;

drop policy if exists "Authenticated users can view service slots"
  on public.service_slots;

create policy "Authenticated users can view service slots"
  on public.service_slots
  for select
  using (auth.uid() is not null);

drop policy if exists "Users can claim open service slots"
  on public.service_slots;

create policy "Users can claim open service slots"
  on public.service_slots
  for update
  using (
    auth.uid() is not null
    and slot_status = 'open'
    and assigned_user_id is null
  )
  with check (
    assigned_user_id = auth.uid()
    and slot_status = 'taken'
  );

drop policy if exists "Users can accept pending service slots"
  on public.service_slots;

create policy "Users can accept pending service slots"
  on public.service_slots
  for update
  using (
    assigned_user_id = auth.uid()
    and slot_status = 'pending'
  )
  with check (
    assigned_user_id = auth.uid()
    and slot_status = 'taken'
  );

drop policy if exists "Users can release own service slots"
  on public.service_slots;

create policy "Users can release own service slots"
  on public.service_slots
  for update
  using (
    assigned_user_id = auth.uid()
    and slot_status in ('pending', 'taken')
  )
  with check (
    assigned_user_id is null
    and slot_status = 'open'
  );

drop policy if exists "Admins can insert service slots"
  on public.service_slots;

create policy "Admins can insert service slots"
  on public.service_slots
  for insert
  with check (public.is_admin());

drop policy if exists "Admins can update service slots"
  on public.service_slots;

create policy "Admins can update service slots"
  on public.service_slots
  for update
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "Admins can delete service slots"
  on public.service_slots;

create policy "Admins can delete service slots"
  on public.service_slots
  for delete
  using (public.is_admin());
