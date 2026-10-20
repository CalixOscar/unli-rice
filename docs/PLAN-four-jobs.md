# PLAN — Four jobs: a sidebar for context, guardrails, security and projects

**Intent:** `docs/intent/INTENT-006-four-jobs.md`
**Planner:** claude. **Reviewer:** codex.
**Stage:** 5 building (founder approved 2026-10-20)
**Pre-mortem:** `docs/dialogue/four-jobs.md` (codex, 2026-10-19), answered there 2026-10-20
**Branch:** `claude/four-jobs`, cut from `codex/project-garden` at `06ef490` (Garden isn't on
`main` yet, and this plan rebuilds the navigation Garden plugs into). The hygiene hook
warns about branch drift. That's expected until Garden merges.
**Verified against:** `11e0389` on `claude/four-jobs`

## 0. What was asked for

> "the features on unli rice are too many now. We need to simplify the app to focus on
> context, guardrails, security and keeping track of things like gits"

Founder decisions, 2026-10-19: the keep/cut list in INTENT-006 is approved as drafted.
Hide, don't delete. Mac app only. "What runs on its own" becomes one visible switch in
Setup.

## 1. What already exists (checked, not assumed)

- **Sidebar:** 9 rows, `ContentView.swift:123-195`: Home, Garden, Notes, To do, Repos,
  Needs you (only when the badge > 0), Your year so far, Map, More. Plus `CapturePromoCard()`
  at `:198`, the only door to the Capture sheet (`CapturePromoView.swift:38,75-76`).
- **Routing:** 18 `@Published var showing…` flags in `AppStore.swift`. They're written by
  the `show…()` methods, `closeAllPanes()` (`:1096-1119`), `selectNote` (`:1370-1390`),
  `resetCorpusScopedState()` (`:893-897`) and the launch choice (`:630-634`: First Run or
  Home; with every flag false the note list shows). They're read through an if-chain in
  `ContentView.mainColumn` (`:226-253`) and in the note list (`:317,332,345,370,722,827`).
  No `$store.showing…` bindings exist (Codex, pre-mortem 5). A missed flag has already
  caused a shadowing bug (`AppStore.swift:1113-1117`).
- **Archive:** `showArchived()` sets `showingMore`, so today `.archived` renders
  `MoreView.archivedNotesSection` (restore one, restore selected). The note-list archive
  mode (selection toolbar, "Move to Trash") is unreachable today and stays so.
- **More** (`MoreView.swift`): a chip bar (`:38-62`) over 9 destinations (`:6-14`), plus the
  **"Rate Unli Rice" row** (`:116-143`) the studio guardrails require. `moreDestination`
  isn't persisted (`AppStore.swift:64`).
- **Setup** (`SetupView.swift:8-16`): local `@State selectedTab` starting at AI Tools; 5 tabs,
  4 repeating More's chips. The storage-folder picker is in AI Tools (`ConnectView.swift:88-90,144-180`).
- **Automation** (`AutomationView.swift:40-52`): Advanced Mode off shows only
  `SimpleScanRootsCard`; on shows Autonomy, Schedule, Janitor and Ingest cards. Both
  schedule switches (`ScheduleCard`, `:142-170`; row helper and statuses private at
  `:174,199`) show **only with Advanced Mode on**, so routines can run with no visible switch.
- **What runs regardless of `routinesEnabled`:** on every tick (GUI `AppStore+Ingest.swift:237`
  or agent `unlirice-agent/main.swift:272`), `RoutineDriver.swift:162-182` imports the
  "Notes for Unli Rice" inbox and refreshes the mirror; notices are announced (`:233`).
  **Gated by it** (`:185-209`): Claude session import and the scheduled routines, which
  import documents from `scanRoots` (`:28-32,309-318`) and run the janitor. Imports create,
  revise and tag notes (`IngestRunner.swift:144-177`); the janitor tags and queues
  proposals (`JanitorRunner.swift:87-117`).
