# New App Checklist

Use this before we build any new app in the Padeswood suite.

## App Brief

- App name:
- App folder:
- Short purpose:
- Main user groups:
- Does it need manager or admin views:
- Does it need approvals:
- Does it need audit trail:

## Access Rules

- Which `pw_profiles` access field controls it:
- Should Platform block launch when access is off:
- Should denied users keep their Platform session:
- Exact denied message:
- Who can view:
- Who can approve:
- Who can edit other users:
- Should managers see only assigned staff:

## Login And Splash

- Uses standard suite login screen:
- Uses standard `No Access` screen:
- Uses standard licence overlay:
- Uses shared suite runtime from `shared-suite.js`:
- Back button returns to Platform:
- Logout returns to Platform:
- Top-right name must use full name, never shorthand:

## Suite Defaults

These should be true unless we explicitly choose otherwise.

- Do not sign the user out just because app access is denied.
- Access denied should say `No Access`.
- Access denied should show a single `Back to Platform` action.
- Platform should redirect denied users with `?access=denied`.
- Licence footer should only say `Licence active`.
- Theme should persist across the suite.
- Palette should persist across the suite and database.
- Supabase client, access checks, and licence checks should use the shared suite helper.
- Visible names should prefer full name, then email, never short kiln usernames.
- Date, select, and number fields must clamp correctly on mobile.

## Data And Policy Questions

- Main tables:
- Audit tables:
- Profile table:
- Does it need manager assignment:
- Does it need retrospective entries:
- Does it need entitlement or allowance editing:
- What should count as approved only:
- What should count as pending reserved:
- What should be blocked by database policy:
- Which actions must be admin only:

## Mobile Checks

- Login screen matches the suite:
- Access denied screen matches the suite:
- Date inputs do not overflow right edge:
- Sticky headers use measured height, not magic offsets:
- Primary actions stay reachable without scrolling traps:
- Any grouping or filter controls are centered and readable:

## Finish Line

Do not call the app complete until these are checked.

- Platform launcher added.
- User management access toggle added.
- Access-denied route works from Platform.
- Direct app visit also resolves to denied instead of a stray login prompt.
- Session persists when returning to Platform.
- Full-name display works in top bar and activity.
- Licence status wording matches the suite.
- Mobile pass completed on the real screens that matter.
- Syntax check completed.
- Smoke check added or updated in `tests/smoke-check.mjs`.

## The Questions I Should Ask You First

When we add the next app, I should pause and get these answers up front:

1. What is the app called and who uses it?
2. Which access flag controls it?
3. Who can approve, edit, or see other users?
4. Should denied users stay signed in and go back to Platform?
5. Does it need manager assignment or routing?
6. Does it need audit trail, retrospective edits, or admin-only actions?
7. What must the mobile version prioritise?
