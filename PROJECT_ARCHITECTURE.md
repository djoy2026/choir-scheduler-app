# Choir Scheduler Project Architecture

## App Purpose

Choir Scheduler is a Flutter application for organizing volunteer service coverage across church ministries. It lets authenticated users view ministry schedules, claim open service slots, unclaim their own assignments, respond to pending admin assignments, and mark themselves unavailable for upcoming services.

The app currently supports multiple ministries, including Main Choir, Kids Choir, and Children's Ministry scheduling. It is designed to preserve separation between ministries while still preventing volunteers from being double-booked across overlapping service times.

## Flutter Architecture

The app is a small, page-oriented Flutter application using Material widgets and direct Supabase calls from each page.

- `lib/main.dart` initializes Flutter bindings, loads `.env`, initializes Supabase with `SUPABASE_URL` and `SUPABASE_ANON_KEY`, then starts `MyApp`.
- `lib/app.dart` defines the shared Supabase client, the root `MaterialApp`, and `AuthGate`.
- `lib/pages/` contains the app screens. Each screen owns its own state, loading flags, error message handling, Supabase queries, and navigation.
- Navigation is imperative with `Navigator.push`, `pushReplacement`, and `pushAndRemoveUntil`.
- State management is local `StatefulWidget` state with `setState`; there is no global state management package.
- Supabase is accessed through `Supabase.instance.client` in each page file.
- UI layout uses standard Flutter widgets such as `Scaffold`, `AppBar`, `Padding`, `Column`, `Wrap`, `ListView`, `Card`, `ListTile`, dialogs, switches, and form fields.

Dependencies currently declared in `pubspec.yaml` include:

- `supabase_flutter` for authentication and database access.
- `flutter_dotenv` for loading Supabase environment variables.
- `intl` through transitive/imported usage for time formatting.
- `table_calendar`, which appears in dependencies and backup code but is not used by the current primary page files.

## Page Hierarchy

```text
main.dart
└── MyApp
    └── AuthGate
        ├── AuthPage
        │   ├── LoginPage
        │   └── SignUpPage
        └── HomePage
            ├── MonthlySchedulePage
            │   └── ServiceSlotsPage
            ├── MySchedulePage
            ├── PendingAssignmentsPage
            ├── MyAvailabilityPage
            └── TeamsPage
                └── ServiceInstancesPage
                    └── ServiceSlotsPage
```

### Auth Pages

- `AuthPage` toggles between login and signup modes.
- `LoginPage` signs users in with email and password, then navigates to `HomePage`.
- `SignUpPage` creates a Supabase auth user with email and password and shows a success/error message.
- `AuthGate` checks `supabase.auth.currentSession` at startup and routes authenticated users to `HomePage`.

### Home And Navigation

- `HomePage` loads the current user's profile from `profiles`.
- `HomePage` loads ministries from `ministries`, ordered by `display_order`.
- It displays quick links for monthly schedule, personal schedule, assignments, and availability.
- It lists ministries and routes into the ministry-specific team and service hierarchy.

### Ministry Drilldown

- `TeamsPage` lists teams filtered by `ministry_id`.
- `ServiceInstancesPage` lists service instances filtered by both `ministry_id` and `team_id`.
- `ServiceSlotsPage` lists slots for a selected service instance.

### Schedule And Availability Pages

- `MonthlySchedulePage` lists current-month service instances across ministries.
- `MySchedulePage` lists taken slots assigned to the current user and flags overlapping assignments.
- `PendingAssignmentsPage` lists pending admin assignments for the current user.
- `MyAvailabilityPage` lists upcoming services and lets the current user toggle unavailable/available status per service.

## Authentication Flow

1. App startup loads `.env` and initializes Supabase.
2. `AuthGate` checks `supabase.auth.currentSession`.
3. If a session exists, the user goes to `HomePage`.
4. If no session exists, the user goes to `AuthPage`.
5. `AuthPage` shows `LoginPage` by default and can toggle to `SignUpPage`.
6. `LoginPage` calls `supabase.auth.signInWithPassword`.
7. On successful login, the app replaces the auth route with `HomePage`.
8. `HomePage` loads the authenticated user's profile from `profiles`.
9. Logout calls `supabase.auth.signOut` and clears navigation back to `AuthPage`.

The current authentication flow depends on Supabase Auth for identity and the `profiles` table for application-level metadata such as first name and role.

## Scheduling Workflow

### Volunteer Claim Flow

1. A user opens a service through either the ministry drilldown or monthly schedule.
2. `ServiceSlotsPage` loads slots from `service_slots` for the selected `service_instance_id`.
3. Open slots display as available.
4. Non-admin users tap an open slot to claim it.
5. The app updates the slot:
   - `slot_status` becomes `taken`.
   - `assigned_user_id` becomes the current user id.
   - `color_code` becomes `green`.
6. The page reloads slots and shows a success message.

The code expects database-level conflict prevention. It specifically handles a PostgREST error containing `ux_service_slots_one_user_per_service` and shows "You already claimed another slot for this service."

### Volunteer Unclaim Flow

1. A user taps their own taken slot from `ServiceSlotsPage` or `MySchedulePage`.
2. The app updates the slot:
   - `slot_status` becomes `open`.
   - `assigned_user_id` becomes `null`.
   - `color_code` becomes `amber`.
3. The current list reloads.

### Admin Assignment Flow

1. Admin status is determined by loading the current user's `profiles.role`.
2. Admins tapping an open slot on `ServiceSlotsPage` see a user selection dialog.
3. Assignable users are loaded from `profiles`.
4. The selected user is assigned with:
   - `slot_status` set to `pending`.
   - `assigned_user_id` set to the selected profile id.
   - `color_code` set to `blue`.
