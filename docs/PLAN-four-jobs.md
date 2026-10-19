# PLAN — Four jobs: a sidebar for context, guardrails, security and projects

**Intent:** `docs/intent/INTENT-006-four-jobs.md`
**Planner:** claude. **Reviewer:** codex.
**Stage:** 2 draft
**Pre-mortem:** not run
**Branch:** `claude/four-jobs`, cut from `codex/project-garden` at `06ef490` (Garden isn't on
`main` yet, and this plan rebuilds the navigation Garden plugs into). The hygiene hook
warns about branch drift. That's expected until Garden merges.
**Verified against:** `6fde23f` on `claude/four-jobs`

## 0. What was asked for

> "the features on unli rice are too many now. We need to simplify the app to focus on
> context, guardrails, security and keeping track of things like gits"

Founder decisions, 2026-10-19: the keep/cut list in INTENT-006 is approved as drafted.
Hide, don't delete. Mac app only. "What runs on its own" becomes one visible switch in
Setup.

## 1. What already exists (checked, not assumed)

- **Sidebar:** 9 rows, `ContentView.swift:123-195`: Home, Garden, Notes, To do, Repos,
  Needs you (only when the badge > 0), Your year so far, Map, More. Plus `CapturePromoCard()`
  at `:198`.
- **Routing:** 18 `@Published var showing…` flags in `AppStore.swift`. They're cleared in
  `closeAllPanes()` (`:1096-1119`) and again by hand in `selectNote` (`:1370-1390`), and
  read through an if-chain in `ContentView.mainColumn` (`:226-253`). The "Notes" row's
  active state negates 14 of them (`:138-144`). A missed flag has already caused a
  shadowing bug (comment at `AppStore.swift:1113-1117`).
- **More** (`MoreView.swift`): a chip bar over 9 destinations (`:6-14`): Setup, Why not a
  text file, Separate memories, House rules, The folder your AI can read, What runs on its
  own, Trust Center, Notifications, Archived. It also holds the **"Rate Unli Rice" row**
  (`:116-143`), which the studio guardrails require to stay permanent.
- **Setup** (`SetupView.swift:10-16`): 5 tabs, 4 of which repeat More's chips (Separate
  memories, House rules, Folder, What runs on its own) plus AI Tools (`ConnectView`).
