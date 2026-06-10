# Team Role Architecture

## Purpose

Service slots should be generated from roles configured on each team. Each team role has a role name and a quantity. When a service instance is created for a team, the application should automatically create the correct number of service slots for that team's configured roles.

Examples:

Main Worship Team:

- Worship Leader (1)
- Keyboardist (1)
- Guitarist (1)
- Drummer (1)
- Backup Singer (3)

Kids Worship Team:

- Worship Leader (1)
- Keyboardist (1)
- Guitarist (1)
- Drummer (1)
- Backup Singer (2)

Children's Ministry Team:

- Teacher (1)
- Assistant Teacher (2)
- Check-In (2)
- Security (1)

This replaces the older fixed-role plan. Roles are team-defined, and each role controls how many slots should be generated.

## Current Baseline

The existing Flutter app already has a compatible service-slot model:

- `service_instances` stores `ministry_id` and `team_id`.
- `service_slots` stores assignable slots for a service instance.
- Slot screens display `role_name ?? slot_name`.
- Claim, unclaim, admin assignment, pending accept, and pending decline update `service_slots` by `id`.
- `MonthlySchedulePage` counts slots by `slot_status`.
- Service creation already calls `generate_slots_from_team_roles(p_service_instance_id)`.

The recommended approach is database-first:

- Preserve the existing `service_slots` table and slot statuses.
- Preserve the existing RPC function name.
- Add a `team_roles` table with `role_name` and `quantity`.
- Generate one service slot per quantity unit.
- Keep generated `slot_name` and `role_name` readable for the current Flutter UI.

## 1. Database Design

### Tables To Preserve

The feature should keep these existing tables and relationships:

- `ministries`
- `teams`
- `service_instances`
- `service_slots`
- `profiles`
- `service_availability`

Ministry separation remains anchored by:

```text
service_slots -> service_instances -> teams -> ministries
```

### New Table

Add:

- `team_roles`

This table defines the role template for a team. It does not replace `service_slots`; it drives slot generation.

### Service Slot Link

Add nullable metadata columns to `service_slots`:

- `team_role_id`
- `role_instance_number`

These columns allow the database to know which team role generated a slot and which numbered instance it represents.

Example:

```text
team_roles.role_name = Backup Singer
team_roles.quantity = 3

Generated service_slots:
Backup Singer 1, role_instance_number = 1
Backup Singer 2, role_instance_number = 2
Backup Singer 3, role_instance_number = 3
```

For quantity `1`, the generated display label should stay clean:

```text
Worship Leader
Keyboardist
Teacher
Security
```

## 2. `team_roles` Table Design

Recommended schema:

```sql
create table if not exists public.team_roles (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  role_name text not null,
  quantity integer not null default 1,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint team_roles_role_name_not_blank check (length(trim(role_name)) > 0),
  constraint team_roles_quantity_positive check (quantity > 0)
);
```

Recommended constraints and indexes:

```sql
create unique index if not exists ux_team_roles_team_role_name_active
on public.team_roles (team_id, lower(role_name))
where is_active = true;

create index if not exists idx_team_roles_team_active_order
on public.team_roles (team_id, is_active, display_order);
```

Recommended columns:

- `id`: stable role identifier.
- `team_id`: team that owns this role.
- `role_name`: base display name, such as `Backup Singer`.
- `quantity`: number of slots to generate per service.
- `display_order`: order in admin role management and slot generation.
- `is_active`: disables a role for future services without deleting history.
- `created_at` and `updated_at`: audit timestamps.

Do not make `role_name` globally unique. The same role name can exist for multiple teams.

## 3. Quantity Support

Quantity controls how many slots are generated for one team role.

Rules:

- Quantity must be a positive integer.
- Quantity `1` generates one slot with the base role name.
- Quantity greater than `1` generates numbered slots using the base role name plus the instance number.
- Existing generated slots should not be deleted automatically if a quantity is reduced later.
- New service instances should use the active quantity at creation time.

Examples:

| Role Name | Quantity | Generated Slots |
| --- | ---: | --- |
| Worship Leader | 1 | Worship Leader |
| Backup Singer | 3 | Backup Singer 1, Backup Singer 2, Backup Singer 3 |
| Assistant Teacher | 2 | Assistant Teacher 1, Assistant Teacher 2 |
| Check-In | 2 | Check-In 1, Check-In 2 |

