# Team Role UI Implementation Plan

## Scope

Build admin-facing Flutter UI for managing `team_roles` records. This is a planning document only. No code, SQL, or Supabase data should be changed as part of this document.

The feature must preserve:

- Existing authentication flow.
- Ministry separation.
- Existing team and service navigation.
- Claim/unclaim workflow.
- Admin assignment workflow.
- Pending assignment workflow.
- Database-driven slot generation through `generate_slots_from_team_roles`.

## Current Repository Fit

The app currently uses a simple page-based architecture:

- Pages live under `lib/pages/`.
- Each page owns its own Supabase calls and local `setState` state.
- Navigation uses `Navigator.push` with `MaterialPageRoute`.
- Admin checks are currently done by reading `profiles.role`.
- `TeamsPage` currently lists teams and opens `ServiceInstancesPage` when a team row is tapped.

The Team Role Management UI should follow this existing style for the first implementation rather than introducing a new router, state management package, or repository layer.

## 1. Exact Flutter Files To Create

Create one new page file:

```text
lib/pages/team_roles_page.dart
```

Purpose:

- Load roles for a selected team.
- Display active and inactive roles.
- Add roles.
- Edit roles.
- Update quantity.
- Update display order.
- Deactivate/reactivate roles.

Recommended contents:

- `TeamRolesPage extends StatefulWidget`
- `_TeamRolesPageState`
- Local Supabase client reference, matching existing pages.
- Local methods:
  - `_loadCurrentUserRole`
  - `_loadTeamRoles`
  - `_showAddRoleDialog`
  - `_showEditRoleDialog`
  - `_saveRole`
  - `_deactivateRole`
  - `_reactivateRole`
  - `_moveRoleUp`
  - `_moveRoleDown`
  - `_generatedLabelsFor`
  - `_validateRoleName`
  - `_validateQuantity`

Do not create model, repository, or widget files in the first pass unless the implementation becomes too large. The current codebase keeps logic inside pages, so one page file is the most consistent first slice.

## 2. Exact Flutter Files To Modify

Modify this file:

```text
lib/pages/teams_page.dart
```

Required changes:

- Import `team_roles_page.dart`.
- Load current user profile role, or accept an admin flag from parent if that is added later.
- Track `_isAdmin`.
- Preserve existing team row tap behavior that opens `ServiceInstancesPage`.
- Add an admin-only role management entry for each team.

Recommended UI change:

- Keep team row `onTap` unchanged.
- Change `trailing` to admin-only `PopupMenuButton` or `IconButton`.
- Add `Manage Roles` action that opens `TeamRolesPage`.

Avoid modifying these files in the first pass:

```text
lib/app.dart
lib/main.dart
lib/pages/home_page.dart
lib/pages/service_instances_page.dart
lib/pages/service_slots_page.dart
lib/pages/monthly_schedule_page.dart
lib/pages/my_schedule_page.dart
lib/pages/pending_assignments_page.dart
lib/pages/my_availability_page.dart
```

They are not required for the first Team Role Management UI slice.

## 3. Navigation Changes Required

Current flow:

```text
HomePage -> TeamsPage -> ServiceInstancesPage -> ServiceSlotsPage
```

New admin-only side path:

```text
HomePage
`-- TeamsPage
    |-- tap team -> ServiceInstancesPage
    `-- admin action -> TeamRolesPage
```

`TeamRolesPage` constructor should receive:

```text
teamId
teamName
ministryId
ministryName
```

Minimum required constructor fields:

```text
teamId
teamName
ministryName
```

Recommended navigation from `TeamsPage`:

```text
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => TeamRolesPage(
      ministryId: widget.ministryId,
      ministryName: widget.ministryName,
      teamId: team['id'],
      teamName: team['name'],
    ),
  ),
)
```

No named routes are needed because the current app does not use named routes.

## 4. TeamRolesPage Wireframe

### Mobile Wireframe

```text
AppBar
------------------------------------------------
< Back              Team Roles              +

Ministry Name
Team Name

Active roles: 5       Slots/service: 7

[Role Card]
Worship Leader
Qty 1 · Generates: Worship Leader
                         [edit] [more]

[Role Card]
Backup Singer
Qty 3 · Generates:
Backup Singer 1, Backup Singer 2, Backup Singer 3
                         [edit] [more]

[Inactive Section Toggle]
Show inactive roles

FAB: +
```

### Tablet/Desktop Wireframe

```text
AppBar
------------------------------------------------
Team Roles                         + Add Role

Ministry Name / Team Name
Active roles: 5 | Slots per service: 7

------------------------------------------------
Order | Role Name       | Qty | Generates        | Status | Actions
------------------------------------------------
  10  | Worship Leader  |  1  | Worship Leader   | Active | Edit ...
  20  | Keyboardist     |  1  | Keyboardist      | Active | Edit ...
  50  | Backup Singer   |  3  | Backup Singer... | Active | Edit ...
------------------------------------------------
```

