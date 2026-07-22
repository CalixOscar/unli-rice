# UnliRiceSync

CloudKit/SwiftData sync scaffolding for Unli Rice — PROJECT_NOTES.md deferred
item #4. **Nothing in this directory has been built, run, or tested.** It was
written in a Linux container with no Xcode, no macOS SDK, and no Apple
Developer account, so treat every file here as a draft to compile-check and
exercise for the first time on the Mac, not as verified working code.

## What's here

- `Package.swift` — a separate SPM package (macOS 14 floor), not a target
  added to the root `Package.swift`. SwiftData's CloudKit backing needs macOS
  14; the root package was deliberately moved back down to macOS 13 after MLX
  forced it up (see "Removing the on-device model" in PROJECT_NOTES.md), and
  nothing here should re-impose that floor on `UnliRiceCore`, `unlirice-mcp`,
  `unlirice-agent`, or the test suite. Depends on the root package via a local
  path (`.package(path: "..")`) for `UnliRiceCore` only — one-directional, no
  cycle, root manifest untouched.
- `Sources/UnliRiceSync/SyncEvent.swift` — a SwiftData `@Model` mirroring
  `Event` field-for-field.
- `Sources/UnliRiceSync/SyncCoordinator.swift` — an actor that pulls new
  `SyncEvent`s from the CloudKit-backed container into the local
  `events.jsonl` via `EventStore.append`, then pushes local events the
  container doesn't have yet. Both directions dedupe on `Event.id`.
- `UnliRice.entitlements` — the iCloud/CloudKit capability plist. Sits outside
  `Sources/UnliRice/` on purpose, so SwiftPM doesn't see it as a stray
  resource in the GUI target's source tree.
- `Tests/UnliRiceSyncTests/` — merge-logic tests against an in-memory
  `ModelContainer`. They cover idempotence and pull ordering; they do **not**
  cover a real CloudKit round trip between two devices, which no unit test can.

## Why the append-only design matters here

`Event` is immutable once written (PROJECT_NOTES.md decision #1) — no update,
no delete, only new events. That's exactly what makes CloudKit sync tractable:
every device only ever *creates* records, so there's no per-field conflict to
resolve, no last-writer-wins to get wrong. Merging two devices' histories is
just "union the events, sorted by timestamp, deduped by id" — which is all
`SyncCoordinator.sync()` does.

## Steps that need the Mac, in order

1. **Confirm the package builds.**
   ```sh
   cd UnliRiceSync
   swift build
   swift test
   ```
   This alone will surface anything wrong with the SwiftData/CloudKit API
   usage — attribute defaults, the `@Model` macro, `ModelConfiguration`
   initializer signatures. Fix here before touching Xcode.

2. **Get the GUI app into Xcode.** There's no `.xcodeproj` in this repo today
   — `UnliRice` runs via `swift run UnliRice` and gets bundled by
   `Scripts/make-app.sh`, not built through Xcode. Open `Package.swift` at the
   repo root directly in Xcode (File → Open on the root `Package.swift` —
   Xcode treats a `Package.swift` as an openable project) and select the
   `UnliRice` scheme.

3. **Add `UnliRiceSync` as a package dependency of the `UnliRice` target**
   (File → Add Package Dependencies → Add Local... → point at this
   directory), alongside the root package it already implicitly has.

4. **Add the iCloud capability.** Select the `UnliRice` target → Signing &
   Capabilities → `+ Capability` → iCloud → check CloudKit. This needs an
   Apple Developer Program account (paid enrollment) and a signing team
   selected — this is the specific step that could not be done headlessly.
   Xcode will generate/merge an entitlements file; reconcile it with
   `UnliRice.entitlements` in this directory (container identifier, CloudKit
   service) rather than starting from a blank one.

   **Caveat worth checking early:** SwiftPM executable targets opened via a
   bare `Package.swift` in Xcode have historically had a rockier relationship
   with Signing & Capabilities than a real `.app` target does. If the iCloud
   capability doesn't stick (no entitlements file gets attached to the
   scheme's build settings, or `CODE_SIGN_ENTITLEMENTS` doesn't take), the
   fallback is wrapping `UnliRice` in a proper Xcode `.app` target — a
   thicker version of what `Scripts/make-app.sh` already does by hand — and
   adding the capability there instead. Confirm which path works before
   building anything further on top.

5. **Wire `SyncCoordinator` into app startup.** In `Sources/UnliRice/AppStore.swift`
   (where `EventStore`/`NoteService` are already constructed — see
   `AppStore.switchDataFolder(to:)` for the existing pattern of owning and
   reopening the store), construct a `SyncCoordinator` via
   `SyncCoordinator.makeCloudKitBacked(store:)` using the *same* `EventStore`
   instance the app already reads/writes, and call `sync()` on launch and
   after `RoutineDriver` ticks. Remember `resetCorpusScopedState()` — switching
   data folders should probably also rebuild the coordinator, or a synced
   note from vault A could get pushed into vault B's container.

6. **Verify with two devices**, not two runs on one Mac: build and run on the
   Macbook and on a second Mac (or the iOS/iPadOS target, if this ever grows
   one) signed into the *same* iCloud account, create a note on one, and
   confirm it appears on the other without either device's `unlirice-mcp`
   process being open at the same time — that's the actual claim being made
   ("notes on the Macbook show up on more devices"), and nothing short of that
   confirms it.

## Known gaps, called out rather than hidden

- No retry/backoff on `sync()` failure — a real CloudKit call can fail for
  account, quota, or network reasons that a single `try await` will just
  propagate. Decide where that surfaces (a `Notice`, matching this project's
  existing `NoticeStore` pattern for "a routine failed and shouldn't be
  swallowed") before shipping this unattended.
- `unlirice-mcp` (the CLI MCP server other agents connect through) does not
  link this package at all yet. As scaffolded, sync only runs while the GUI
  app is open — the same "MCP points the wrong way for scheduling" limitation
  PROJECT_NOTES.md already recorded for the removed on-device model applies
  here too: this app is a server, it can't be woken by CloudKit on its own
  without something like a `NSPersistentCloudKitContainer` remote-change
  observer running in a process that's actually alive to receive it.
- No conflict test against two *concurrent* writers editing the same note from
  two offline devices, then both coming online. The append-only design should
  make this a non-issue (both sets of events just get unioned in), but that's
  a claim worth a real test with two `EventStore`s and one shared container
  before trusting it.