Recommended `service_slots` additions:

```sql
alter table public.service_slots
add column if not exists team_role_id uuid null
references public.team_roles(id) on delete set null;

alter table public.service_slots
add column if not exists role_instance_number integer null;

alter table public.service_slots
add constraint service_slots_role_instance_number_positive
check (role_instance_number is null or role_instance_number > 0)
not valid;
```

Recommended uniqueness:

```sql
create unique index if not exists ux_service_slots_one_role_instance_per_service
on public.service_slots (
  service_instance_id,
  team_role_id,
  role_instance_number
)
where team_role_id is not null
  and role_instance_number is not null;
```

This lets one service have `Backup Singer 1`, `Backup Singer 2`, and `Backup Singer 3`, while preventing duplicate `Backup Singer 2` rows for the same service.

## 4. Migration Strategy

Generate SQL migration scripts only. Do not execute them in this planning step.

### Migration 1: Create Team Roles

Suggested file:

```text
supabase/migrations/YYYYMMDDHHMMSS_create_team_roles.sql
```

Include:

- Create `team_roles`.
- Add `quantity` constraints.
- Add uniqueness for active role names per team.
- Add team/order indexes.
- Add RLS policies for read access and admin-only writes.

### Migration 2: Extend Service Slots

Suggested file:

```text
supabase/migrations/YYYYMMDDHHMMSS_extend_service_slots_for_team_roles.sql
```

Include:

- Add nullable `team_role_id`.
- Add nullable `role_instance_number`.
- Add positive instance-number check as `not valid`.
- Add unique index on `(service_instance_id, team_role_id, role_instance_number)`.
- Add indexes for `team_role_id`, `assigned_user_id`, `service_instance_id`, and `slot_status` if missing.

### Migration 3: Update Slot Generation RPC

Suggested file:

```text
supabase/migrations/YYYYMMDDHHMMSS_generate_slots_from_team_role_quantities.sql
```

Include:

- Keep the existing function name `generate_slots_from_team_roles`.
- Read `team_id` from the target service instance.
- Read active roles and quantities from `team_roles`.
- Use `generate_series(1, quantity)` to generate numbered instances.
- Insert missing slots idempotently.
- Populate `slot_name`, `role_name`, `team_role_id`, `role_instance_number`, `slot_status`, `assigned_user_id`, and `color_code`.

Example function shape:

```sql
create or replace function public.generate_slots_from_team_roles(
  p_service_instance_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_team_id uuid;
begin
  select team_id
  into v_team_id
  from public.service_instances
  where id = p_service_instance_id;

  if v_team_id is null then
    raise exception 'Service instance not found: %', p_service_instance_id;
  end if;

  insert into public.service_slots (
    service_instance_id,
    team_role_id,
    role_instance_number,
    slot_name,
    role_name,
    slot_status,
    assigned_user_id,
    color_code
  )
  select
    p_service_instance_id,
    tr.id,
    role_instances.instance_number,
    case
      when tr.quantity = 1 then tr.role_name
      else tr.role_name || ' ' || role_instances.instance_number::text
    end,
    case
      when tr.quantity = 1 then tr.role_name
      else tr.role_name || ' ' || role_instances.instance_number::text
    end,
    'open',
    null,
    'amber'
  from public.team_roles tr
  cross join lateral generate_series(1, tr.quantity) as role_instances(instance_number)
  where tr.team_id = v_team_id
    and tr.is_active = true
  order by tr.display_order, tr.role_name, role_instances.instance_number
  on conflict (service_instance_id, team_role_id, role_instance_number) do nothing;
end;
$$;
```

### Migration 4: Seed Initial Team Roles

Suggested file:

```text
supabase/migrations/YYYYMMDDHHMMSS_seed_initial_team_roles.sql
```

Seed role definitions by existing team names. Use actual production/staging team names from an audit query before finalizing the script.

Example shape:

```sql
insert into public.team_roles (team_id, role_name, quantity, display_order)
select id, 'Worship Leader', 1, 10
from public.teams
where name = 'Main Worship Team'
on conflict do nothing;
```

