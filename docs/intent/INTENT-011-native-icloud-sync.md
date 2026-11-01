# INTENT-011 — Connect the Mac and Capture automatically

**Date:** 2026-11-01
**Author:** codex, from the founder's request
**Status:** approved 2026-11-01 — “Lets build it”, following the described native iCloud flow
**Intent read:** passed 2026-11-01 — Astra architecture audit; findings incorporated in plan
**Spec:** docs/SPEC-native-icloud-sync.md
**Plan:** docs/PLAN-native-icloud-sync.md

## The founder's words

“That is a lot of steps. Can we automate it?” Then: “So why isnt that active for
unli rice and unli rice capture?” After the explanation of the missing shared
iCloud capability: “Lets build it”.

## What solved looks like

Enable iCloud Sync once in each app, using the same Apple Account. The apps
find their shared space without folder selection. The Mac reuses already-granted
project folders and publishes project information automatically while running;
Capture imports it when opened and during foreground use. Codex/Claude's connector
can exchange captures even when the Mac window is closed.

Existing captures and notes stay local and are preserved. Existing private choices
stay private; existing shared-folder setups keep working until explicitly changed.
Enabling native sync explains that existing note text, captures, to-dos and project
summaries will sync. Audio and project source files stay local. The build request
does not activate cloud upload against the founder's real notes.

## Feel and constraints

One plain Enable iCloud Sync action; settings say waiting, unavailable or published
truthfully. Project-folder permission is requested only if not already granted.
Apple controls transfer timing; no promise of instantaneous background iOS sync.
Local work keeps working offline. Changing Apple Account pauses sync rather than
mixing accounts. A cloud-bound corpus uses reversible archive, including after sync
is turned off; it does not physically purge source history.

This extends INTENT-010: its no-new-entitlement boundary is superseded only for
native iCloud support and the provisioned connector wrapper. No CloudKit schema,
custom server, cloud model, audio upload, third-party dependency, release number,
TestFlight upload or App Store submission. Private and advanced folder modes remain.
This is tier 2; the previous feature's pre-mortem waiver is not reused.


## Founder scope amendment

The founder subsequently set the goal “keep going until icloud applekit is
implmented and uploaded to app store”. This authorizes the release upload after
verification, superseding only the no-upload boundary above. Production sync
still requires runtime consent; App Store Connect numbering is checked live.
