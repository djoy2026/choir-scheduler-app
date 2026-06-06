-- Classroom service generation for Kids Class Schedule.
--
-- Purpose:
-- - Remove dependency on old classroom test services.
-- - Generate future classroom service_instances for the next 8 weeks.
-- - Generate every church service time for every classroom team.
-- - Keep this script manual and reviewable. Do not run against production until
--   the preview queries match expectations.
--
-- Classroom teams:
-- - Nursery
-- - Kindies
-- - 2 Year Olds
-- - 3 Year Olds
-- - 4 Year Olds
-- - 1st Grade
-- - 2nd Grade
-- - 3rd Grade
-- - 4th Grade
-- - 5th Grade
--
-- Church service times:
-- - Wednesday 7:00 PM
-- - Saturday 6:00 PM
-- - Sunday 8:00 AM
-- - Sunday 9:45 AM
-- - Sunday 11:45 AM

-- ============================================================
-- 1. PREVIEW CLASSROOM TEAMS
-- ============================================================

with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
)
select
  ministries.id as ministry_id,
  ministries.name as ministry_name,
  teams.id as team_id,
  teams.name as team_name,
  classroom_team_names.sort_order
from classroom_team_names
join public.teams
  on teams.name = classroom_team_names.team_name
join public.ministries
  on ministries.id = teams.ministry_id
order by
  classroom_team_names.sort_order;

-- Expected: exactly 10 rows.

-- ============================================================
-- 2. CLEANUP SQL
-- ============================================================
--
-- This cleanup targets future classroom service_instances that look like old
-- generated/test services and have no assigned/pending/taken slots.
--
-- It deliberately avoids deleting any service with a non-open slot so existing
-- real volunteer activity is preserved.
--
-- Run the preview first. Only run the delete after reviewing the preview.

with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
),
cleanup_candidates as (
  select
    service_instances.id,
    service_instances.service_name,
    service_instances.service_date,
    service_instances.start_time,
    service_instances.end_time,
    service_instances.location,
    service_instances.status,
    teams.name as team_name,
    count(service_slots.id) as total_slots,
    count(service_slots.id) filter (
      where service_slots.assigned_user_id is not null
         or service_slots.slot_status in ('pending', 'taken')
    ) as protected_slots
  from public.service_instances
  join public.teams
    on teams.id = service_instances.team_id
  join classroom_team_names
    on classroom_team_names.team_name = teams.name
  left join public.service_slots
    on service_slots.service_instance_id = service_instances.id
  where service_instances.service_date >= current_date
    and (
      service_instances.service_name ilike 'Service %'
      or service_instances.service_name ilike '%test%'
      or service_instances.service_name ilike '%classroom test%'
      or service_instances.service_name ilike '%kids class test%'
    )
  group by
    service_instances.id,
    service_instances.service_name,
    service_instances.service_date,
    service_instances.start_time,
    service_instances.end_time,
    service_instances.location,
    service_instances.status,
    teams.name
)
select *
from cleanup_candidates
order by
  service_date,
  start_time,
  team_name;

-- Optional destructive cleanup.
-- Review the preview above before running this delete.
--
-- begin;
--
-- with classroom_team_names(team_name, sort_order) as (
--   values
--     ('Nursery', 1),
--     ('Kindies', 2),
--     ('2 Year Olds', 3),
--     ('3 Year Olds', 4),
--     ('4 Year Olds', 5),
--     ('1st Grade', 6),
--     ('2nd Grade', 7),
--     ('3rd Grade', 8),
--     ('4th Grade', 9),
--     ('5th Grade', 10)
-- ),
-- cleanup_candidates as (
--   select service_instances.id
--   from public.service_instances
--   join public.teams
--     on teams.id = service_instances.team_id
--   join classroom_team_names
--     on classroom_team_names.team_name = teams.name
--   left join public.service_slots
--     on service_slots.service_instance_id = service_instances.id
--   where service_instances.service_date >= current_date
--     and (
--       service_instances.service_name ilike 'Service %'
--       or service_instances.service_name ilike '%test%'
--       or service_instances.service_name ilike '%classroom test%'
--       or service_instances.service_name ilike '%kids class test%'
--     )
--   group by service_instances.id
--   having count(service_slots.id) filter (
--     where service_slots.assigned_user_id is not null
--        or service_slots.slot_status in ('pending', 'taken')
--   ) = 0
-- )
-- delete from public.service_instances
-- using cleanup_candidates
-- where service_instances.id = cleanup_candidates.id
-- returning
--   service_instances.id,
--   service_instances.service_name,
--   service_instances.service_date,
--   service_instances.start_time;
--
-- commit;

-- ============================================================
-- 3. GENERATION SQL
-- ============================================================
--
-- Inserts classroom service_instances for the next 8 weeks.
-- Idempotency:
-- - A row is inserted only when no service exists for the same:
--   team_id + service_date + start_time.
--
-- Service names intentionally use date/time labels. The Flutter UI can render
-- professional titles from service_date/start_time while preserving team names.