The final seed script should include every approved team and role mapping.

### Migration 5: Harden Slot Integrity

Suggested file:

```text
supabase/migrations/YYYYMMDDHHMMSS_harden_service_slot_integrity.sql
```

Include:

- Valid `slot_status` constraint.
- Open slots must be unassigned.
- Pending/taken slots must be assigned.
- One user cannot hold multiple pending/taken slots in the same service.
- Trigger-based cross-service overlap prevention.

Add constraints as `not valid` first if existing data may need cleanup.

## 5. Backfill Strategy

Backfill must be conservative. It should preserve existing features and never remove assigned work.

### Step 1: Audit Existing Data

Generate read-only SQL to inspect:

- Existing team names.
- Existing ministry/team relationships.
- Existing service slot labels by team.
- Existing assigned slots.
- Existing pending assignments.
- Existing duplicate slot labels.
- Existing overlap conflicts.
- Existing inconsistent slot status rows.

Example:

```sql
select
  m.name as ministry_name,
  t.name as team_name,
  coalesce(ss.role_name, ss.slot_name) as slot_label,
  count(*) as usage_count
from public.service_slots ss
join public.service_instances si on si.id = ss.service_instance_id
join public.teams t on t.id = si.team_id
join public.ministries m on m.id = si.ministry_id
group by m.name, t.name, coalesce(ss.role_name, ss.slot_name)
order by m.name, t.name, slot_label;
```

### Step 2: Seed `team_roles`

Create team roles from approved team configuration:

Main Worship Team:

- Worship Leader, quantity 1
- Keyboardist, quantity 1
- Guitarist, quantity 1
- Drummer, quantity 1
- Backup Singer, quantity 3

Kids Worship Team:

- Worship Leader, quantity 1
- Keyboardist, quantity 1
- Guitarist, quantity 1
- Drummer, quantity 1
- Backup Singer, quantity 2

Children's Ministry Team:

- Teacher, quantity 1
- Assistant Teacher, quantity 2
- Check-In, quantity 2
- Security, quantity 1

Use exact `teams.name` values from the database. If current names differ, migration scripts should match current data instead of these example labels.

### Step 3: Link Existing Slots Where Safe

For existing slots:

- Match through `service_instances.team_id`.
- Match `role_name` or `slot_name` to either the base role name or generated numbered names.
- Set `team_role_id` and `role_instance_number` only when the match is unambiguous.
- Do not change assigned users.
- Do not change pending/taken/open status.
- Do not change color code.

Matching examples:

- `Backup Singer 1` -> `Backup Singer`, instance 1
- `Backup Singer 2` -> `Backup Singer`, instance 2
- `Assistant Teacher 1` -> `Assistant Teacher`, instance 1
- `Teacher` -> `Teacher`, instance 1

### Step 4: Insert Missing Slots

After linking safe existing slots:

- For each service instance, generate missing slots from active team roles and quantities.
- Do not delete legacy or unmatched slots.
- Do not overwrite assigned slots.
- Use the same RPC or equivalent migration query to keep behavior consistent.

### Step 5: Validate

Before validating constraints, verify:

- No duplicate `(service_instance_id, team_role_id, role_instance_number)` rows.
- No invalid `slot_status` values.
- No `open` rows with an assigned user.
- No `pending` or `taken` rows without an assigned user.
- No existing overlapping pending/taken assignments.

## 6. Slot Generation Workflow

### Current Flow To Preserve

1. Admin creates a service instance.
2. Flutter inserts a row into `service_instances`.
3. Flutter calls `generate_slots_from_team_roles(p_service_instance_id)`.
4. The database creates service slots.

### New Quantity-Aware Flow

1. Admin creates a service instance for a team.
2. RPC loads the service instance.
3. RPC reads `service_instances.team_id`.
4. RPC loads active `team_roles` for that team.
5. For each role, RPC generates `quantity` slot rows.
6. For quantity `1`, the generated label is the base role name.
7. For quantity greater than `1`, generated labels are numbered.
8. Each generated slot starts as open and unassigned.
9. Existing claim/unclaim/admin/pending flows continue to update those slots.

### Idempotency

The generator must be safe to call more than once. This is handled by:

```text
unique(service_instance_id, team_role_id, role_instance_number)
```

