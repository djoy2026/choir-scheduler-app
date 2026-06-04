-- Read-only validation queries for cleanup_duplicate_service_slots.
-- Replace the UUID in target_service before running these queries.

-- 1. Preview duplicate slot_name groups and their cleanup counts.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
)
select
  service_slots.service_instance_id,
  service_slots.slot_name,
  count(*) as current_count,
  count(*) - 1 as expected_deleted_count
from target_service
join public.service_slots
  on service_slots.service_instance_id = target_service.service_instance_id
where service_slots.slot_name is not null
group by service_slots.service_instance_id, service_slots.slot_name
having count(*) > 1
order by service_slots.slot_name;

-- 2. Preview exactly which row would be kept and which rows would be deleted.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
),
ranked_slots as (
  select
    service_slots.id,
    service_slots.service_instance_id,
    service_slots.slot_name,
    service_slots.role_name,
    service_slots.slot_status,
    service_slots.assigned_user_id,
    service_slots.created_at,
    row_number() over (
      partition by service_slots.service_instance_id, service_slots.slot_name
      order by
        (service_slots.assigned_user_id is not null) desc,
        (service_slots.slot_status = 'pending') desc,
        (service_slots.slot_status = 'taken') desc,
        service_slots.created_at asc nulls last,
        service_slots.id asc
    ) as keep_rank,
    count(*) over (
      partition by service_slots.service_instance_id, service_slots.slot_name
    ) as duplicate_count
  from target_service
  join public.service_slots
    on service_slots.service_instance_id = target_service.service_instance_id
  where service_slots.slot_name is not null
)
select
  id,
  service_instance_id,
  slot_name,
  role_name,
  slot_status,
  assigned_user_id,
  created_at,
  duplicate_count,
  case when keep_rank = 1 then 'KEEP' else 'DELETE' end as cleanup_action
from ranked_slots
where duplicate_count > 1
order by slot_name, keep_rank;

-- 3. Highlight duplicate groups where cleanup would delete at least one
-- assigned, pending, or taken row after retaining the highest-priority copy.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
),
ranked_slots as (
  select
    service_slots.*,
    row_number() over (
      partition by service_slots.service_instance_id, service_slots.slot_name
      order by
        (service_slots.assigned_user_id is not null) desc,
        (service_slots.slot_status = 'pending') desc,
        (service_slots.slot_status = 'taken') desc,
        service_slots.created_at asc nulls last,
        service_slots.id asc
    ) as keep_rank
  from target_service
  join public.service_slots
    on service_slots.service_instance_id = target_service.service_instance_id
  where service_slots.slot_name is not null
)
select
  id,
  service_instance_id,
  slot_name,
  slot_status,
  assigned_user_id,
  created_at
from ranked_slots
where keep_rank > 1
  and (
    assigned_user_id is not null
    or slot_status in ('pending', 'taken')
  )
order by slot_name, created_at, id;

-- 4. Count rows expected to be deleted. This should match deleted_count.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
),
ranked_slots as (
  select
    row_number() over (
      partition by service_slots.service_instance_id, service_slots.slot_name
      order by
        (service_slots.assigned_user_id is not null) desc,
        (service_slots.slot_status = 'pending') desc,
        (service_slots.slot_status = 'taken') desc,
        service_slots.created_at asc nulls last,
        service_slots.id asc
    ) as keep_rank
  from target_service
  join public.service_slots
    on service_slots.service_instance_id = target_service.service_instance_id
  where service_slots.slot_name is not null
)
select count(*) as expected_deleted_count
from ranked_slots
where keep_rank > 1;

-- 5. After cleanup, verify no duplicate non-null slot_name remains.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
)
select
  service_slots.service_instance_id,
  service_slots.slot_name,
  count(*) as remaining_count
from target_service
join public.service_slots
  on service_slots.service_instance_id = target_service.service_instance_id
where service_slots.slot_name is not null
group by service_slots.service_instance_id, service_slots.slot_name
having count(*) > 1;

-- 6. After cleanup, verify every original slot_name still has one copy by
-- comparing against a before-cleanup snapshot or exported validation result.
