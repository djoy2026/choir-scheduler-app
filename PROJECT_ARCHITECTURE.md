# Project Architecture

## App Purpose

Choir Scheduler is a Flutter and Supabase application for coordinating church ministry service coverage. It helps volunteers and administrators manage service instances, open role slots, personal assignments, pending assignments, and service availability.

The app currently supports multiple ministry areas, including Main Choir, Kids Choir, and Children's Ministry scheduling. Ministry and team filtering are central to the workflow so each ministry can maintain its own schedule while still supporting conflict awareness across a user's assignments.

## Flutter Architecture

The app uses a simple page-based Flutter structure:

- `lib/main.dart` bootstraps Flutter, loads `.env`, initializes Supabase, and runs `MyApp`.
- `lib/app.dart` defines the root `MaterialApp`, the shared Supabase client reference, and `AuthGate`.
- `lib/pages/` contains the user-facing screens.
- Pages are implemented mostly as `StatefulWidget` classes with local state managed by `setState`.
- Navigation uses Flutter's imperative `Navigator` API with `MaterialPageRoute`.
- Data access is performed directly from page widgets using `Supabase.instance.client`.
- UI is built with Material components such as `Scaffold`, `AppBar`, `ListView`, `Card`, `ListTile`, dialogs, buttons, switches, and form fields.

Primary dependencies:

- `supabase_flutter` for Supabase auth, database queries, updates, deletes, inserts, and RPC calls.
- `flutter_dotenv` for reading Supabase configuration from `.env`.
- `table_calendar` is declared in `pubspec.yaml`, though the current active page files do not appear to use it.
- `intl` is imported by schedule pages for time formatting.

## Page Hierarchy

```text
main.dart
`-- MyApp
    `-- AuthGate
        |-- AuthPage
        |   |-- LoginPage
        |   `-- SignUpPage
        `-- HomePage
            |-- MonthlySchedulePage
            |   `-- ServiceSlotsPage
            |-- MySchedulePage
            |-- PendingAssignmentsPage
            |-- MyAvailabilityPage
            `-- TeamsPage
                `-- ServiceInstancesPage
                    `-- ServiceSlotsPage
```

## Authentication Flow