### Page States

Loading:

```text
Centered CircularProgressIndicator
```

Error:

```text
Failed to load team roles: <message>
[Retry]
```

Empty active roles:

```text
No active roles configured.
New services for this team will not generate slots until roles are added.
[Add Role]
```

Non-admin access:

```text
You do not have permission to manage team roles.
```

## 5. Add/Edit Role Dialog Wireframe

### Mobile Bottom Sheet Or Full-Screen Dialog

```text
Add Role
------------------------------------------------
Role Name
[________________________]

Quantity
[-]  1  [+]

Preview
Worship Leader

Display Order
[10]

[Cancel]                       [Save]
```

Edit mode:

```text
Edit Role
------------------------------------------------
Role Name
[Backup Singer___________]

Quantity
[-]  3  [+]

Preview
Backup Singer 1
Backup Singer 2
Backup Singer 3

Display Order
[50]

Active
[on]

Existing service slots will not be changed automatically.

[Cancel]                       [Save]
```

### Tablet/Desktop Dialog

```text
------------------------------------------------
Edit Role

Role Name                  Quantity
[Backup Singer        ]    [-] 3 [+]

Display Order              Active
[50                  ]      [toggle]

Generated Slot Preview
Backup Singer 1
Backup Singer 2
Backup Singer 3

Existing service slots will not be changed automatically.

                         [Cancel] [Save]
------------------------------------------------
```

## 6. Supabase Queries Required

### Admin Permission Check

Load current profile role:

```text
profiles
select role
where id = currentUser.id
single
```

Expected admin condition:

```text
lower(trim(role)) == 'admin'
```

### Load Team Roles

Table:

```text
team_roles
```

Query:

```text
select id, team_id, role_name, quantity, display_order, is_active, created_at, updated_at
eq team_id <teamId>
order display_order
order role_name
```

### Add Role

Insert:

```text
team_roles.insert({
  team_id,
  role_name,
  quantity,
  display_order,
  is_active: true
})
```

### Edit Role

Update by `id`:

```text
team_roles.update({
  role_name,
  quantity,
  display_order,
  is_active
}).eq('id', roleId)
```

### Deactivate Role

Soft deactivate:

```text
team_roles.update({
  is_active: false
}).eq('id', roleId)
```

### Reactivate Role

Soft reactivate:

```text
team_roles.update({
  is_active: true
}).eq('id', roleId)
```

### Reorder Roles

For up/down buttons:

```text
team_roles.update({ display_order: newOrder }).eq('id', roleId)
```

If swapping two rows, update both rows and then reload.

### Duplicate Name Validation Query

Before insert/update:

```text
team_roles
select id
eq team_id <teamId>
ilike role_name <trimmedRoleName>
eq is_active true
```

For edit mode, ignore the current role id in Dart after fetching, or use a not-equal filter if supported by the Supabase client version.

Database unique index should remain the final authority.

## 7. Admin Permission Checks

Client-side checks:

- `TeamsPage` should only show `Manage Roles` for admins.
- `TeamRolesPage` should load the current user profile and block non-admin users.
- Add/edit/deactivate/reactivate actions should be disabled when `_isAdmin == false`.

Server-side checks:

- RLS policies on `team_roles` must enforce admin-only insert/update/delete.
- Client-side checks are for UX only, not security.

Failure handling:

- If RLS rejects a write, show a friendly SnackBar:
  - `You do not have permission to manage team roles.`
- If the user session is missing, show:
  - `User not logged in.`

## 8. Mobile Layout Design

Use a single-column layout.

Recommended structure:

- `Scaffold`
- `AppBar`
- Summary block
- `RefreshIndicator`
- `ListView`
- `FloatingActionButton` for add role

Role card details:

- Primary line: role name.
- Secondary line: `Qty X`.
- Preview line: generated labels.
- Trailing: edit icon or overflow menu.

Actions:

- Tap card: edit.
- Overflow menu:
  - Move up.
  - Move down.
  - Deactivate or Reactivate.

Quantity control:

- Stepper row:
  - minus icon button
  - numeric text
  - plus icon button

Mobile constraints:

- Avoid tables.
- Avoid horizontal scroll.
- Keep preview wrapping readable.
- Put destructive actions behind confirmation.
- Use full-width form fields.

## 9. Tablet/Desktop Layout Design

Use a wider layout when screen width is at least roughly `700`.

Recommended structure:

- `Scaffold`
- `AppBar`
- Constrained content width or responsive two-pane layout
- Header summary
- Data-table-like list

Role row columns:

- Order controls.
- Role name.
- Quantity.
- Generated preview.
- Active status.
- Actions.

Editor behavior:

- Tablet: centered dialog or side panel.
- Desktop: centered dialog is sufficient for first pass.

Tablet/desktop constraints:

- Keep touch targets large enough.
- Do not nest cards inside cards.
- Use dense but readable rows.
- Align quantity and actions consistently.

