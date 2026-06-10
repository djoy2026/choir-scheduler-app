# Technical Debt

## Architecture Concerns

- Supabase access is duplicated across pages. Each page creates or references `Supabase.instance.client` and owns its own query logic, which makes behavior harder to audit and test.
- Business rules live in UI widgets. Slot claiming, admin assignment, availability toggling, conflict checks, and role checks are implemented inside page state classes instead of dedicated services.
- Navigation is fully imperative and spread across widgets. This is workable for the current size, but route ownership will become harder to maintain as admin flows and multi-position slots expand.
- Auth state is checked once through `AuthGate` using `currentSession`. There is no central listener for auth state changes, token refresh issues, or session expiration.
- Admin detection is repeated in schedule-related pages by querying `profiles.role`.
- Error handling is inconsistent. Some pages show SnackBars, some store `_message`, and some only log with `debugPrint`.
- Data models are represented as `Map<String, dynamic>` throughout the UI. This makes field usage fragile and increases the chance of runtime errors from missing or renamed columns.
- Backup files under `lib/` contain older app code. Keeping inactive code inside the source tree can make searches noisy and future refactors more error-prone.

## Security Concerns

- Admin authorization appears to be enforced in the client by checking `profiles.role`. Supabase Row Level Security policies and RPC permissions should also enforce admin-only writes.
- Slot claiming and assignment use direct table updates from the client. Database policies, constraints, or secured RPC functions should validate who can update each slot and which status transitions are allowed.
- Profile queries load assignable users from `profiles` for admin assignment. Confirm that non-admin users cannot read broader profile data through Supabase policies.
- Signup creates a Supabase Auth user but the current active signup page does not create a `profiles` row. If profile creation depends on a trigger, that trigger should be documented and migrated.
- `.env` is listed as a Flutter asset in `pubspec.yaml`. This can expose Supabase configuration in app bundles. The anon key is expected in client apps, but the project should confirm no service-role or privileged keys can ever be bundled.
- Conflict prevention is partly inferred from database constraints and partly shown in the UI. Hard prevention should be enforced server-side, especially for cross-ministry double-booking.
- Error messages may expose raw database or PostgREST details to users in some paths.

## Testing Gaps

- `test/widget_test.dart` is currently empty, so there is no automated coverage for core flows.
- No tests cover auth routing through `AuthGate`, login success/failure, signup behavior, or logout navigation.
- No tests cover ministry separation: ministries, teams, services, and slots filtered by the correct ids.
- No tests cover volunteer slot claiming, unclaiming, and duplicate-claim prevention.
- No tests cover admin assignment, pending assignment acceptance, or pending assignment decline.
- No tests cover availability toggling, including insert/delete behavior.
- No tests cover conflict detection in `MySchedulePage`.
- No tests cover monthly schedule counts for open, pending, taken, available, and unavailable totals.
- No tests cover responsive layout behavior on narrow and wide screens.
- No database migration or policy tests are present in the repository.

## Database Improvements

- Add tracked SQL migrations for the current schema if they are not stored elsewhere.
- Document and migrate Row Level Security policies for `profiles`, `ministries`, `teams`, `service_instances`, `service_slots`, and `service_availability`.
- Enforce valid `slot_status` values with a check constraint or enum.
- Enforce valid `availability_status` values with a check constraint or enum.
- Confirm a unique or partial unique constraint prevents one user from taking more than one slot in the same service instance.
- Add database-level prevention for overlapping assignments across ministries and teams.
- Consider moving claim, unclaim, admin assign, accept assignment, and decline assignment into RPC functions so transitions are atomic and policy-controlled.
- Add indexes for common filters:
  - `teams.ministry_id`
  - `service_instances.ministry_id`
  - `service_instances.team_id`
  - `service_instances.service_date`
  - `service_slots.service_instance_id`
  - `service_slots.assigned_user_id`
  - `service_slots.slot_status`
  - `service_availability.service_instance_id`
  - `service_availability.user_id`
- Add a uniqueness rule for one availability record per user per service instance.
- Document `generate_slots_from_team_roles`, including expected input, generated roles, and failure behavior.
- Prepare migrations for the upcoming multi-position roles: Worship Leader, Keyboardist, Backup Singer 1, Backup Singer 2, and Backup Singer 3.

## Flutter Improvements

- Introduce typed Dart models for profiles, ministries, teams, service instances, service slots, and availability records.
- Add a small data/service layer around Supabase calls to keep widgets focused on UI.
- Centralize auth/session handling and expose current user/profile state to pages.
- Centralize role checks so admin behavior is consistent.
- Extract repeated date and time formatting helpers.
- Extract repeated loading, empty, and error states into reusable widgets.
- Use forms and validators consistently on signup and service creation flows.
- Add mounted checks consistently before `setState` after async calls.
- Dispose all controllers created in stateful widgets or dialogs where practical.
- Improve responsive layouts for tablets, desktop, and dense admin screens.
- Review inactive backup files and decide whether they belong outside `lib/`.

## Performance Improvements

- Reduce repeated profile role queries by caching the current profile during a session.
- Avoid loading all profiles for assignment until an admin starts an assignment flow, and consider search or pagination if the user list grows.
- Limit nested Supabase selects to only fields used by the UI.
- Add database indexes for date, assigned user, service instance, and status filters.
- Consider server-side aggregate views or RPCs for monthly schedule counts if the service list grows.
- Avoid reloading entire page datasets after small mutations when a local state update is sufficient and safe.
- Add pull-to-refresh consistently where data can change from another user.
- Consider realtime subscriptions for slots or pending assignments if live coordination becomes important.

## Recommended Refactors

1. Create a `services/` or `repositories/` layer for Supabase access.
2. Add typed model classes and mapping helpers for database rows.
3. Centralize auth state and profile loading.
4. Move slot state transitions into dedicated methods or secured RPC functions.
5. Add SQL migrations for schema, constraints, RLS policies, and RPC definitions.
6. Add focused widget tests for auth routing and primary page states.
7. Add integration-style tests or mocked repository tests for scheduling workflows.
8. Extract shared UI components for service cards, slot cards, loading states, and error states.
9. Replace scattered magic strings for statuses and roles with constants or enums.
10. Prepare the slot generation path for the upcoming multi-position service slots feature.