and:

```sql
on conflict (service_instance_id, team_role_id, role_instance_number) do nothing
```

## 7. Flutter Impact

### No-Code Compatibility

The current Flutter app should continue working if the migrations populate `role_name` and `slot_name`:

- `ServiceSlotsPage` displays dynamic slot labels.
- `MonthlySchedulePage` counts slots by status.
- `MySchedulePage` displays assigned slot labels.
- `PendingAssignmentsPage` displays pending slot labels.
- Claim/unclaim/admin assignment/pending response flows mutate existing slot fields by `id`.

No Flutter code changes are required for the database-only migration phase.

### Later Flutter Enhancements

Future app changes should add:

- Admin team role management screens.
- Role quantity editing controls.
- Slot ordering by `team_roles.display_order` and `role_instance_number`.
- Friendly error messages for double-booking violations.
- A warning when creating a service for a team with no active roles.
- Typed Dart models for team roles and service slots.
- A Supabase repository/service layer.

## 8. Admin UI Changes

Admin UI should let admins manage roles per team after the database foundation is in place.

Recommended capabilities:

- View roles for a selected team.
- Add a role.
- Edit role name.
- Edit quantity.
- Reorder roles.
- Deactivate/reactivate roles.
- Show whether a role has generated historical slots.

Recommended fields:

- Role Name: text input.
- Quantity: numeric stepper or integer input, minimum 1.
- Display Order: drag handle or numeric field.
- Active: toggle.

Important behavior:

- Prefer deactivate over delete.
- Do not automatically remove historical service slots when quantity decreases.
- For future service instances, use the latest active role configuration.
- If admins want new role quantities applied to existing future services, provide an explicit repair/regenerate action later.

## 9. Double-Booking Impact

Team role quantities increase the number of slots, but they should not change assignment safety rules.

### Same-Service Protection

A user should not be assigned to more than one pending or taken slot in the same service instance, even if there are multiple role slots.

Recommended unique index:

```sql
create unique index if not exists ux_service_slots_one_user_per_service
on public.service_slots (service_instance_id, assigned_user_id)
where assigned_user_id is not null
  and slot_status in ('pending', 'taken');
```

### Cross-Service Protection

A user should not be assigned to overlapping services on the same date, even across ministries.

Use a trigger on `service_slots` that checks:

- New row has `assigned_user_id`.
- New row status is `pending` or `taken`.
- Another row for the same user is already `pending` or `taken`.
- The other row belongs to a different service instance.
- Both services have the same date.
- Time ranges overlap.

Overlap rule:

```text
new_start < existing_end
and
new_end > existing_start
```

### Pending Workflow Preservation

Double-booking checks should apply to both:

- Admin assignment to `pending`.
- Volunteer acceptance from `pending` to `taken`.

This ensures admins cannot accidentally assign conflicts and users cannot accept conflicting assignments.

## 10. Future Scalability Considerations

- The `team_roles` table supports future role additions without database redesign.
- The `quantity` field supports multiple slots for the same role without creating new columns.
- `is_active` supports retiring roles without losing history.
- `team_role_id` preserves historical traceability from generated slots to role definitions.
- `role_instance_number` supports deterministic labels and uniqueness.
- Additional per-role metadata can be added later, such as skill requirements, gender/age constraints, notes, or default visibility.
- Role templates could later be copied between teams if many teams share similar structures.
- Slot generation can later move fully behind secured RPC functions for claim, unclaim, assignment, and acceptance.
- Monthly schedule performance can later improve with aggregate views or RPCs if slot counts grow.
- RLS policies should be kept central and migration-backed so admin-only role management remains enforceable server-side.

## Recommended First Change Set

Keep the first implementation small and reviewable:

1. Create `team_roles` with `role_name` and `quantity`.
2. Extend `service_slots` with `team_role_id` and `role_instance_number`.
3. Update `generate_slots_from_team_roles` to generate slots from team role quantities.
4. Seed initial team roles in SQL using approved team names.
5. Add validation queries and avoid executing migrations until reviewed.

Then follow with separate migrations for:

1. Backfilling existing service slots.
2. Validating slot integrity constraints.
3. Adding double-booking trigger enforcement.
4. Adding admin UI for team role management.
