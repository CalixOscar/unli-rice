# SPEC — Native iCloud sync

**Intent:** docs/intent/INTENT-011-native-icloud-sync.md
**Status:** approved 2026-11-01 with the requested native sync behavior

| ID | Requirement | Check |
|---|---|---|
| C1 | Mac, Capture and wrapped MCP use the same app-managed iCloud Documents container. Existing connector launch path remains valid. | Entitlements, generated bundle/symlink inspection, signed capability check. |
| C2 | Per-corpus modes private/iCloud/folder; existing explicit private and folder choices preserved. Native sync requires explicit runtime opt-in with accurate data scope. | Pure preference migration tests and both settings walkthroughs. |
| C3 | Canonical event log stays local. Immutable coordinated cloud batches preserve raw event bytes and unknown kinds; UUIDs deduplicate crash retries and finite relay. No source rewrite. | Fixture roundtrip, crash/retry, unknown-kind, same-phone-label tests. |
| C4 | Separate strict cloud state, preserving all legacy cursor files; corrupt/future state and source shrink pause instead of resetting. Batch/state work serialized across GUI and MCP. | Concurrency, corruption, cursor and shrink tests. |
| C5 | Corpus binds to a canonical CloudKit container/environment/user-record identity plus a separate ubiquity token for each executable. Known-client token changes pause; an unknown client enrolls only after matching the canonical identity. Version-1 migration requires its original token and preserves binding UUID. Never silently rebind or reuse cloud caches for another account. | Injected A/logout/B/A tests; real signed account behavior before release. |
| C6 | Placeholder discovery requests downloads; only complete downloaded files are read. Downloading/missing/unavailable/malformed/handed-to-iCloud are distinct from Mac receipt. Cloud coordination runs off the main thread. | Injected discovery/IO tests and signed device checks. |
| C7 | Mac reuses granted project roots, publishes at enable/activation and throttled while running, independent of Studio navigation. Per-producer overviews retain source age; no false fresh empty report on failed scans. | Lifecycle/code checks, snapshot resolver tests. |
| C8 | Capture automatically loads native overview and captures while foregrounded. Manual folder pairing becomes Advanced; private choice remains prominent. | Simulator settings/offline walkthrough. |
| C9 | MCP independently syncs through a signed/provisioned app-like wrapper; environment-overridden test corpora never resolve real iCloud. Account failures become context warnings. | Wrapper inspection, protocol smoke and signed helper test. |
| C10 | Permanently cloud-bound corpora refuse physical note purge even after turning sync off. Reversible archive remains available. Audio retention remains local. | Guard tests/code review and UI copy. |
| C11 | Native causal ancestry preserves sequential edits inside one timestamp across reversed downloads. Legacy bytes remain unchanged; appended declarations preserve observed order. Missing ancestors remain pending; actual cycles fail visibly. Unbound history retains its existing fold. | Causal migration, reverse arrival, second-writer/cache, cycle/pending and Python agreement tests. |
| C12 | Private/legacy behavior remains compatible; no automatic moving/deleting old folders or old cloud files. Release upload is authorized by the later founder goal; production sync still needs runtime consent. | Existing suite, version/entitlement diff, migration fixtures; live ASC numbering and release verification. |

Built, unsigned-build verified, signed-capability verified and two-device delivery
verified are separate claims. The final acceptance record identifies each honestly.
