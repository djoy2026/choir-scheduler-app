-- Read-only validation and audit queries for the team role slot generation change.
-- These queries are intended for manual review before and after applying the
-- schema/function migrations. They do not modify data.

-- 1. List teams and their configured roles.
select
  ministries.name as ministry_name,
  teams.name as team_name,
  team_roles.role_name,
  team_roles.quantity,
  team_roles.display_order,
  team_roles.is_active
from public.team_roles
join public.teams
  on teams.id = team_roles.team_id
left join public.ministries
  on ministries.id = teams.ministry_id
order by
  ministries.name,
  teams.name,
  team_roles.display_order,
  team_roles.role_name;

-- 2. Find teams with no active role configuration.
select
  ministries.name as ministry_name,
  teams.id as team_id,
  teams.name as team_name
from public.teams
left join public.ministries
  on ministries.id = teams.ministry_id
where not exists (
  select 1
  from public.team_roles
  where team_roles.team_id = teams.id
    and team_roles.is_active = true
)
order by ministries.name, teams.name;

-- 3. Show expected slot counts per team based on active role quantities.
select
  ministries.name as ministry_name,
  teams.id as team_id,
  teams.name as team_name,
  coalesce(sum(team_roles.quantity), 0) as expected_slots_per_service
from public.teams
left join public.ministries
  on ministries.id = teams.ministry_id
left join public.team_roles
  on team_roles.team_id = teams.id
 and team_roles.is_active = true
group by ministries.name, teams.id, teams.name
order by ministries.name, teams.name;

-- 4. Compare existing service slot counts to expected active team role counts.
select
  ministries.name as ministry_name,
  teams.name as team_name,
  service_instances.id as service_instance_id,
  service_instances.service_name,
  service_instances.service_date,
  service_instances.start_time,
  count(service_slots.id) as actual_slot_count,
  coalesce(expected.expected_slot_count, 0) as expected_slot_count
from public.service_instances
join public.teams
  on teams.id = service_instances.team_id
left join public.ministries
  on ministries.id = service_instances.ministry_id
left join public.service_slots
  on service_slots.service_instance_id = service_instances.id
left join (
  select
    team_roles.team_id,
    sum(team_roles.quantity) as expected_slot_count
  from public.team_roles
  where team_roles.is_active = true
  group by team_roles.team_id
) expected
  on expected.team_id = service_instances.team_id
group by
  ministries.name,
  teams.name,
  service_instances.id,
  service_instances.service_name,
  service_instances.service_date,
  service_instances.start_time,
  expected.expected_slot_count
order by
  service_instances.service_date,
  service_instances.start_time,
  ministries.name,
  teams.name;

-- 5. Find duplicate generated role instances on a service.
select
  service_instance_id,
  team_role_id,
  role_instance_number,
  count(*) as duplicate_count
from public.service_slots
where team_role_id is not null
  and role_instance_number is not null
group by
  service_instance_id,
  team_role_id,
  role_instance_number
having count(*) > 1;

-- 6. Find invalid role instance numbers.
select
  *
from public.service_slots
where role_instance_number is not null
  and role_instance_number <= 0;

-- 7. Find service slots whose team_role_id does not belong to the service's team.
select
  service_slots.id as service_slot_id,
  service_slots.service_instance_id,
  service_slots.team_role_id,
  service_instances.team_id as service_team_id,
  team_roles.team_id as role_team_id
from public.service_slots
join public.service_instances
  on service_instances.id = service_slots.service_instance_id
join public.team_roles
  on team_roles.id = service_slots.team_role_id
where service_slots.team_role_id is not null
  and team_roles.team_id <> service_instances.team_id;

-- 8. Find status/assignment consistency issues.
select
  *
from public.service_slots
where
  (slot_status = 'open' and assigned_user_id is not null)
  or
  (slot_status in ('pending', 'taken') and assigned_user_id is null);

-- 9. Find existing overlapping pending/taken assignments.
-- This is audit-only. The double-booking trigger is intentionally not added
-- in this first change set.
select
  first_slot.assigned_user_id,
  first_slot.id as first_slot_id,
  second_slot.id as second_slot_id,
  first_service.service_date,
  first_service.start_time as first_start_time,
  first_service.end_time as first_end_time,
  second_service.start_time as second_start_time,
  second_service.end_time as second_end_time
from public.service_slots first_slot
join public.service_instances first_service
  on first_service.id = first_slot.service_instance_id
join public.service_slots second_slot
  on second_slot.assigned_user_id = first_slot.assigned_user_id
 and second_slot.id > first_slot.id
join public.service_instances second_service
  on second_service.id = second_slot.service_instance_id
where first_slot.assigned_user_id is not null
  and first_slot.slot_status in ('pending', 'taken')
  and second_slot.slot_status in ('pending', 'taken')
  and first_service.id <> second_service.id
  and first_service.service_date = second_service.service_date
  and first_service.start_time < second_service.end_time
  and first_service.end_time > second_service.start_time
order by
  first_slot.assigned_user_id,
  first_service.service_date,
  first_service.start_time;

-- 10. Preview generated slot labels from team role quantities.
select
  ministries.name as ministry_name,
  teams.name as team_name,
  team_roles.role_name as base_role_name,
  team_roles.quantity,
  role_instances.instance_number,
  case
    when team_roles.quantity = 1 then team_roles.role_name
    else team_roles.role_name || ' ' || role_instances.instance_number::text
  end as generated_slot_label
from public.team_roles
join public.teams
  on teams.id = team_roles.team_id
left join public.ministries
  on ministries.id = teams.ministry_id
cross join lateral generate_series(
  1,
  team_roles.quantity
) as role_instances(instance_number)
where team_roles.is_active = true
order by
  ministries.name,
  teams.name,
  team_roles.display_order,
  team_roles.role_name,
  role_instances.instance_number;