## 10. State Management Approach Using Current Architecture

Use the existing local `StatefulWidget` pattern.

`TeamRolesPage` local state:

```text
bool _isLoading
bool _isSaving
bool _isAdmin
bool _showInactive
String? _message
List<Map<String, dynamic>> _roles
Map<String, dynamic>? _profile
```

Methods:

- `_loadData()` loads admin status and roles.
- `_loadAdminStatus()` queries `profiles.role`.
- `_loadRoles()` queries `team_roles`.
- `_activeRoles` computed getter filters `is_active == true`.
- `_inactiveRoles` computed getter filters `is_active == false`.
- `_totalGeneratedSlots` sums active role quantities.
- `_generatedLabels(roleName, quantity)` returns display labels.

Dialog state:

- Use `StatefulBuilder` inside `showDialog` or a dedicated private dialog widget in the same file.
- Use `TextEditingController` for role name, quantity, and display order.
- Dispose controllers if implemented as a widget; if using `showDialog`, keep controller lifetime scoped and dispose after await where practical.

Why not introduce Provider/Riverpod/BLoC:

- The current app does not use a shared state management package.
- This feature is scoped to one admin page.
- Local state keeps the first implementation reviewable.

## 11. Risks And Compatibility Considerations

### Existing Navigation Risk

`TeamsPage` currently uses the whole row tap to open services. Adding role management must not replace or confuse this behavior.

Mitigation:

- Keep row tap unchanged.
- Put role management behind an admin-only trailing action or overflow menu.

### Admin Check Duplication

Admin role loading already happens in multiple pages. Adding another local check increases duplication.

Mitigation:

- Accept duplication for the first pass to match current architecture.
- Later refactor profile/admin state into a shared service.

### Database Migration Dependency

The UI requires `team_roles` to exist.

Mitigation:

- Implement only after migrations are applied in development/staging.
- Show a clear error if the table/query fails.

### Existing Services Behavior

Changing a role should not mutate existing service slots.

Mitigation:

- UI copy must explicitly state changes affect future services only.
- Do not call slot generation or backfill RPC from this UI in the first pass.

### Quantity Decrease Risk

Admins may expect reducing quantity to remove existing slots.

Mitigation:

- State clearly that existing slots remain unchanged.
- Keep repair/regeneration tools out of the first UI.

### Duplicate Role Names

Users may try to create duplicate active roles for the same team.

Mitigation:

- Validate in UI.
- Rely on database unique index as final protection.

### RLS/Permission Failures

Client may show admin controls but database policy may reject mutation.

Mitigation:

- Catch `PostgrestException`.
- Show permission-specific friendly messages where possible.

### Ordering Conflicts

Concurrent admin edits could produce duplicate display orders.

Mitigation:

- Reload after updates.
- Keep order best-effort in first pass.
- Normalize display order values after reorder.

## 12. Incremental Implementation Phases

### Phase 1: Read-Only Page

Files:

- Create `lib/pages/team_roles_page.dart`.
- Modify `lib/pages/teams_page.dart`.

Work:

- Add admin-only navigation to `TeamRolesPage`.
- Load and display roles for a team.
- Show active roles and total generated slots.
- Show generated label preview.
- Show inactive roles behind a toggle.

Verification:

- Non-admin users do not see manage roles action.
- Admin users can open the page.
- Existing team tap still opens services.

### Phase 2: Add Role

Work:

- Add `Add Role` action.
- Build add dialog.
- Validate role name and quantity.
- Insert `team_roles` row.
- Reload list.

Verification:

- Quantity `1` preview is unnumbered.
- Quantity `3` preview is numbered.
- Duplicate active role names are blocked.

### Phase 3: Edit Role

Work:

- Tap role to edit.
- Update role name, quantity, and display order.
- Show existing-services warning.
- Reload list after save.

Verification:

- Edits affect `team_roles`.
- Existing services and slots are not touched.

### Phase 4: Deactivate And Reactivate

Work:

- Add deactivate confirmation.
- Add inactive roles section.
- Add reactivate action.

Verification:

- Deactivated roles stop appearing in active total.
- Inactive roles remain visible when toggled.

### Phase 5: Ordering

Work:

- Add up/down ordering controls.
- Update `display_order`.
- Normalize display order values.

Verification:

- Roles appear in intended order.
- Generated preview order follows role order.

### Phase 6: Responsive Polish

Work:

- Add width-based layout switch.
- Mobile uses cards.
- Tablet/desktop uses table-like rows.

Verification:

- No text overflow on narrow screens.
- Actions remain reachable on tablet/desktop.

## Out Of Scope For First Implementation

- Writing SQL migrations.
- Running migrations.
- Applying role changes to existing service instances.
- Regenerating slots from the UI.
- Adding double-booking triggers.
- Replacing current direct Supabase page calls with repositories.
- Introducing a new state management package.
- Modifying claim/unclaim/admin assignment/pending assignment behavior.
