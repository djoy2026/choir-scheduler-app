# Database Migration Execution Plan

This document is a review artifact for the Team Role database migration work. It does not execute migrations, modify Supabase data, or change Flutter code.

## 1. Current `team_roles` Schema

The live `team_roles` table already exists.

Current columns:

```text
id
team_id
role_name
display_order
created_at
```

Current missing columns:

```text
quantity
is_active
updated_at
```

Current behavior:

- Stores role names associated with teams.
- Does not support role quantities.
- Does not support active/inactive role lifecycle.
- Does not provide enough metadata for automatic multi-slot generation.

## 2. Target `team_roles` Schema

Target columns:

```text
id uuid primary key
team_id uuid not null references public.teams(id) on delete cascade
role_name text not null
display_order integer not null default 0
created_at timestamptz not null default now()
quantity integer not null default 1
is_active boolean not null default true
updated_at timestamptz not null default now()
```

Target constraints:

```text
team_roles_role_name_not_blank
team_roles_quantity_positive
```

Target indexes:

```text
idx_team_roles_team_active_order
idx_team_roles_team_id
ux_team_roles_team_role_name_active
```

Target behavior:

- Each team defines its own roles.
- Each role has a base `role_name`.
- Each role has a positive `quantity`.
- Active roles are used for future service slot generation.
- Inactive roles remain available for history but are excluded from future generated slots.
- Active role names are unique per team, case-insensitively.

## 3. Current `service_slots` Schema

Current columns:

```text
id
service_instance_id
slot_name
role_name
slot_status
assigned_user_id
color_code
created_at
```

Current missing columns:

```text
team_role_id
role_instance_number
```

Current behavior:

- Stores assignable service slots.
- Preserves claim, unclaim, pending assignment, and admin assignment workflows.
- Uses `slot_status`, `assigned_user_id`, and `color_code` as the current app-facing slot state.

## 4. Target `service_slots` Schema

Additional target columns:

```text
team_role_id uuid null references public.team_roles(id) on delete set null
role_instance_number integer null
```

Target constraints:

```text
service_slots_role_instance_number_positive
```

Target indexes:

```text
idx_service_slots_team_role_id
idx_service_slots_service_instance_id
idx_service_slots_assigned_user_id
idx_service_slots_slot_status
ux_service_slots_one_role_instance_per_service
```

Target behavior:

- Existing slots remain valid with `team_role_id = null`.
- Existing slots remain valid with `role_instance_number = null`.
- Newly generated slots can be traced back to the role configuration that created them.
- Quantity `1` generates an unnumbered slot label, such as `Worship Leader`.
- Quantity greater than `1` generates numbered slot labels, such as `Backup Singer 1`, `Backup Singer 2`, and `Backup Singer 3`.
- Duplicate generated role instances are prevented per service instance.

## 5. Exact Migration Execution Order

Run the migration files in timestamp order during an approved maintenance window. Do not execute these from Flutter.

1. Apply `supabase/migrations/20260601000100_create_team_roles.sql`.

   This upgrades the existing `team_roles` table with `ALTER TABLE` statements. It adds and backfills `quantity`, `is_active`, and `updated_at`, then validates the new constraints.

2. Apply `supabase/migrations/20260601000200_extend_service_slots_for_team_roles.sql`.

   This adds nullable generated-role metadata to `service_slots`: `team_role_id` and `role_instance_number`.

3. Apply `supabase/migrations/20260601000300_update_generate_slots_from_team_roles.sql`.

   This replaces the existing `generate_slots_from_team_roles(uuid)` function while preserving the RPC name used by Flutter.

4. Use `supabase/migrations/20260601000400_team_role_validation_audit_queries.sql` as a read-only validation reference.

   This file contains audit queries only. It should not be treated as a data-changing migration.

Pre-execution checklist:

- Confirm a fresh Supabase backup exists.
- Capture the current `generate_slots_from_team_roles(uuid)` function definition for rollback.
- Confirm no one is actively creating service instances during the migration window.
- Confirm the migration operator understands that existing service instances will not be automatically regenerated.

## 6. Rollback Strategy

Preferred rollback:

- Restore the pre-migration Supabase backup if the migration fails or causes broad production issues.

Function-level rollback:

- Restore the previous `generate_slots_from_team_roles(uuid)` function body if only the new slot generation behavior needs to be reverted.
- Keep the nullable `service_slots` columns in place unless there is a specific reason to remove them.

Schema rollback, only if confirmed safe:

```sql
drop index if exists public.ux_service_slots_one_role_instance_per_service;
drop index if exists public.idx_service_slots_team_role_id;

alter table public.service_slots
drop constraint if exists service_slots_role_instance_number_positive;

alter table public.service_slots
drop column if exists role_instance_number;

alter table public.service_slots
drop column if exists team_role_id;

drop index if exists public.ux_team_roles_team_role_name_active;
drop index if exists public.idx_team_roles_team_active_order;

alter table public.team_roles
drop constraint if exists team_roles_quantity_positive;

alter table public.team_roles
drop constraint if exists team_roles_role_name_not_blank;

alter table public.team_roles
drop column if exists updated_at;

alter table public.team_roles
drop column if exists is_active;

alter table public.team_roles
drop column if exists quantity;
```

Do not drop `public.team_roles` during rollback because the table already exists in the live schema and may contain production data.

