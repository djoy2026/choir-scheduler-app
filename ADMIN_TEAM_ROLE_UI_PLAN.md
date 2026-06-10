# Admin Team Role UI Plan

## Purpose

Admins need a clear way to manage the roles that generate service slots for each team. A role has a name, quantity, display order, and active state. When a new service instance is created for a team, slots are generated from that team's active roles and quantities.

This UI should preserve the existing ministry, team, service, slot, claim/unclaim, pending assignment, and admin assignment flows.

## Navigation Flow

Recommended entry points:

1. `HomePage`
2. Select a ministry
3. `TeamsPage`
4. Select or open team actions
5. `Team Roles Page`

Admin-only access:

- Show role management controls only when `profiles.role == admin`.
- Non-admin users should continue seeing the existing ministry/team/service navigation without role management actions.

Suggested navigation pattern:

```text
HomePage
`-- TeamsPage
    |-- ServiceInstancesPage
    `-- TeamRolesPage (admin only)
```

Options for entry UI:

- Add a small admin icon button on each team row.
- Add an overflow menu on each team row with `Manage Roles`.
- Add a `Manage Roles` button at the top of `ServiceInstancesPage` for admins.

The least disruptive option is an overflow menu on `TeamsPage`, because it keeps the existing team tap behavior intact.

## Screens

### Team Roles Page

Purpose: view and manage the role configuration for one team.

Header content:

- Ministry name.
- Team name.
- Total generated slots per service.
- Active role count.

Main list:

- Role name.
- Quantity.
- Generated labels preview.
- Display order.
- Active/inactive status.
- Edit action.
- Deactivate/reactivate action.

Examples:

```text
Backup Singer
Quantity: 3
Generates: Backup Singer 1, Backup Singer 2, Backup Singer 3
```

For quantity `1`:

```text
Worship Leader
Quantity: 1
Generates: Worship Leader
```

Primary actions:

- Add Role.
- Reorder Roles.
- Save Order if using drag-and-drop with staged changes.

Secondary actions:

- Show inactive roles.
- Refresh.

Empty state:

- If the team has no active roles, show an admin-facing empty state with an `Add Role` action.
- Make it clear that new services for this team will not generate slots until active roles exist.

### Add/Edit Role Screen Or Dialog

Use a dialog on tablet and a full-screen route or bottom sheet on mobile.

Fields:

- Role Name.
- Quantity.
- Display Order.
- Active toggle for edit only.

Actions:

- Save.
- Cancel.

For edit mode, include contextual copy indicating that existing service slots are not automatically changed.

### Role Change Preview

When quantity or role name changes, show a generated slot preview before saving.

Examples:

- `Quantity = 1`: `Teacher`
- `Quantity = 2`: `Assistant Teacher 1`, `Assistant Teacher 2`
- `Quantity = 3`: `Backup Singer 1`, `Backup Singer 2`, `Backup Singer 3`

This makes the quantity behavior obvious without changing existing services.

## Add Role Workflow

1. Admin opens `Team Roles Page`.
2. Admin taps `Add Role`.
3. App opens add role form.
4. Admin enters role name.
5. Admin sets quantity, defaulting to `1`.
6. App previews generated slot labels.
7. Admin saves.
8. App inserts a `team_roles` row with:
   - `team_id`
   - `role_name`
   - `quantity`
   - `display_order`
   - `is_active = true`
9. Role list refreshes.
10. Future service instances for this team generate slots from the new role.

Important behavior:

- Adding a role should not modify existing service instances automatically.
- If admins need the new role added to already-created future services, that should be a separate explicit repair workflow later.

## Edit Role Workflow

1. Admin opens `Team Roles Page`.
2. Admin selects edit on a role.
3. App opens edit form with current values.
4. Admin changes role name, quantity, display order, or active state.
5. App shows generated slot preview.
6. App warns that existing service slots will not be automatically renamed, removed, or added.
7. Admin saves.
8. App updates the `team_roles` row.
9. Role list refreshes.

Recommended edit behavior:

- Role name changes affect future generated slots.
- Quantity changes affect future generated slots.
- Display order changes affect future generated slot ordering.
- Existing service slots remain unchanged unless a future explicit repair tool is added.

## Quantity Management

Quantity should be edited with controls that reduce invalid input:

- Mobile: stepper with minus and plus buttons plus numeric value.
- Tablet: numeric input with stepper controls.
- Minimum value: `1`.
- No empty value.
- No decimals.
- No negative values.

Preview rules:

- Quantity `1` uses the base role name with no number.
- Quantity greater than `1` appends a 1-based number.

Examples:

```text
Guitarist (1) -> Guitarist
Backup Singer (3) -> Backup Singer 1, Backup Singer 2, Backup Singer 3
Check-In (2) -> Check-In 1, Check-In 2
```

Large quantity guardrail:

- The database allows positive integers, but the UI should use a practical limit, such as `20`, unless leadership approves a larger limit.
- If a team needs more than the UI limit, it should be treated as an explicit product decision.

## Display Ordering

Display order controls the order roles appear in admin management and the order generated slots should appear.

Recommended admin interaction:

- Mobile: drag handle on each role row, or up/down buttons if drag reorder is too finicky.
- Tablet: drag-and-drop list with visible drag handles.

Ordering behavior:

- Store order in `team_roles.display_order`.
- Use gaps such as `10`, `20`, `30` to make future insertions easier.
- On reorder save, normalize values back to stable increments.