5. The assigned volunteer sees the item on `PendingAssignmentsPage`.
6. Accepting changes the slot to `taken`; declining changes the slot back to `open`.

### Monthly Service Creation Flow

1. Admin users see an add button on `MonthlySchedulePage`.
2. The create dialog loads allowed teams by name:
   - `All Main Choir Volunteers`
   - `All Kids Choir Volunteers`
   - `Children's Ministry Live Schedule`
3. Admin selects team, service type, date, start time, end time, and location.
4. The app inserts a row into `service_instances`.
5. The app calls the Supabase RPC function `generate_slots_from_team_roles` with the new service instance id.
6. The monthly schedule reloads.

### Availability Flow

1. `MyAvailabilityPage` loads upcoming services and nested `service_availability` rows.
2. A user toggles a switch on a service.
3. If an availability row already exists for the current user and service, it is deleted.
4. If none exists, a row is inserted with `availability_status = unavailable`.
5. The local list is updated so the UI reflects the new availability state.

### Conflict Visibility

`MySchedulePage` detects schedule conflicts client-side by comparing the current user's taken assignments. A conflict is shown when two assigned service instances:

- Are on the same `service_date`.
- Have different service instance ids.
- Have overlapping `start_time` and `end_time` values.

Project requirements also call for conflict prevention between ministries. The app appears to rely on database constraints or RPC logic for hard prevention, while this page provides visible conflict detection for already assigned services.

## Current Features

- Supabase email/password login.
- Supabase email/password signup.
- Logout.
- Profile-backed role detection.
- Ministry listing.
- Ministry-specific team listing.
- Team-specific service instance listing.
- Monthly schedule page for the current month.
- Admin service creation from the monthly page.
- Automatic slot generation through `generate_slots_from_team_roles`.
- Slot claiming by volunteers.
- Slot unclaiming by assigned volunteers.
- Admin assignment of users to pending slots.
- Pending assignment acceptance and decline.
- Personal schedule view.
- Client-side conflict highlighting for overlapping assigned services.
- Per-service availability toggling.
- Children's Ministry scheduling support through the existing ministry/team data model and create-service team filter.

## Database Assumptions

The Flutter app assumes the following Supabase tables, columns, relationships, constraints, and functions exist.

### `profiles`

Expected columns:

- `id`
- `first_name`
- `last_name`
- `email`
- `role`

Used for current user metadata, admin checks, display names, and admin assignment user selection.

### `ministries`

Expected columns:

- `id`
- `name`
- `description`
- `display_order`

Used to separate scheduling domains and drive the ministry list on `HomePage`.

### `teams`

Expected columns:

- `id`
- `ministry_id`
- `name`
- `description`

Used to group volunteers and service instances within a ministry.

### `service_instances`

Expected columns:

- `id`
- `ministry_id`
- `team_id`
- `service_name`
- `service_date`
- `start_time`
- `end_time`
- `location`
- `status`

Used as the scheduled service/rehearsal/event record.

### `service_slots`

Expected columns:

- `id`
- `service_instance_id`
- `slot_name`
- `role_name`
- `slot_status`
- `assigned_user_id`
- `color_code`

Expected relationship:

- `service_slots.assigned_user_id` references `profiles.id`, using the relationship name `service_slots_assigned_user_id_fkey`.

Expected statuses:

- `open`
- `pending`
- `taken`

Expected database protection:

- A uniqueness or exclusion rule named or surfaced as `ux_service_slots_one_user_per_service` prevents a user from claiming more than one slot for the same service.
- Additional database rules or RPC logic should prevent double-booking across overlapping ministries, per project requirements.

### `service_availability`

Expected columns:

- `service_instance_id`
- `user_id`
- `availability_status`

Expected status:

- `unavailable`

Used to track volunteer availability per service instance.

### RPC Functions

Expected function:

- `generate_slots_from_team_roles(p_service_instance_id)`

This function is called after creating a service instance and is expected to create the service slots for that instance based on team roles.

## Supabase Integration

Supabase is used for:

- Auth session detection.
- Email/password sign in.
- Email/password sign up.
- Sign out.
- CRUD operations through PostgREST.
- Nested relational selects for service data, slots, profiles, teams, and availability.
- RPC invocation for slot generation.

The app reads Supabase configuration from `.env`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

No SQL migrations are present in the current repository. Per project rules, future database changes should be delivered as SQL migration scripts and should not be executed against production data by the app or by development workflow automation.

## Future Roadmap

### Multi-Position Service Slots

The next planned feature is support for defined positions within each service:

- Worship Leader
- Keyboardist
- Backup Singer 1
- Backup Singer 2
- Backup Singer 3

The current `service_slots` model already has `slot_name` and `role_name`, so this roadmap likely fits the existing slot-based design. The safest path is to add or adjust database seed/migration logic and the `generate_slots_from_team_roles` function so new service instances produce the expected positions without disrupting existing claim, unclaim, admin assignment, and pending assignment flows.

### Recommended Follow-Up Work

- Add migrations documenting the existing schema and constraints if they are not already tracked elsewhere.
- Confirm hard database protection for cross-ministry double-booking.
- Add tests for auth routing, slot status transitions, admin assignment, and conflict detection.
- Consider centralizing Supabase data access once the feature surface grows.
- Improve signup/profile creation if profiles are not created elsewhere by a trigger or admin process.
- Add stronger responsive layout handling for wider screens and dense monthly schedules.
- Extend the service slot generator to create the planned choir positions consistently across relevant teams.