Post-rollback checks:

- Login works.
- Ministries load.
- Teams load.
- Service instances load.
- Existing service slots load.
- Claim and unclaim still work.
- Admin assignment still works.
- Pending accept and decline still work.
- Monthly schedule still loads.

## 7. Validation Queries

Confirm `team_roles` columns:

```sql
select
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'team_roles'
order by ordinal_position;
```

Confirm `service_slots` columns:

```sql
select
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'service_slots'
order by ordinal_position;
```

Confirm constraints:

```sql
select
  conname as constraint_name,
  conrelid::regclass as table_name,
  pg_get_constraintdef(oid) as constraint_definition,
  convalidated
from pg_constraint
where conrelid in (
  'public.team_roles'::regclass,
  'public.service_slots'::regclass
)
  and conname in (
    'team_roles_role_name_not_blank',
    'team_roles_quantity_positive',
    'service_slots_role_instance_number_positive'
  )
order by table_name, constraint_name;
```

Confirm indexes:

```sql
select
  schemaname,
  tablename,
  indexname,
  indexdef
from pg_indexes
where schemaname = 'public'
  and indexname in (
    'idx_team_roles_team_active_order',
    'idx_team_roles_team_id',
    'ux_team_roles_team_role_name_active',
    'idx_service_slots_team_role_id',
    'idx_service_slots_service_instance_id',
    'idx_service_slots_assigned_user_id',
    'idx_service_slots_slot_status',
    'ux_service_slots_one_role_instance_per_service'
  )
order by tablename, indexname;
```

Confirm slot generation function:

```sql
select
  proname,
  pg_get_function_arguments(pg_proc.oid) as arguments,
  pg_get_function_result(pg_proc.oid) as result_type
from pg_proc
join pg_namespace
  on pg_namespace.oid = pg_proc.pronamespace
where pg_namespace.nspname = 'public'
  and proname = 'generate_slots_from_team_roles';
```

Expected function:

```text
generate_slots_from_team_roles(p_service_instance_id uuid) returns void
```

List configured team roles:

```sql
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
```

Find teams without active roles:

```sql
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
```

Preview generated slot labels:

```sql
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
```

Find duplicate generated role instances:

```sql
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
```

Expected result:

```text
0 rows
```

Find service slot and team role mismatches:

```sql
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
```

Expected result:

```text
0 rows
```

Find status and assignment inconsistencies:

```sql
select
  *
from public.service_slots
where
  (slot_status = 'open' and assigned_user_id is not null)
  or
  (slot_status in ('pending', 'taken') and assigned_user_id is null);
```

Expected result:

```text
0 rows
```

Audit existing overlapping assignments:

```sql
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
```

## 8. Expected `TeamRolesPage` Behavior After Migration

After the schema migration is applied, `TeamRolesPage` should no longer show a schema mismatch error for missing `team_roles.quantity`.

Expected admin behavior:

- Admin users can open the Teams page.
- Admin users can see the `Manage Roles` action for each team.
- Admin users can open `TeamRolesPage`.
- `TeamRolesPage` loads role rows for the selected team.
- Each role row displays:
  - role name
  - quantity
  - generated slot preview
  - display order
  - active or inactive status
- The page displays total generated slots per service.
- If a team has no roles, the page displays the read-only empty state.

Expected non-admin behavior:

- Non-admin users can open the Teams page.
- Non-admin users do not see the `Manage Roles` action.
- Non-admin users should not be able to reach role management through normal navigation.

Expected existing scheduling behavior:

- Existing team navigation to `ServiceInstancesPage` still works.
- Existing service slots still load.
- Existing claim and unclaim flows remain unchanged.
- Existing admin assignment remains unchanged.
- Existing pending assignment accept and decline remain unchanged.

## 9. Test Plan Using Andy And Tejus Accounts

Use these accounts only for validation testing. Do not create, modify, or delete production data.

Admin test account:

```text
Email: andy@knuth.com
Password: Password123
```

Non-admin test account:

```text
Email: Tejus@knuth.com
Password: Password123
```

### Andy Admin Validation

1. Sign in as `andy@knuth.com`.
2. Confirm the app loads the authenticated home page.
3. Open a ministry.
4. Open the Teams page.
5. Confirm each team row shows the admin menu.
6. Open the menu and confirm `Manage Roles` is visible.
7. Select `Manage Roles`.
8. Confirm `TeamRolesPage` opens without crashing.
9. Confirm role rows display when roles exist.
10. Confirm the empty state displays when the selected team has no roles.
11. Confirm quantity and generated slot preview render correctly.
12. Return to Teams.
13. Select a team row directly.
14. Confirm existing navigation to `ServiceInstancesPage` still works.

### Tejus Non-Admin Validation

1. Sign out from the Andy account.
2. Sign in as `Tejus@knuth.com`.
3. Confirm the app loads the authenticated home page.
4. Open a ministry.
5. Open the Teams page.
6. Confirm the admin menu is not visible.
7. Confirm `Manage Roles` is not visible.
8. Select a team row directly.
9. Confirm existing navigation to `ServiceInstancesPage` still works.

### No-Data-Mutation Rule

During this validation:

- Do not create service instances.
- Do not claim slots.
- Do not unclaim slots.
- Do not assign users.
- Do not accept pending assignments.
- Do not decline pending assignments.
- Do not edit team roles.