- **"Keep working with the window closed"** is a real login item (`BackgroundAgent.isInstalled()`,
  `UnliRiceHost/BackgroundAgent.swift:38-41`), independent of `routinesEnabled`.
- **One folder list, four readers:** `store.scanRoots` (`AppStore.swift:378`) feeds document
  import, Repos (`RepoPaneView.swift:275`), Garden (`ProjectGardenView.swift:245`) and To do
  (`TodoPaneView.swift:193`). `SimpleScanRootsCard` promises "automatically imported"
  (`AutomationView.swift:515-516`), which is false with routines off.
- **Year-so-far notices:** posted when `settings.monthlyReviewEnabled` (`RoutineDriver.swift:264`).
  The GUI hard-codes `true` (`AppStore.swift:912`). `open()` routes `.retrospective` to
  `showRetrospective` (`AppStore+Notices.swift:52-53`). Notice rows in Needs you only offer
  Dismiss (`NeedsYouView.swift:128-153`); the notice list opens destinations.
- **Links into moving places:** Home → Profile Builder (`HomeView.swift:158`) and → House
  rules (`:334`). Profile Builder's finish → `showGetStarted()` (`ProfileBuilderView.swift:632`),
  cancel → `showHome()` (`:52`). Garden → Repos (`ProjectGardenView.swift:95`) and → folders
  (`:96,223`). Copy naming "More": `FirstRunView.swift:57`, `RepoPaneView.swift:134`,
  `CapturePromoView.swift:207`, `ProjectGardenView.swift:200`, `README.md:26`.
- **Profiles:** `ProfileRegistry.profiles` (`Profile.swift:33`), saved to `profiles.json` in
  `DataLocation.supportDirectory()` (`:44`).
- **Isolation hooks for testing:** `UNLIRICE_DATA_PATH` (event log) and
  `UNLIRICE_AGENT_SETTINGS` (`AgentSettings.swift:171-174`). Neither covers `UserDefaults`
  or `profiles.json`. The GUI saves agent settings on every launch (`AppStore.swift:650,988-990`).
- **Tests:** one target, `UnliRiceCoreTests`. No app-target or UI tests. Baseline on this
  branch: 406 executed, 2 skipped, 0 failures (verified: `swift test`, Claude, 2026-10-19).

## 2. Decisions

| Decision | Chosen | Credible alternative, and why it lost |
|---|---|---|
| Routing state | One `Pane` enum replaces the 18 flags; the flags become get-only computed readers | Keep the flags: every new row adds another negation, and that bug class already shipped once. |
| Hidden features | Enum cases and views stay compiled; no sidebar row points at them | Delete: the founder chose hide. Bringing one back means adding one `sidebarRow` line. |
| Sidebar shape | Four small headings (CONTEXT, GUARDRAILS, SECURITY, PROJECTS), rows under them, Setup at the bottom | Page names only: the headings are what tell a first-time user what the app is for. |
| More hub | Removed. `MoreView` becomes a host that renders one destination | A slimmer More: that's the junk drawer this plan exists to empty. |
| Archive | Keep today's renderer (`MoreView` restore list) | The note-list archive mode: it would re-open "Move to Trash", a door that isn't reachable today. |
| Projects | One row; a segmented control switches `pane` between `.projects` (Garden) and `.repos` (Repos); each child is created on entry | Keep both alive: needs extra refresh reasoning for Repos' uncancelled scan. Filters reset on switch, as they do today. |
| Needs you + Notifications | One always-visible row (badge when > 0), active for `.needsYou` and `.notices`; the page has "All messages" | Inline notice history: Needs you is for what's waiting. |
| The one switch | `routinesEnabled`, always visible. If the agent is installed, a visible line says so; Details opens by itself when the agent is on and routines are off | Two switches: the founder chose one. Agent hidden in Details: contradicts "nothing runs invisibly". |
| Folders | Own Setup tab, "Folders"; Garden's "Manage folders" opens it | Inside Automation: Projects reads these folders, so burying them hides that. |
| Setup tabs | Stored in `AppStore.setupTab`; every entry sets it explicitly; plain `showSetup()` resets to AI Tools | Remember the last tab: a notes-folder notice could land on the wrong tab (pre-mortem 4). |
| Year so far | GUI writes `monthlyReviewEnabled: false`; old `.retrospective` notices are marked read and open nothing | Leave on: they'd link to a page with no door. |
| Separate memories | Setup tab only when `profiles.count > 1`; a stale `.profiles` tab falls back to AI Tools | Hide always: strands anyone who already has two memories. |
| Rate row | Foot of Setup only | Every page: the guardrail asks for quiet. |
| Exports | File menu keeps Markdown and OKF Bundle; Zip and PDF filtered | Remove the menu: export is how a user leaves with their data. |