1. `main.dart` loads environment variables from `.env`.
2. Supabase is initialized with `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. `AuthGate` checks `supabase.auth.currentSession`.
4. Authenticated users are routed to `HomePage`.
5. Unauthenticated users are routed to `AuthPage`.
6. `AuthPage` toggles between `LoginPage` and `SignUpPage`.
7. `LoginPage` calls `supabase.auth.signInWithPassword`.
8. On successful login, the user is sent to `HomePage`.
9. `SignUpPage` calls `supabase.auth.signUp`.
10. `HomePage` loads the user's profile from `profiles`.
11. Logout calls `supabase.auth.signOut` and returns the app to `AuthPage`.

The app uses Supabase Auth for session identity and the `profiles` table for app-specific user data such as name and role.

## Scheduling Workflow

### Ministry Browsing

1. `HomePage` loads ministries from `ministries`, ordered by `display_order`.
2. Selecting a ministry opens `TeamsPage`.
3. `TeamsPage` loads teams filtered by `ministry_id`.
4. Selecting a team opens `ServiceInstancesPage`.
5. `ServiceInstancesPage` loads service instances filtered by `ministry_id` and `team_id`.
6. Selecting a service opens `ServiceSlotsPage`.

### Monthly Schedule

`MonthlySchedulePage` loads all service instances for the current month. It includes nested slot and availability data, then displays counts for open, pending, taken, available, and unavailable coverage.

Admin users can create a service from this page. The flow inserts a `service_instances` row and calls the Supabase RPC function `generate_slots_from_team_roles` to create service slots.

### Slot Claiming

On `ServiceSlotsPage`, users can claim open slots.

When a volunteer claims a slot, the app updates `service_slots`:

- `slot_status` becomes `taken`.
- `assigned_user_id` becomes the current user's id.
- `color_code` becomes `green`.

The app catches Supabase/PostgREST errors and specifically recognizes the database constraint name `ux_service_slots_one_user_per_service`, which implies database-level protection against claiming multiple slots for the same service.

### Slot Unclaiming

Users can unclaim their own slots from `ServiceSlotsPage` or `MySchedulePage`.

When a slot is unclaimed, the app updates `service_slots`:

- `slot_status` becomes `open`.
- `assigned_user_id` becomes `null`.
- `color_code` becomes `amber`.

### Admin Assignment

Admins are identified by reading `profiles.role` and checking for `admin`.

On `ServiceSlotsPage`, admins can tap open slots and choose a user from `profiles`. The app then updates the selected slot:

- `slot_status` becomes `pending`.
- `assigned_user_id` becomes the selected user's id.
- `color_code` becomes `blue`.

Assigned users see pending items on `PendingAssignmentsPage`. Accepting the assignment marks the slot `taken`; declining it clears the assignment and returns the slot to `open`.

### My Schedule

`MySchedulePage` loads `service_slots` assigned to the current user with `slot_status = taken`. It displays service details and allows the user to unclaim a slot.

This page also detects visible conflicts by comparing assigned services on the same date. A conflict is shown when two services overlap by start and end time.

### Availability

`MyAvailabilityPage` loads upcoming service instances with nested `service_availability` rows. A user can toggle their availability for each service.

If a matching availability row exists, the app deletes it and treats the user as available. If no row exists, the app inserts a row with `availability_status = unavailable`.

## Current Features

- User login.
- User signup.
- Logout.
- Profile-based admin detection.
- Ministry list.
- Team list by ministry.
- Service instance list by ministry and team.
- Monthly schedule page.
- Admin service creation.
- Slot generation through Supabase RPC.
- Volunteer slot claiming.
- Volunteer slot unclaiming.
- Admin assignment to pending slots.
- Pending assignment accept/decline.
- Personal schedule view.
- Client-side conflict highlighting for overlapping assignments.
- Per-service availability tracking.
- Children's Ministry scheduling through the existing ministry/team/service model.

## Database Assumptions

The app assumes an existing Supabase schema. No migrations are currently generated or executed by this document.

### `profiles`

Expected purpose: application profile data for Supabase auth users.

Expected fields used by the app:

- `id`
- `first_name`
- `last_name`
- `email`
- `role`

### `ministries`

Expected purpose: top-level ministry separation.

Expected fields used by the app:

- `id`
- `name`
- `description`
- `display_order`

### `teams`

Expected purpose: ministry-specific volunteer or scheduling groups.

Expected fields used by the app:

- `id`
- `ministry_id`
- `name`
- `description`

### `service_instances`

Expected purpose: scheduled services, rehearsals, or special events.

Expected fields used by the app:

- `id`
- `ministry_id`
- `team_id`
- `service_name`
- `service_date`
- `start_time`
- `end_time`
- `location`
- `status`

### `service_slots`

Expected purpose: assignable positions for a service instance.

Expected fields used by the app:

- `id`
- `service_instance_id`
- `slot_name`
- `role_name`
- `slot_status`
- `assigned_user_id`
- `color_code`

Expected status values:

- `open`
- `pending`
- `taken`

Expected relationship:

- `assigned_user_id` references `profiles.id`.
- The relationship is queried as `profiles!service_slots_assigned_user_id_fkey`.

Expected protection:

- A constraint or trigger surfaced as `ux_service_slots_one_user_per_service` prevents one user from claiming multiple slots in the same service.
- The project requirements also require preventing double-booking between ministries, likely through database constraints, triggers, or RPC logic.

### `service_availability`

Expected purpose: per-user availability by service instance.

Expected fields used by the app:

- `service_instance_id`
- `user_id`
- `availability_status`

Expected status value:

- `unavailable`

### RPC Functions

Expected function:

- `generate_slots_from_team_roles(p_service_instance_id)`

The app calls this after creating a service instance. It is expected to create the initial set of `service_slots` for that service.

## Supabase Integration

Supabase is integrated directly into the Flutter pages.

Used capabilities:

- Auth session lookup.
- Email/password login.
- Email/password signup.
- Logout.
- Table selects.
- Nested relational selects.
- Inserts.
- Updates.
- Deletes.
- RPC calls.

Configuration is loaded from `.env`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

The app does not modify Supabase production data as part of local documentation work. Future database changes should be written as SQL migration scripts and reviewed before execution.

## Future Roadmap

The next planned feature is multi-position service slots:

- Worship Leader
- Keyboardist
- Backup Singer 1
- Backup Singer 2
- Backup Singer 3

The current schema already has slot concepts through `service_slots.slot_name` and `service_slots.role_name`, so this feature should fit the existing architecture. The main work is likely to update database migrations, seed data, and the `generate_slots_from_team_roles` RPC function so new services consistently generate those positions.

Recommended future work:

- Add tracked SQL migrations for the current schema if they are not stored elsewhere.
- Confirm hard database-level prevention for cross-ministry double-booking.
- Add tests around login routing, slot claiming, unclaiming, pending assignment responses, and conflict detection.
- Consider moving Supabase access into a small service layer as the app grows.
- Confirm how `profiles` rows are created after signup.
- Improve responsive layouts for larger screens and dense monthly schedules.
