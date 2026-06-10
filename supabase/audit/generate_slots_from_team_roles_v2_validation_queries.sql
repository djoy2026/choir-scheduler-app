-- Read-only validation queries for generate_slots_from_team_roles v2.
-- Replace the UUID in target_service before running these queries.

-- 1. Preview the mode and source team for the target service.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
)
select
  service_instances.id as service_instance_id,
  service_instances.service_name,
  service_instances.ministry_id,
  service_instances.team_id,
  teams.name as team_name,
  teams.name = 'Children''s Ministry Live Schedule' as is_live_schedule_mode
from target_service
join public.service_instances
  on service_instances.id = target_service.service_instance_id
join public.teams
  on teams.id = service_instances.team_id;

-- 2. Preview every expected quantity-aware slot_name for the target service.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
),
service_context as (
  select
    service_instances.id as service_instance_id,
    service_instances.team_id,
    service_instances.ministry_id,
    teams.name as team_name,
    teams.name = 'Children''s Ministry Live Schedule' as is_live_schedule
  from target_service
  join public.service_instances
    on service_instances.id = target_service.service_instance_id
  join public.teams
    on teams.id = service_instances.team_id
),
source_roles as (
  select
    service_context.service_instance_id,
    service_context.is_live_schedule,
    teams.name as source_team_name,
    team_roles.id as team_role_id,
    team_roles.role_name,
    team_roles.quantity,
    team_roles.display_order
  from service_context
  join public.teams
    on (
      (
        not service_context.is_live_schedule
        and teams.id = service_context.team_id
      )
      or
      (
        service_context.is_live_schedule
        and teams.ministry_id = service_context.ministry_id
        and teams.id <> service_context.team_id
      )
    )
  join public.team_roles
    on team_roles.team_id = teams.id
   and team_roles.is_active = true
)
select
  source_roles.source_team_name,
  source_roles.team_role_id,
  role_instances.instance_number as role_instance_number,
  case
    when source_roles.is_live_schedule then
      source_roles.source_team_name || ' - ' ||
      case
        when source_roles.quantity = 1 then source_roles.role_name
        else source_roles.role_name || ' ' || role_instances.instance_number::text
      end
    when source_roles.quantity = 1 then source_roles.role_name
    else source_roles.role_name || ' ' || role_instances.instance_number::text
  end as expected_slot_name
from source_roles
cross join lateral generate_series(
  1,
  source_roles.quantity
) as role_instances(instance_number)
order by
  source_roles.source_team_name,
  source_roles.display_order,
  role_instances.instance_number;

-- 3. Find expected slots that are currently missing.
-- This result count should equal the RPC created_count before generation.
with target_service as (
  select '<SERVICE_INSTANCE_ID>'::uuid as service_instance_id
),
service_context as (
  select
    service_instances.id as service_instance_id,
    service_instances.team_id,
    service_instances.ministry_id,
    teams.name = 'Children''s Ministry Live Schedule' as is_live_schedule
  from target_service
  join public.service_instances
    on service_instances.id = target_service.service_instance_id
  join public.teams
    on teams.id = service_instances.team_id
),
expected_slots as (
  select distinct
    service_context.service_instance_id,
    case
      when service_context.is_live_schedule then
        teams.name || ' - ' ||
        case
          when team_roles.quantity = 1 then team_roles.role_name
          else team_roles.role_name || ' ' || role_instances.instance_number::text
        end
      when team_roles.quantity = 1 then team_roles.role_name
      else team_roles.role_name || ' ' || role_instances.instance_number::text
    end as expected_slot_name
  from service_context
  join public.teams
    on (
      (
        not service_context.is_live_schedule
        and teams.id = service_context.team_id
      )
      or
      (
        service_context.is_live_schedule
        and teams.ministry_id = service_context.ministry_id
        and teams.id <> service_context.team_id
      )
    )
  join public.team_roles
    on team_roles.team_id = teams.id
   and team_roles.is_active = true
  cross join lateral generate_series(
    1,
    team_roles.quantity
  ) as role_instances(instance_number)
)
select expected_slots.expected_slot_name
from expected_slots
where not exists (
  select 1
  from public.service_slots
  where service_slots.service_instance_id = expected_slots.service_instance_id
    and service_slots.slot_name = expected_slots.expected_slot_name
)
order by expected_slots.expected_slot_name;

-- 4. Find active role configurations that generate the same slot_name.
-- These collisions are deduplicated by the RPC before insertion.
with source_roles as (
  select
    teams.id as team_id,
    teams.name as team_name,
    team_roles.id as team_role_id,
    team_roles.role_name,
    team_roles.quantity,
    team_roles.display_order
  from public.team_roles
  join public.teams
    on teams.id = team_roles.team_id
  where team_roles.is_active = true
),
generated_names as (
  select
    source_roles.team_id,
    source_roles.team_name,
    source_roles.team_role_id,
    source_roles.display_order,
    case
      when source_roles.quantity = 1 then source_roles.role_name
      else source_roles.role_name || ' ' || role_instances.instance_number::text
    end as generated_slot_name
  from source_roles
  cross join lateral generate_series(
    1,
    source_roles.quantity
  ) as role_instances(instance_number)
)
select
  team_id,
  team_name,
  generated_slot_name,
  count(*) as candidate_count,
  array_agg(team_role_id order by display_order, team_role_id) as team_role_ids
from generated_names
group by team_id, team_name, generated_slot_name
having count(*) > 1
order by team_name, generated_slot_name;

-- 5. Find duplicate slot_name values already present on any service.
select
  service_instance_id,
  slot_name,
  count(*) as duplicate_count
from public.service_slots
group by service_instance_id, slot_name
having count(*) > 1
order by duplicate_count desc, service_instance_id, slot_name;

-- 6. Confirm assigned, pending, and taken slots remain present.
select
  service_instance_id,
  id as service_slot_id,
  slot_name,
  role_name,
  slot_status,
  assigned_user_id
from public.service_slots
where slot_status in ('pending', 'taken')
   or assigned_user_id is not null
order by service_instance_id, slot_name;

-- 7. After running the RPC once, run the missing-slot query again.
-- Expected result: zero rows. A second RPC call should return created_count = 0.
