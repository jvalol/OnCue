---
title: Open at login
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 124f354 (spec), 446386c (implementation)
---

## Problem
After a restart or a log out, OnCue isn't running until someone opens it, so it isn't watching.
For a security camera that's the easiest gap to fall into, and Settings has no way to close it.
(There was never an open-at-login option; the history has no trace of one.)

## Non-goals
- Arming automatically at login: possibly a later spec, with privacy concerns to weigh first.
- Supporting macOS before 13; OnCue requires 14.

## Behaviour (acceptance criteria)
- [x] Settings has an "open at login" checkbox, off by default. Turning it on adds OnCue to the
      login items; turning it off removes it. Manual check: on, log out and in, OnCue is running.
- [x] The checkbox shows what macOS actually has, so a change made in System Settings > General >
      Login Items shows up the next time Settings opens. Unit test on reading the status; manual check.
- [x] If macOS needs the user's approval before OnCue can open at login, Settings says so and offers
      to open Login Items settings. Unit test on the status mapping; manual check.
- [x] A failure to register or unregister is shown, and the checkbox goes back to the real state.
      Unit test with a fake service.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `SMAppService.mainApp` (ServiceManagement): `register()`, `unregister()`, and `status`
  (`.enabled`, `.notRegistered`, `.requiresApproval`, `.notFound`). The status is the source of
  truth; OnCue saves nothing of its own, so it can't disagree with System Settings.
- A small `LoginItem` wrapper around a protocol that `SMAppService` conforms to, so toggling,
  failure, and the status mapping are unit-tested with a fake.
- The checkbox sits with the other checkbox in Settings. Its label, the approval note, and the error
  message are copy: drafts carry `[COPY - Jake]`.
- `SMAppService.openSystemSettingsLoginItems()` opens Login Items for the approval case.
- **Built (2026-09-19):** `LoginItem` wraps a `LoginItemService` protocol that `SMAppService`
  conforms to; `state(for:)` maps macOS's status, `set(_:)` returns the resulting state and any error.
  The checkbox sits under "Open Preview Window at Launch" and reads the status each time Settings
  opens. Turning it on into a state that needs approval offers to open Login Items. A failure shows its error, and the checkbox shows the real state.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] `LoginItem` over a service protocol, with tests
- [x] Settings checkbox, status on open, approval note, error handling
- [x] Manual checks, Verification filled in

## Verification
- `LoginItemTests` (5): macOS's statuses mapped; switched off in System Settings shows unchecked;
  turning on and off; approval needed reported; a failure returns its error and the real state.
  90 tests pass on a clean build with no warnings; `scripts/check` passed in full once Jake had the
  six copy markers struck, keeping the drafted text.
- Jake's manual checks (2026-09-19): all pass. OnCue opened at login after logging out and in; after
  the fix, switching it off in System Settings shows the box unchecked. A development build registers
  the copy of OnCue it runs from, so the login check opened the Xcode build.
- An "untitled" Local Network prompt appeared at that login. OnCue isn't in the Local Network list
  and has no network entitlement or code, so it most likely came from another app starting at login;
  unconfirmed.

## Open questions
Resolved by Jake, 2026-09-19: arming at login is out of this spec; it may be a later one, and has
privacy concerns to weigh first.