## 3. Point of view and patterns

- **Feel:** a quiet control room with four labelled doors. You check what you came for and
  close the app.
- **Not this:** a sidebar that lists every capability, or a More drawer you scroll sideways.
- **Reused:** `sidebarRow` (`ContentView.swift:205`), every existing pane view, `MoreView`'s
  content switch, `AutomationView`'s `Card`, `Theme` tokens, and the small monospaced label
  style of "WHAT YOUR AI KNOWS ABOUT YOU" (`HomeView.swift:89`) for headings.
- **New:** `Pane` enum; `sidebarHeading`, `ProjectsPane` (in `ContentView.swift`);
  `AutomationToggleRow`, `BackgroundWorkCard`, `BackgroundAgentRow` (in
  `AutomationView.swift`). No new files, so `xcodegen generate` isn't needed.

## 4. Journey and states

**Journey:** 1. Open the app. The sidebar reads CONTEXT / GUARDRAILS / SECURITY / PROJECTS.
2. Check Home for what your AI knows. 3. Glance at Needs you if it has a badge. 4. Open
Projects to see where each repo stands. 5. Close the app.

| State | What the user sees, and what they can do |
|---|---|
| First run, nothing yet | Full-window `FirstRunView` as today; its copy points at Setup. After it: Home. |
| Success | Every kept destination is one click from the sidebar, active row highlighted. |
| Empty or partial input | Projects with no folders: Garden's empty state, whose button opens Setup › Folders. Needs you with nothing waiting: "Nothing is waiting on you" plus "All messages". Archive empty: "No archived notes." |
| Slow (loading, latency) | Garden and Repos keep their own progress text; switching segments mid-scan starts the other view's own scan. |
| Offline or failed, and how they recover | A notes-folder notice opens Setup › AI Tools (the picker). The corpus banner's reconnect/default buttons work as today. An old year-so-far notice is marked read. |
| Permission denied | Unchanged per pane (Repos' denied-ancestry status; unreadable folders). |
| Interrupted and resumed | Launch shows First Run or Home, as today. `pane` and `setupTab` aren't persisted. |
| Return visit | Routines on → the switch is in Setup › What runs on its own, whatever Advanced Mode says. Agent installed → the line under the switch says so. 2+ memories → Separate memories tab present. |

## 5. Tasks

### B0. Baseline
- [x] `planner` Build and test before any change — 406 executed, 2 skipped, 0 failures
      (verified: `swift build && swift test --scratch-path /tmp/unlirice-spm-build`, Claude, 2026-10-19)

### B1. One `Pane` value instead of 18 flags (`build`)
- [ ] `build` In `AppStore.swift` add
      `enum Pane: Equatable { case home, notes, aiFolder, houseRules, todo, needsYou, notices, trustCenter, archived, projects, repos, setup, firstRun, profileBuilder, map, retrospective, whyNotTextFile }`,
      `@Published var pane: Pane = .notes` and `@Published var setupTab: SetupView.Tab = .connect`.
      Replace the 18 stored `showing…` properties with get-only computed readers:
      `showingHome` = `.home`, `showingGarden` = `.projects`, `showingRepos` = `.repos`,
      `showingTodo` = `.todo`, `showingGraph` = `.map`, `showingRetrospective` = `.retrospective`,
      `showingNeedsYou` and `showingReviewQueue` = `.needsYou`, `showingNotices` = `.notices`,
      `showingTrustCenter` = `.trustCenter`, `showingArchived` = `.archived`,
      `showingFirstRun` = `.firstRun`, `showingProfileBuilder` = `.profileBuilder`,
      `showingMore` = `.setup || .aiFolder || .houseRules || .trustCenter || .archived || .notices || .whyNotTextFile`,
      `showingSetup` and `showingGetStarted` = `.setup`,
      `showingProfileManager` = `.setup && setupTab == .profiles`,
      `showingAutomation` = `.setup && setupTab == .automation`.
      — files: `AppStore.swift` — done when: none of those 18 names is assigned anywhere —
      verify: `grep -rnE "\b(store\.)?showing(Home|Garden|NeedsYou|Setup|ProfileBuilder|ProfileManager|FirstRun|More|Archived|ReviewQueue|Graph|GetStarted|Retrospective|Repos|Todo|Notices|TrustCenter|Automation) = " Sources/UnliRice` prints nothing
- [ ] `build` Every writer sets `pane` (and `moreDestination` / `setupTab`) directly. Delete
      `closeAllPanes()`. Exact transitions:
      `showHome` → `.home`; `showGarden` → `.projects`; `showRepos` → `.repos`;
      `showTodo` → `.todo`; `showNeedsYou`, `showReviewQueue` → `.needsYou`;
      `showNotices` → `.notices` + `moreDestination = .notifications`;
      `showTrustCenter` → `.trustCenter` + `.trustCenter`; `showArchived` → `.archived` + `.archived`;
      `showHouseRules` → `.houseRules` + `.houseRules`; `showGraph` → `.map`;
      `showRetrospective` (both overloads) → `.retrospective`; `showFirstRun` → `.firstRun`;
      `showProfileBuilder` → `.profileBuilder`;
      `showMore`, `showSetup`, `showNotesFolder`, `showGetStarted` → `.setup` + `moreDestination = .setup` + `setupTab = .connect`;
      `showProfileManager` → `.setup` + `.setup` + `setupTab = .profiles`;
      `showAutomation` → `.setup` + `.setup` + `setupTab = .automation`;
      `showGardenFolders` → `.setup` + `.setup` + `setupTab = .folders` (B3 adds the case);
      `showLatest`, `showLast`, `showAllNotes` → `.notes`;
      `selectNote(id)` with non-nil id → `.notes` (the archived special case goes, per §1);
      `resetCorpusScopedState()` → if `pane` is `.retrospective`, `.projects`, `.repos`,
      `.notices` or `.trustCenter`, set `.notes`; otherwise leave it;
      launch (`:630-634`) → `.firstRun` or `.home`. Keep every `statusMessage` as is except
      those B5 rewrites. — files: `AppStore.swift`, `AppStore+Notices.swift`,
      `AppStore+Retrospective.swift` — verify: `grep -rn closeAllPanes Sources` prints nothing; build green
- [ ] `build` `ContentView.mainColumn` becomes a `switch store.pane`, keeping First Run's
      full-window branch at `:52-64` as is: `.home` → `HomeView`; `.notes` → `NoteDetailView`
      if a note is selected, else `noteListColumn`; `.projects`, `.repos` → `ProjectsPane`
      (B5); `.todo` → `TodoPaneView`; `.needsYou` → `NeedsYouView`; `.map` → `MapPaneView`;
      `.retrospective` → `RetrospectiveView`; `.profileBuilder` → `ProfileBuilderView`;
      `.firstRun` → `FirstRunView`; every other case → `MoreView`. — files: `ContentView.swift`
      — verify: build green

### B2. The sidebar (`build`)
- [ ] `build` Replace `ContentView.swift:123-195` with:
      CONTEXT: Home (`.home`), Notes (`.notes`), "The folder your AI can read" (`.aiFolder`).
      GUARDRAILS: "What your AI should always do" (`.houseRules`), To do (`.todo`),
      Needs you (always shown; active for `.needsYou` or `.notices`; `badge:` when > 0).
      SECURITY: Trust Center (`.trustCenter`), "Archived notes" (`.archived`).
      PROJECTS: Projects (active for `.projects` or `.repos`).
      Then `Spacer()`, then Setup (active for `.setup`). Remove `CapturePromoCard()`.
      Every row's action calls `store.selectNote(nil)` then its `show…()`, as today.
      Headings: a private `sidebarHeading(_ text: String)`, `.system(size: 10, weight: .bold,
      design: .monospaced)`, `Theme.textSecondary`, `.padding(.horizontal, 16)`,
      `.padding(.top, 14)`, `.padding(.bottom, 2)`, `.accessibilityAddTraits(.isHeader)`.
      — done when: 10 rows, 4 headings — verify: build green, then B6
- [ ] `build` `sidebarRow` gets `.accessibilityElement(children: .combine)` and, when
      `badge > 0`, `.accessibilityLabel("\(title), \(badge) waiting")`. — files: `ContentView.swift`
- [ ] `build-light` If "What your AI should always do" or "The folder your AI can read"
      truncates at 190pt (B6 screenshot), the rows become "House rules" and "AI folder";
      page titles keep the full phrase. Planner decides from the screenshot.

### B3. More becomes a host; Setup's tabs (`build`)
- [ ] `build` `MoreView.swift`: delete the chip bar (`:38-62` and the divider after it);
      render `store.moreDestination` alone; show `rateFooter` only when it's `.setup`.
      `ContentView` sets nothing extra: B1's writers already set `moreDestination`.
      — files: `MoreView.swift` — verify: B6
- [ ] `build` `SetupView.Tab` becomes `connect = "AI Tools"`, `folders = "Folders"`,
      `automation = "What runs on its own"`, `profiles = "Separate memories"` (drop
      `houseRules`, `mirrorExport`). Replace `@State selectedTab` with `store.setupTab`.
      The tab bar lists `.profiles` only when `store.profileRegistry.profiles.count > 1`; if
      `setupTab == .profiles` and it isn't listed, render and highlight `.connect`.
      `.folders` renders B4's Folders tab; `.automation` renders B4's layout.
      — files: `SetupView.swift` — verify: build green

### B4. What runs on its own: one switch, always visible (`build`)
- [ ] `build` In `AutomationView.swift`:
      (a) move ScheduleCard's private `toggleRow` into a file-level
      `struct AutomationToggleRow: View` (same parameters: `isOn`, `title`, `detail`, `disabled`);
      (b) add `struct BackgroundWorkCard: View`: one `Card` (icon `calendar.badge.clock`,
      title "Work in the background", subtitle = B4b on/off text by `store.routinesEnabled`),
      containing one `AutomationToggleRow(isOn: $store.routinesEnabled, title: "Run routines
      on a schedule", detail: routineStatus)`, with `routineStatus` moved from ScheduleCard
      unchanged. Below the row, when `store.backgroundAgentInstalled`, a 12pt
      `Theme.textSecondary` line: "Also set to keep working when the window is closed.
      Change it in Details.";
      (c) add `struct BackgroundAgentRow: View`: one `Card` (icon `moon`, title "Keep working
      with the window closed", subtitle "Lets scheduled routines run when Unli Rice isn't
      open. Off by default."), containing the second toggle exactly as ScheduleCard has it,
      with `backgroundStatus` moved unchanged;
      (d) make `AutonomyCard`, `JanitorCard`, `IngestCard`, `SimpleScanRootsCard` internal.
      Leave `ScheduleCard`, `AdvancedModeToggleCard` and `AutomationView` in the file, unused
      by Setup. — verify: build green
- [ ] `build` Setup › What runs on its own renders, inside one `ScrollView` (24pt horizontal
      padding, 16pt spacing): `BackgroundWorkCard`, then
      `DisclosureGroup("Details", isExpanded: $detailsOpen)` containing `BackgroundAgentRow`,
      `AutonomyCard`, `JanitorCard`, `IngestCard`. `detailsOpen` is `@State`, initialised to
      `store.backgroundAgentInstalled && !store.routinesEnabled`. — files: `SetupView.swift`
- [x] `planner` B4b copy, checked against `RoutineDriver.swift:160-209`, `IngestRunner.swift:144-177`,
      `JanitorRunner.swift:87-117` (2026-10-20):
      **On:** "Unli Rice reads your Claude Code sessions and the folders in Setup › Folders on
      a schedule, and adds and tags notes from them. Merges and archives are only ever
      suggested for your OK."
      **Off:** "Your Claude Code sessions and folders aren't read on their own. Unli Rice
      still imports what you put in the Notes for Unli Rice folder, keeps the folder your AI
      can read up to date, and posts messages to Needs you."
- [ ] `build` Setup › Folders renders `SimpleScanRootsCard` with its `Card` title changed to
      "Project folders" and subtitle to "Projects reads git details from these folders.
      With background work on, Unli Rice also imports the Markdown and text files in them
      as notes." (replaces `AutomationView.swift:515-516`). — files: `AutomationView.swift`, `SetupView.swift`

### B5. Projects, needs-you, links and copy (`build` / `build-light`)
- [ ] `build` Private `struct ProjectsPane: View` in `ContentView.swift`: a `VStack(spacing: 0)`
      of a segmented `Picker` bound to a `Binding` over `store.pane` (`"Overview"` ↔
      `.projects` via `showGarden()`, `"Branches & worktrees"` ↔ `.repos` via `showRepos()`),
      padded 20pt horizontal / 12pt vertical, then `if store.pane == .projects
      { ProjectGardenView() } else { RepoPaneView() }`. No extra `ScrollView`. Remove Garden's
      header "Repos" button (`ProjectGardenView.swift:95`). — verify: B6
- [ ] `build` `NeedsYouView`: an "All messages" text button (calls `store.showNotices()`),
      always shown, under the header. `AppStore.open(_:)`: `.retrospective` → no navigation
      (the notice is already marked read above it). — files: `NeedsYouView.swift`, `AppStore+Notices.swift`
- [ ] `build-light` `AppStore.swift:912`: `monthlyReviewEnabled: true` → `monthlyReviewEnabled: false`.
- [ ] `build-light` `UnliRiceApp.swift:65`: `ForEach(ExportFormat.allCases.filter { $0 != .zip && $0 != .pdf }, id: \.self)`.
      The rest of the `commands` block and the `Settings` scene stay.
- [ ] `build-light` Exact copy:
      `FirstRunView.swift:57` → "You can connect later from Setup."
      `RepoPaneView.swift:133-134` body → "This pane reads the folders in Setup › Folders. Add one there and it will appear here."
      `CapturePromoView.swift:207` → "No Unli Rice Folder set yet. Set one in Setup › AI Tools, somewhere inside iCloud Drive."
      `ProjectGardenView.swift:200` message → "Add a project folder in Setup › Folders. A note titled “Project: Your project” appears here without a folder, too."
      `HomeView.swift:63` → "Open Projects".
      `statusMessage` in `showMore` → "Setup — AI tools, folders, and what runs on its own."; in `showSetup` → the same.
      — verify: `grep -rn "More →\|More ->" Sources` prints nothing
- [ ] `build-light` `README.md:26`: "**Garden.** A native project overview, available directly
      below Home in the sidebar." → "**Projects.** A native project overview, under Projects
      in the sidebar."; "Manage its folders through **More → What Runs on Its Own**." →
      "Manage its folders in **Setup › Folders**."

### One layer deeper
- [ ] Headings are headers to VoiceOver; rows read "Needs you, 3 waiting" (B2).
- [ ] Keyboard focus moves top to bottom through the sidebar, Setup last.
- [ ] No status message claims something happened that didn't (B5 copy, B4b).

### B6. Verify (`planner`)
- [ ] `planner` Build, test (406 / 2 skipped / 0 expected), Xcode Mac target, and the §6 diff limit.
- [ ] `planner` Isolate before launching anything: `SCRATCH=$(mktemp -d)`; find the debug
      binary's defaults domain (launch once, then `defaults domains | tr ',' '\n' | grep -i unlirice`),
      `defaults export <domain> "$SCRATCH/defaults.plist"`; copy `profiles.json` from the
      debug binary's `DataLocation.supportDirectory()` (print it first; record "absent" if so).
      Launch with `UNLIRICE_DATA_PATH="$SCRATCH/events.jsonl" UNLIRICE_AGENT_SETTINGS="$SCRATCH/agent.json"
      /tmp/unlirice-spm-build/debug/UnliRiceApp`. Never toggle "Keep working with the window
      closed" (it registers a real login item); observe its state as found. Afterwards
      `defaults import <domain> "$SCRATCH/defaults.plist"` and restore `profiles.json`.
- [ ] `planner` Walk: every sidebar row; Projects segments, including a switch while Garden is
      loading; Garden's "Manage folders" → Setup › Folders; Needs you → All messages → a
      `.notesFolder` notice (→ AI Tools), a review notice, an old `.retrospective` notice
      (marked read, no navigation) → back via Needs you; each Setup tab after first visiting
      another; Profile Builder finish and cancel; note A → Home → Notes; two archived scratch
      notes → restore one, restore selected; two scratch profiles → switch → back to one
      (Separate memories tab disappears, AI Tools shown); Advanced Mode on and off (flip
      `unliRice.advancedModeEnabled` in the scratch domain, relaunch); the corpus banner's
      buttons; minimum window width; VoiceOver on the sidebar. Screenshot the sidebar here.

## 6. Acceptance — against reality, not a builder's report

Ticked by whoever verifies the build (Claude or the founder), never by the builder.

**Mechanical**
- [x] `swift build --scratch-path /tmp/unlirice-spm-build` and `swift test --scratch-path /tmp/unlirice-spm-build`
      green: 406 executed, 2 skipped, 0 failures (verified: swift test, Claude, 2026-10-20, after every step)
- [x] The Xcode Mac target builds (verified: BUILD SUCCEEDED, Claude, 2026-10-20) (`xcodebuild -scheme UnliRice -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`)
- [x] `git diff --name-only f0c0b47..HEAD` within: `Sources/UnliRice/{AppStore,AppStore+Notices,AppStore+Retrospective,ContentView,MoreView,SetupView,AutomationView,NeedsYouView,ProjectGardenView,RepoPaneView,FirstRunView,CapturePromoView,HomeView,UnliRiceApp}.swift`,
      `README.md`, `docs/PLAN-four-jobs.md`, `memory.md`, `PROJECT_NOTES.md`
- [x] Nothing under `Sources/UnliRiceCore`, `Sources/UnliRiceCapture`, `Sources/unlirice-mcp` or `Tests/` changed
- [x] B6's backups restored: the `UnliRiceApp` defaults domain matches its pre-test export
      (same SHA-1). `profiles.json` was never written: macOS refused the debug build's save
      to the App Store app's group container (Operation not permitted).

**Editorial — in a running build, not a mock or a preview**
- [ ] With the styling ignored, the sidebar alone says what the app is for.
- [ ] Walked B6's list. Every item seen, or marked "(unverified)" with why.
- [ ] No reachable page leads only to a page without a door, except the accepted §7 items.
- [ ] One-layer-deeper items checked by hand.

**Record**
- Built: …
- Verified: … Unverified: …
- Ready to release: no. New screenshots are needed, and the 6-Month Post-Mortem applies.

## 7. Known limits, accepted

- One folder list still serves Projects and document import. Splitting it changes stored
  settings (tier 2 on its own). The Folders card says so.
- `monthlyReviewEnabled` changes value (`true` → `false`) in the agent-settings file the GUI
  writes on launch. That's a value change, not a schema change, and leaves existing notices
  and digest stamps alone. The intent's "settings untouched" didn't foresee it; recorded here
  instead of editing the intent.
- `advancedModeEnabled` stays stored and still feeds `currentStage` (`AppStore.swift:265-267`),
  but nothing in this layout reads or sets it.
- The Capture promo sheet has no door once the card goes (founder's cut). Its copy is still
  corrected for when it returns.
- The note-list archive mode and its "Move to Trash" stay unreachable, as they are today.
- Hidden views still compile and ship. No automated navigation tests: B6 is a manual walk.
- The sidebar-lag hypothesis in memory.md isn't claimed fixed by B1.

## 8. Rides along or deferred

- Per-project branch graph inside each Garden card.
- Deleting the hidden views, once the founder decides nobody misses them.
- App Store screenshots for the new sidebar, before the next submission.

## 9. Pre-mortem responses

All 13 of Codex's findings accepted; full answers in `docs/dialogue/four-jobs.md`.
- 1 (blocker) archive: today's restore list kept; no new door to "Move to Trash".
- 2–3 (blockers) copy: B4b rewritten against the code; the Folders card's "automatically
  imported" promise replaced.
- 4–6: every Setup entry sets its tab; B1 lists every writer; stale profiles tab falls back.
- 7: one switch plus a visible agent line; Details opens itself when only the agent is on.
- 8–10: card extraction, Projects lifetime and the notices journey specified.
- 11: B6 isolates defaults, agent settings, event log and `profiles.json`.
- 12–13: nits taken; baseline re-run matches.

## Handoff

- B1 → B2 → B3 → B4 → B5 `build` items → the `builder` subagent (Sonnet), one section at a
  time, in order. B1 first: everything after it assumes `pane`.
- `build-light` items → `builder-light` (Haiku), after B5's `build` items.
- B4b (done) and B6 are Claude's (`planner`).

## Build notes

- 2026-10-20, founder: build approved. Pre-mortem 7 resolved as planned (one switch plus a
  visible agent line). Capture promo sheet losing its door is accepted (§7).
- The `builder` subagents load only when a session starts in the repo root; this session
  started elsewhere, so each step goes to a Sonnet/Haiku subagent given `.claude/agents/builder*.md`
  and the AGENTS.md handoff verbatim.
- B2, planner: added `AppStore.showAIFolder()` so the AI-folder row sets a status message
  like every other row (B2 had it writing `pane` directly).
- B3, planner: `showGardenFolders()` → `setupTab = .folders`, status "Folders — the project
  folders Projects reads."
- B4, builder: `detailsOpen` lives in a private `AutomationTab` in `SetupView.swift`
  (initialised `.onAppear`); `ScheduleCard` keeps its own status strings. Accepted.
- B4, planner: the plan said move `routineStatus` unchanged, but its off text ("nothing runs
  unless you press a button below") contradicts the B4b subtitle. In `BackgroundWorkCard`
  only, it now reads "Off. You can still import by hand with Ingest now, under Details."
- B6, planner (2026-10-20): built a scratch vault with the CLI (`UNLIRICE_DATA_PATH`):
  a project note, two archived notes, and one flagged note. Agent settings went to
  `UNLIRICE_AGENT_SETTINGS` in scratch, and the running build wrote `monthlyReviewEnabled: false`
  there. The bare debug binary has no bundle ID, so computer use can't drive it. It was wrapped
  in a scratch `.app` (`com.calmdownoscar.unlirice.fourjobs-qa`, a fresh defaults domain). The
  launch showed Home with exactly 10 sidebar rows in the planned order (read from the
  accessibility tree). "The folder your AI can read" and "What your AI should always do"
  wrap to two lines rather than truncate.
- B6, blocked: the founder's screen was on a full-screen Space, so the QA window couldn't be
  brought over or clicked. The click-through walk is **unverified** until it runs on a
  regular desktop Space.
- Two-profile walk skipped on purpose: `profiles.json` resolves to the App Store app's group
  container. Verified by reading the code instead (`SetupView.visibleTabs` / `effectiveTab`).
