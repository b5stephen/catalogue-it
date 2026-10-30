---
paths:
  - "catalogue-it/Utilities/CloudKitSyncMonitor.swift"
  - "catalogue-it/Utilities/SyncStatusBar*.swift"
  - "catalogue-it/Utilities/SyncDiagnostics*.swift"
---

## Sync status UI

`CloudKitSyncMonitor` reads `NSPersistentCloudKitContainer.eventChangedNotification` (again with
`object: nil`, since SwiftData doesn't expose the container). Events carry only a type, start/end
dates, a success flag and an error — **no record counts and no percentage**, so progress is
necessarily indeterminate; the count in `SyncStatusBar` is how many items have landed in our own
store since the run began (a delta against a baseline taken at the first event — never the total,
since every launch runs an incremental import that usually fetches nothing). Behaviours worth
preserving:

- Signed out of iCloud, CloudKit posts an import event that *starts and never finishes*. The
  monitor gates on `CKContainer.default().accountStatus()` so the indicator doesn't sit on
  "Syncing…" forever for anyone not using iCloud.
- Both directions are shown: `.import`/`.setup` as "Syncing from iCloud", plus "· N new items"
  once any have arrived; `.export` as "Syncing to iCloud" with no count (the local total says
  nothing about what is still queued).
- Nothing shows until a run has been in flight for a while: 1s on an empty store (a new device
  pulling everything down, where the bar is the only sign of life), 3s once catalogues exist.
  Routine launch and foreground checks finish well inside that, so they don't flash the bar.
- The bar lives on the catalogue list only. An inset on the `NavigationSplitView` doesn't reach
  columns pushed onto their own stack in compact width, and on the item screen iOS 26 renders
  `.searchable` as a bottom bar occupying the same edge.
- Not-signed-in, network and throttling errors are deliberately **not** surfaced — they are either
  the user's choice or self-resolving. Only actionable failures (quota, schema) reach the UI.

## Reporting sync failures from the field

`CKError.partialFailure` (code 2) is a container, not a cause — the per-record errors are in
`userInfo[CKPartialErrorsByItemIDKey]`. `SyncDiagnostics` unwraps them, buckets them by
(code, record type), scrapes the `CD_…` field names out of the server messages, and keeps a
rolling record that survives a relaunch. `SyncDiagnosticsView` renders it for screenshotting,
because a screenshot is the only payload TestFlight feedback carries — there is no API to
attach anything else. Two rules for anything added there:

- Log at `.notice` or above with `privacy: .public`. `.debug` entries are memory-only and can
  never be recovered from a tester's device, and interpolations are redacted by default.
- Record every failure, including ones deliberately kept out of the UI. Staying quiet about a
  self-resolving error is a separate decision from discarding the evidence.