- **Automation** (`AutomationView.swift:40-52`): with Advanced Mode **off**, it shows only
  `SimpleScanRootsCard` (folders). The two schedule switches (`ScheduleCard`, `:142-170`:
  "Run routines on a schedule" = `routinesEnabled`, and "Keep working with the window
  closed" = background agent) show **only with Advanced Mode on**. A user who switches
  routines on and Advanced Mode off has routines running with no visible switch.
- **What `routinesEnabled` gates:** `RoutineDriver.swift:185` runs Claude session import
  and the routines only when it's on. The folder mirror (`:170-182`) and notices run
  either way. The agent logs "routines are off" (`unlirice-agent/main.swift:280`).
- **One folder list, four readers:** `store.scanRoots` (`AppStore.swift:378`) feeds
  document import, Repos (`RepoPaneView.swift:275`), Garden (`ProjectGardenView.swift:245`)
  and To do (`TodoPaneView.swift:193`).
- **Year-so-far notices:** `RoutineDriver.swift:264-275` posts one per month when
  `settings.monthlyReviewEnabled`. The GUI hard-codes that to `true`
  (`AppStore.swift:912`). Opening one calls `showRetrospective` (`AppStore+Notices.swift:52-53`).
- **Links into hidden or moving places:** Home → Profile Builder (`HomeView.swift:158`,
  the "no memory profile yet" state) and → House rules (`:334`). Garden → Repos
  (`ProjectGardenView.swift:95`) and → folders (`:96`, `:223`). Copy that names "More":
  `FirstRunView.swift:57`, `RepoPaneView.swift:134`, `CapturePromoView.swift:207`,
  `ProjectGardenView.swift:200`, `README.md:26`.
- **Profiles:** `ProfileRegistry.profiles` (`Profile.swift:33`). Setup's profiles tab hosts
  both the Profile Builder launch button and `ProfileManagerView` (`SetupView.swift:63-83`).
- **Export menu:** File → Export Notes lists every `ExportFormat` (`UnliRiceApp.swift:63-71`):
  Markdown, OKF Bundle, Zip, PDF.
- **Tests:** one test target, `UnliRiceCoreTests`. No app-target or UI tests, so the
  navigation has no automated coverage. Last recorded full run: 406 tests, 2 skipped
  (memory.md, Codex, 2026-10-19). Unverified on this branch until B0.

## 2. Decisions

| Decision | Chosen | Credible alternative, and why it lost |
|---|---|---|
| Routing state | One `Pane` enum replaces the 18 flags | Keep the flags and edit the chain: every new row adds another negation to `:138-144`, and that's the bug class that already shipped once. |
| Hidden features | Enum cases and views stay compiled, but no sidebar row points at them | Delete the views: founder chose hide. Bringing one back means adding one `sidebarRow` line. |
| Sidebar shape | Four small headings (CONTEXT, GUARDRAILS, SECURITY, PROJECTS) with rows under them, then Setup at the bottom | Page names only: the intent's test is that a first-time user can tell what the app is for from the sidebar alone, and the headings are what say it. |
| More hub | Removed. Its destinations become rows or Setup tabs | A slimmer More: that's the junk drawer this plan exists to empty. |
| Projects | One "Projects" row. The page has a segmented control: **Overview** (Garden) and **Branches & worktrees** (Repos) | Fold Repos' graph into each Garden card: better, but it means splitting the repo scan per project. That's new work, deferred. |
| Needs you + Notifications | One always-visible "Needs you" row (badge only when > 0). The page links to "All messages" (the notice list) | Always show the full notice list inline: Needs you is for what's waiting. History is one click away. |
| The one switch | `routinesEnabled`, shown in Setup outside Advanced Mode, at the top of a "What runs on its own" tab. The other Automation cards sit under it, collapsed in a "Details" disclosure | Merge the two schedule switches into one: they're independent (`setBackgroundAgent` vs `routinesEnabled`), and one switch can't truthfully show both states. "Keep working with the window closed" moves into Details. |
| Folders | Their own Setup tab, "Folders". Garden's "Manage folders" opens it | Keep them inside Automation: the folders are what Projects reads, and burying them under background work hides that. |
| Year so far | GUI writes `monthlyReviewEnabled: false`. Existing `.retrospective` notices open nothing (they're just marked read) | Leave the notices on: they'd link to a page that no longer has a door. |
| Separate memories | Setup tab shown only when `profiles.count > 1`. Profile Builder stays reachable from Home's empty-profile state | Hide it always: that strands anyone who already has two memories (INTENT-006, open question 1). |
| Rate row | Moves to the foot of Setup | Every page: the guardrail asks for quiet. |
| Exports | Menu lists Markdown and OKF Bundle. Zip and PDF are filtered out | Remove the menu: export is how a user leaves with their data, which is part of Security. |

## 3. Point of view and patterns

- **Feel:** a quiet control room with four labelled doors. You check what you came for and
  close the app.
- **Not this:** a sidebar that lists every capability, or a More drawer you have to scroll
  sideways through.
- **Reused:** `sidebarRow` (`ContentView.swift:205`), every existing pane view as-is,
  `MoreView`'s content switch (minus the chip bar), `Theme` tokens, and the monospaced
  small-caps label style already used for "WHAT YOUR AI KNOWS ABOUT YOU"
  (`HomeView.swift:89`) for the section headings.
- **New:** a `Pane` enum, a private `sidebarHeading` helper, and a private
  `ProjectsPane` wrapper (segmented control + Garden/Repos), all inside existing files.
  No new files, so `xcodegen generate` isn't needed.

## 4. Journey and states

**Journey:** 1. Open the app. The sidebar reads CONTEXT / GUARDRAILS / SECURITY / PROJECTS.
2. Check Home for what your AI knows. 3. Glance at Needs you if it has a badge. 4. Open
Projects to see where each repo stands. 5. Close the app.

| State | What the user sees, and what they can do |
|---|---|
| First run, nothing yet | `FirstRunView` as today, and its copy points at Setup (not "More → Setup"). After it: Home. |
| Success | Every kept destination is one click from the sidebar, and the active row is highlighted. |
| Empty or partial input | Projects with no folders: Garden's empty state, whose button opens Setup › Folders. Needs you with nothing waiting: "Nothing is waiting on you" plus the "All messages" link. |
| Slow (loading, latency) | Unchanged: Garden and Repos keep their own progress text. Switching panes stays instant. |
| Offline or failed, and how they recover | Unchanged per pane. An old year-so-far notice opens nothing and is marked read. |
| Permission denied | Unchanged: Repos' denied ancestry status. Folders the sandbox can't read show what they show today. |
| Interrupted and resumed | The app reopens on Home, as today. The pane isn't persisted (no new state). |
| Return visit | A user with routines on now sees the switch in Setup › What runs on its own, whatever Advanced Mode says. A user with 2+ memories still finds Separate memories in Setup. |

## 5. Tasks

### B0. Baseline
- [ ] `planner` Build and test on the branch before any change, and record the counts here
      — verify: `swift build --scratch-path /tmp/unlirice-spm-build && swift test --scratch-path /tmp/unlirice-spm-build`

### B1. One `Pane` value instead of 18 flags (`build`)
- [ ] `build` In `AppStore.swift`, add `enum Pane: Equatable { case home, notes, aiFolder,
      houseRules, todo, needsYou, notices, trustCenter, archived, projects, repos, setup,
      firstRun, profileBuilder, map, retrospective, whyNotTextFile }` and
      `@Published var pane: Pane = .notes` (today, with every flag false, the note list
      shows). Keep the launch choice at `AppStore.swift:630-634`: First Run or Home.
      Delete the 18 `showing…` stored properties and replace each with a get-only computed
      property (`var showingHome: Bool { pane == .home }` and so on), so the call sites that
      only read them still compile. `showingReviewQueue` maps to `.needsYou`.
      `showingMore`, `showingGetStarted` and `showingProfileManager` map to `.setup`.
      `showingAutomation` maps to `.setup` with `setupTab == .automation`, so add
      `@Published var setupTab: SetupView.Tab` here (the tab enum `SetupView.swift:10`
      already defines; B3 changes its cases).
      — files: `Sources/UnliRice/AppStore.swift`, `AppStore+Notices.swift`,
      `AppStore+Retrospective.swift` — done when: no `showing… = ` assignment remains
      anywhere — verify: `grep -rnE "showing[A-Z][A-Za-z]* = " Sources/UnliRice` prints nothing
- [ ] `build` Every `show…()` sets `pane` (and `setupTab` / `moreDestination` where it set
      them before) instead of calling `closeAllPanes()` + a flag. Delete `closeAllPanes()`.
      `selectNote(id)` with a non-nil id sets `pane = (pane == .archived ? .archived : .notes)`.
      — done when: `closeAllPanes` no longer exists — verify: `grep -rn closeAllPanes Sources` prints nothing
- [ ] `build` `ContentView.mainColumn` becomes a `switch store.pane`. For `.notes` and
      `.archived`, show `NoteDetailView` when a note is selected, otherwise the list for
      that pane (as today). — files: `ContentView.swift` — verify: build green

### B2. The sidebar (`build`)
- [ ] `build` Replace the rows at `ContentView.swift:123-195` with:
      CONTEXT: Home (`.home`), Notes (`.notes`), "The folder your AI can read" (`.aiFolder`).
      GUARDRAILS: "What your AI should always do" (`.houseRules`), To do (`.todo`),
      Needs you (`.needsYou`, **always visible**, `badge:` only when > 0).
      SECURITY: Trust Center (`.trustCenter`), Archived notes (`.archived`).
      PROJECTS: Projects (active for `.projects` and `.repos`).
      Then `Spacer()`, then Setup (active for `.setup`). Remove `CapturePromoCard()`.
      Headings use a private `sidebarHeading(_:)` styled like `HomeView.swift:89`: 10pt,
      bold, monospaced, `Theme.textSecondary`, 14pt top padding. Each row's `active:` is
      `store.pane == …`. — done when: the sidebar has exactly 10 rows and 4 headings —
      verify: build green, then B6
- [ ] `build-light` Row titles may truncate at the 190pt sidebar width. If "What your AI
      should always do" truncates, use "House rules" as the row title and keep the full
      phrase as the page title. — verify: B6 screenshot

### B3. More becomes a host, not a hub (`build`)
- [ ] `build` In `MoreView.swift`, delete the chip bar (`:38-62`) and render
      `store.moreDestination` alone. Show `rateFooter` only when the destination is
      `.setup`. `ContentView` routes `.aiFolder`, `.houseRules`, `.trustCenter`,
      `.archived`, `.notices`, `.setup` and `.whyNotTextFile` through it, setting
      `moreDestination` to match. — files: `MoreView.swift`, `ContentView.swift`,
      `AppStore.swift` — done when: no chip bar renders anywhere — verify: B6
- [ ] `build` `SetupView` tabs become: AI Tools (`ConnectView`), Folders, What runs on its
      own, and Separate memories **only when** `store.profileRegistry.profiles.count > 1`.
      Remove the House rules and Folder (mirror) tabs, since both are sidebar rows now.
      `SetupView` reads and writes `store.setupTab` (from B1) instead of its own `@State`, so
      other pages can open a given tab. — files:
      `SetupView.swift`, `AppStore.swift` — verify: build green

### B4. What runs on its own: one switch, always visible (`build`)
- [ ] `build` Make `ScheduleCard`, `AutonomyCard`, `JanitorCard`, `IngestCard` and
      `SimpleScanRootsCard` in `AutomationView.swift` non-private (internal), so Setup can
      place them. The "What runs on its own" tab shows, in order:
      (1) one toggle row bound to `store.routinesEnabled`, titled "Work in the background",
      with the copy in B4b; (2) a `DisclosureGroup("Details")`, collapsed by default,
      containing `ScheduleCard`'s second switch ("Keep working with the window closed"),
      `AutonomyCard`, `JanitorCard` and `IngestCard`. Delete `AdvancedModeToggleCard` from
      this layout, but leave `advancedModeEnabled` and its key in place, unused here.
      — files: `AutomationView.swift`, `SetupView.swift` — done when: the routines switch
      is visible with Advanced Mode on or off — verify: B6. Advanced Mode's own switch
      leaves this page, so B6 flips `unliRice.advancedModeEnabled` in the debug binary's
      defaults domain and relaunches
- [ ] `planner` B4b copy. On: "Unli Rice imports your Claude Code sessions and tidies your
      notes on a schedule. It only ever suggests changes." Off: "Nothing is imported or
      tidied on its own. Unli Rice still refreshes the folder your AI can read and posts
      messages to Needs you." The planner checks each clause against
      `RoutineDriver.swift:160-200` before the builder pastes it.
- [ ] `build` The Folders tab shows `SimpleScanRootsCard` (its own add/remove list), with
      one line under it: "Projects reads these folders. With background work on, Unli Rice
      also imports documents from them." (`planner` confirms the second sentence against
      `IngestRunner` first, or drops it.)

### B5. Projects, needs-you, links and copy (`build` / `build-light`)
- [ ] `build` A private `ProjectsPane` in `ContentView.swift`: a segmented `Picker` with
      "Overview" (`.projects` → `ProjectGardenView`) and "Branches & worktrees" (`.repos`
      → `RepoPaneView`), above the content. Remove Garden's header "Repos" button
      (`ProjectGardenView.swift:95`). Garden's "Manage folders" (`:96`, `:223`) and
      `showGardenFolders()` open Setup › Folders. — verify: B6
- [ ] `build` `NeedsYouView` gets an "All messages" button (opens `.notices`), shown always.
      `open(_ notice:)`: `.retrospective` marks the notice read and changes nothing else.
      — files: `NeedsYouView.swift`, `AppStore+Notices.swift`
- [ ] `build-light` `AppStore.swift:912`: `monthlyReviewEnabled: true` → `false`.
- [ ] `build-light` `UnliRiceApp.swift:65`: `ForEach(ExportFormat.allCases.filter { $0 != .zip && $0 != .pdf }, …)`.
- [ ] `build-light` Copy, exact replacements:
      `FirstRunView.swift:57` → "You can connect later from Setup."
      `RepoPaneView.swift:134` → "Add one in Setup › Folders and it will appear here."
      `CapturePromoView.swift:207` → "No Unli Rice Folder set yet. Set one under The folder your AI can read, somewhere inside iCloud Drive."
      `ProjectGardenView.swift:200` → "Add a project folder in Setup › Folders. A note titled “Project: Your project” appears here without a folder, too."
      `HomeView.swift:63` "Open Project Garden" → "Open Projects".
      Each `show…()` `statusMessage` that mentions "More" drops it.
      — verify: `grep -rn "More →\|More ->" Sources` prints nothing
- [ ] `build-light` `README.md:26`: "**Garden.** … below Home in the sidebar" → "**Projects.** …
      under Projects in the sidebar", and "Manage its folders through **More → What Runs on
      Its Own**" → "Manage its folders in **Setup › Folders**".

### One layer deeper
- [ ] Section headings aren't VoiceOver buttons. Add `.accessibilityAddTraits(.isHeader)`.
- [ ] Rows keep their keyboard focus order: top to bottom, Setup last.
- [ ] The Needs you badge is read with its row ("Needs you, 3"). Today the badge is a bare
      `Text` (`ContentView.swift:210-211`), so give the row an `accessibilityLabel`.
- [ ] No status message claims something happened that didn't.

### B6. Verify (`planner`)
- [ ] `planner` Build, test, and `git diff --name-only` within §6's list.
- [ ] `planner` Run the unsigned debug binary against a throwaway vault
      (`UNLIRICE_DATA_PATH=<scratch>/events.jsonl /tmp/unlirice-spm-build/debug/UnliRiceApp`,
      memory.md) and click every sidebar row, the Projects segments, Garden's "Manage
      folders", Needs you → All messages, and each Setup tab, with Advanced Mode on and off.
      Screenshot the sidebar for this plan.

## 6. Acceptance — against reality, not a builder's report

Ticked by whoever verifies the build (Claude or the founder), never by the builder.

**Mechanical**
- [ ] `swift build --scratch-path /tmp/unlirice-spm-build` and `swift test --scratch-path /tmp/unlirice-spm-build`
      green, test count equal to B0's (verified: <tool> YYYY-MM-DD)
- [ ] The Xcode Mac target builds (`xcodebuild -scheme UnliRice -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`)
- [ ] `git diff --name-only` stays within: `Sources/UnliRice/{AppStore,AppStore+Notices,AppStore+Retrospective,ContentView,MoreView,SetupView,AutomationView,NeedsYouView,ProjectGardenView,RepoPaneView,FirstRunView,CapturePromoView,HomeView,UnliRiceApp}.swift`,
      `README.md`, `docs/PLAN-four-jobs.md`, `memory.md`, `PROJECT_NOTES.md`
- [ ] Nothing under `Sources/UnliRiceCore`, `Sources/UnliRiceCapture`, `Sources/unlirice-mcp` or `Tests/` changed

**Editorial — in a running build, not a mock or a preview**
- [ ] With the styling ignored, the sidebar alone says what the app is for.
- [ ] Walked the §4 journey. Every state seen, or marked "(unverified)" with why.
- [ ] No page is reachable only through a page that has no door.
- [ ] §5's one-layer-deeper items checked by hand.

**Record**
- Built: …
- Verified: … Unverified: …
- Ready to release: no. New screenshots are needed, and the 6-Month Post-Mortem applies.

## 7. Known limits, accepted

- One folder list still serves both Projects and document import. Splitting it would change
  stored settings (tier 2 on its own), so it's out of scope. The Folders tab says so.
- Hidden views still compile and ship in the binary. That's the cost of "hide, don't delete".
- No automated navigation tests. B6 is a manual walk-through, and says so.
- The sidebar-lag hypothesis in memory.md isn't claimed fixed by B1.

## 8. Rides along or deferred

- Per-project branch graph inside each Garden card (the alternative that lost in §2).
- Deleting the hidden views, once the founder decides nobody misses them.
- App Store screenshots for the new sidebar, before the next submission.

## 9. Pre-mortem responses

_(after Codex's pre-mortem)_

## Handoff

- B1, B2, B3, B4, B5 `build` items → the `builder` subagent (Sonnet), one section at a
  time, in order. B1 first: everything after it assumes `pane`.
- `build-light` items → `builder-light` (Haiku), after B5's `build` items.
- B0, B4b and B6 are Claude's (`planner`).

## Build notes

_(written during the build)_
