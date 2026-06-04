-- Add an admin-only RPC for removing duplicate service slots by slot_name.
--
-- For each duplicate (service_instance_id, slot_name) group, keep exactly one
-- row using this priority:
--   1. assigned_user_id is not null
--   2. slot_status = 'pending'
--   3. slot_status = 'taken'
--   4. oldest created_at
--   5. lowest id
--
-- Rows with a null slot_name are excluded. The highest-priority row is always
-- retained, so the final copy of a slot_name is never deleted.

create or replace function public.cleanup_duplicate_service_slots(
  p_service_instance_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_count integer;
begin
  if auth.uid() is null
    or not exists (
      select 1
      from public.profiles
      where profiles.id = auth.uid()
        and lower(coalesce(profiles.role, '')) = 'admin'
    )
  then
    raise exception 'Admin permission required';
  end if;

  if not exists (
    select 1
    from public.service_instances
    where service_instances.id = p_service_instance_id
  ) then
    raise exception 'Service instance not found: %', p_service_instance_id;
  end if;

  -- Use the same lock key as slot regeneration to prevent cleanup from racing
  -- with generation for this service instance.
  perform pg_advisory_xact_lock(
    hashtextextended(p_service_instance_id::text, 0)
  );

  with ranked_slots as (
    select
      service_slots.id,
      row_number() over (
        partition by service_slots.service_instance_id, service_slots.slot_name
        order by
          (service_slots.assigned_user_id is not null) desc,
          (service_slots.slot_status = 'pending') desc,
          (service_slots.slot_status = 'taken') desc,
          service_slots.created_at asc nulls last,
          service_slots.id asc
      ) as keep_rank
    from public.service_slots
    where service_slots.service_instance_id = p_service_instance_id
      and service_slots.slot_name is not null
  ),
  deleted_slots as (
    delete from public.service_slots
    using ranked_slots
    where service_slots.id = ranked_slots.id
      and ranked_slots.keep_rank > 1
    returning service_slots.id
  )
  select count(*)::integer
  into v_deleted_count
  from deleted_slots;

  return v_deleted_count;
end;
$$;

comment on function public.cleanup_duplicate_service_slots(uuid) is
  'Admin-only cleanup that keeps the highest-priority service_slot for each duplicate slot_name and returns the number deleted.';

revoke all on function public.cleanup_duplicate_service_slots(uuid) from public;
grant execute on function public.cleanup_duplicate_service_slots(uuid)
to authenticated;