Generated slot order:

1. `team_roles.display_order`
2. `team_roles.role_name`
3. `role_instance_number`

This means:

```text
Worship Leader
Keyboardist
Backup Singer 1
Backup Singer 2
Backup Singer 3
```

instead of an unpredictable database order.

## Deactivate Role Workflow

Roles should be deactivated instead of deleted.

Why:

- Existing service slots may reference `team_roles.id`.
- Historical schedules should remain understandable.
- Deactivation prevents the role from generating future slots without destroying history.

Workflow:

1. Admin taps deactivate on a role.
2. App shows confirmation.
3. Confirmation explains:
   - Future services will no longer generate this role.
   - Existing service slots will remain unchanged.
   - Existing assignments and pending assignments are preserved.
4. Admin confirms.
5. App updates `is_active = false`.
6. Role moves to inactive section or remains labeled inactive.

Reactivate workflow:

1. Admin shows inactive roles.
2. Admin taps reactivate.
3. App updates `is_active = true`.
4. Future services generate the role again.

Delete should not be part of the first admin UI.

## Validation Rules

### Role Name

- Required.
- Trim leading and trailing whitespace.
- Must not be blank after trimming.
- Must be unique among active roles for the same team, case-insensitive.
- May duplicate role names used by other teams.
- Recommended max length: `80` characters.

### Quantity

- Required.
- Integer only.
- Minimum: `1`.
- Recommended UI maximum: `20`.
- Changing quantity should show preview labels before save.

### Display Order

- Required internally.
- Can be managed by drag-and-drop rather than manual typing.
- Must be numeric if exposed as a field.

### Active State

- New roles default to active.
- Deactivating requires confirmation.
- Reactivating should fail if another active role for the same team already has the same name.

### Permissions

- Only admins can create, edit, deactivate, reactivate, or reorder roles.
- Authenticated users may read role configuration if needed for display, but mutation must remain admin-only.
- Server-side RLS must enforce admin-only writes; the UI check is not sufficient by itself.

## Existing Services Behavior When A Role Changes

Default rule: role configuration changes affect future service instances only.

### Rename Role

Existing service slots:

- Keep their current `slot_name` and `role_name`.
- Keep their assignments.
- Keep pending status if pending.
- Keep taken status if taken.

Future service slots:

- Use the new role name.

### Increase Quantity

Existing service slots:

- No automatic changes.

Future service slots:

- Generate the new larger number of slots.

Possible later workflow:

- Add `Apply to future existing services` as an explicit repair action.
- Add `Apply to selected service` from service detail.

### Decrease Quantity

Existing service slots:

- No automatic deletion.
- Assigned and pending slots remain intact.

Future service slots:

- Generate fewer slots.

This avoids destructive behavior, especially when a removed numbered slot already has a person assigned.

### Deactivate Role

Existing service slots:

- Remain visible.
- Remain assignable/unassignable according to existing slot status rules.
- Preserve assignments and pending responses.

Future service slots:

- Do not include the inactive role.

## Mobile Layout

Use a single-column layout optimized for scanning and touch.

### Team Roles Page

Structure:

- App bar: team name.
- Summary strip:
  - Total slots per service.
  - Active roles count.
- Role list.
- Floating action button or app bar action for add role.

Role row:

- Role name as primary text.
- Quantity and preview as secondary text.
- Drag handle or overflow menu.
- Status chip for inactive roles.

Actions:

- Tap row to edit.
- Overflow menu for deactivate/reactivate.
- Reorder mode toggled from app bar if drag handles clutter the normal list.

Add/edit:

- Prefer full-screen dialog or bottom sheet.
- Large touch targets.
- Stepper for quantity.
- Preview below quantity.
- Sticky save action at bottom if content scrolls.

### Mobile Constraints

- Avoid dense tables.
- Avoid horizontal scrolling.
- Keep generated preview to one or two wrapped lines.
- Use clear empty states for teams without roles.

## Tablet Layout

Use a wider, admin-friendly layout with more information visible.

### Team Roles Page

Recommended layout:

- Two-pane layout.
- Left pane: role list.
- Right pane: selected role editor or preview.

Alternative:

- Full-width table/list with inline controls.

Role list columns:

- Drag handle.
- Role name.
- Quantity.
- Generated preview.
- Active state.
- Actions.

Tablet add/edit:

- Use centered dialog or side panel.
- Keep role list visible behind or beside the editor.
- Quantity can use numeric field plus stepper buttons.

### Tablet Constraints

- Preserve readable density without nesting cards inside cards.
- Keep admin actions predictable and aligned.
- Use role preview to prevent confusion about numbered slots.

## Recommended First UI Slice

Keep the first implementation small:

1. Add admin-only `Manage Roles` entry from team list.
2. Build `TeamRolesPage` with read/list/add/edit/deactivate.
3. Support quantity and generated label preview.
4. Support simple display ordering with up/down buttons.
5. Leave drag-and-drop reorder for a later polish pass if needed.
6. Do not add repair/regenerate existing services in the first UI slice.

## Out Of Scope For First UI

- Deleting roles.
- Bulk applying role changes to existing services.
- Backfilling existing services from the UI.
- Double-booking trigger management.
- Slot assignment changes beyond the existing admin assignment workflow.
- Non-admin role suggestions or requests.