with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
),
classroom_teams as (
  select
    teams.id as team_id,
    teams.ministry_id,
    teams.name as team_name,
    classroom_team_names.sort_order
  from classroom_team_names
  join public.teams
    on teams.name = classroom_team_names.team_name
),
calendar_days as (
  select generated_day::date as service_date
  from generate_series(
    current_date,
    current_date + interval '56 days',
    interval '1 day'
  ) as generated_days(generated_day)
),
church_service_times as (
  select
    3 as day_of_week,
    time '19:00' as start_time,
    time '20:30' as end_time,
    'Wednesday 7:00 PM' as service_label,
    1 as sort_order
  union all
  select
    6,
    time '18:00',
    time '19:30',
    'Saturday 6:00 PM',
    2
  union all
  select
    0,
    time '08:00',
    time '09:30',
    'Sunday 8:00 AM',
    3
  union all
  select
    0,
    time '09:45',
    time '11:15',
    'Sunday 9:45 AM',
    4
  union all
  select
    0,
    time '11:45',
    time '13:15',
    'Sunday 11:45 AM',
    5
),
generated_services as (
  select
    gen_random_uuid() as id,
    classroom_teams.ministry_id,
    classroom_teams.team_id,
    church_service_times.service_label as service_name,
    calendar_days.service_date,
    church_service_times.start_time,
    church_service_times.end_time,
    'Classroom' as location,
    'scheduled' as status,
    classroom_teams.sort_order as team_sort_order,
    church_service_times.sort_order as service_time_sort_order
  from classroom_teams
  cross join calendar_days
  join church_service_times
    on extract(dow from calendar_days.service_date)::integer =
      church_service_times.day_of_week
)
insert into public.service_instances (
  id,
  ministry_id,
  team_id,
  service_name,
  service_date,
  start_time,
  end_time,
  location,
  status
)
select
  generated_services.id,
  generated_services.ministry_id,
  generated_services.team_id,
  generated_services.service_name,
  generated_services.service_date,
  generated_services.start_time,
  generated_services.end_time,
  generated_services.location,
  generated_services.status
from generated_services
where not exists (
  select 1
  from public.service_instances existing_services
  where existing_services.team_id = generated_services.team_id
    and existing_services.service_date = generated_services.service_date
    and existing_services.start_time = generated_services.start_time
)
order by
  generated_services.service_date,
  generated_services.service_time_sort_order,
  generated_services.team_sort_order
returning
  id,
  service_name,
  service_date,
  start_time,
  end_time,
  location,
  status;

-- ============================================================
-- 4. VERIFICATION SQL
-- ============================================================

-- 4.1 Count generated future classroom services by team.
with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
)
select
  teams.name as team_name,
  count(service_instances.id) as upcoming_service_count
from classroom_team_names
join public.teams
  on teams.name = classroom_team_names.team_name
left join public.service_instances
  on service_instances.team_id = teams.id
  and service_instances.service_date >= current_date
  and service_instances.service_date <= current_date + interval '56 days'
group by
  classroom_team_names.sort_order,
  teams.name
order by
  classroom_team_names.sort_order;

-- 4.2 Total upcoming services for the Home page Kids Class Schedule card.
with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
)
select
  'Kids Class Schedule' as ministry_display_name,
  count(service_instances.id) as upcoming_service_count
from classroom_team_names
join public.teams
  on teams.name = classroom_team_names.team_name
join public.service_instances
  on service_instances.team_id = teams.id
  and service_instances.service_date >= current_date;

-- 4.3 Confirm all expected church service times exist.
with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
),
expected_service_times(service_day, start_time) as (
  values
    (3, time '19:00'),
    (6, time '18:00'),
    (0, time '08:00'),
    (0, time '09:45'),
    (0, time '11:45')
)
select
  expected_service_times.service_day,
  expected_service_times.start_time,
  count(service_instances.id) as generated_count
from expected_service_times
cross join classroom_team_names
join public.teams
  on teams.name = classroom_team_names.team_name
left join public.service_instances
  on service_instances.team_id = teams.id
  and service_instances.start_time = expected_service_times.start_time
  and extract(dow from service_instances.service_date)::integer =
    expected_service_times.service_day
  and service_instances.service_date >= current_date
  and service_instances.service_date <= current_date + interval '56 days'
group by
  expected_service_times.service_day,
  expected_service_times.start_time
order by
  expected_service_times.service_day,
  expected_service_times.start_time;

-- 4.4 Detect duplicates by classroom team/date/start_time.
with classroom_team_names(team_name, sort_order) as (
  values
    ('Nursery', 1),
    ('Kindies', 2),
    ('2 Year Olds', 3),
    ('3 Year Olds', 4),
    ('4 Year Olds', 5),
    ('1st Grade', 6),
    ('2nd Grade', 7),
    ('3rd Grade', 8),
    ('4th Grade', 9),
    ('5th Grade', 10)
)
select
  teams.name as team_name,
  service_instances.service_date,
  service_instances.start_time,
  count(*) as duplicate_count,
  array_agg(service_instances.id order by service_instances.id) as service_instance_ids
from classroom_team_names
join public.teams
  on teams.name = classroom_team_names.team_name
join public.service_instances
  on service_instances.team_id = teams.id
  and service_instances.service_date >= current_date
group by
  teams.name,
  service_instances.service_date,
  service_instances.start_time
having count(*) > 1
order by
  service_instances.service_date,
  service_instances.start_time,
  teams.name;
