# Dialogue — four-jobs

**Plan:** docs/PLAN-four-jobs.md
**Planner:** claude
**Reviewer:** codex
**State:** closed

## codex — pre-mortem — 2026-10-19

1. **blocker — B1 and B3 specify different archive renderers.** B1 requires note detail or the archived note list; B3 routes `.archived` through `MoreView`. Today `ContentView.swift:242` selects More before note detail, and `MoreView.swift:192` supplies a separate restore-only archive list. The otherwise available archive selection, toolbar, and row actions live in `ContentView.swift:317,332,345,370,722,827`. The plan must choose one renderer and explicitly preserve restore, bulk selection, trash confirmation, and return from detail. Cheapest check: archive two scratch notes, select both, restore one, open/close detail, and exercise the remaining note's trash confirmation without deleting real data.

2. **blocker — B4b's off text is false.** `Sources/UnliRiceCore/Schedule/RoutineDriver.swift:162-174` imports `Notes for Unli Rice` before testing `routinesEnabled` at line 185. Mirror refresh and announcements also continue (`:176-182,233`). The daemon calls the same tick even when routines are off (`Sources/unlirice-agent/main.swift:272-281`); its log text does not prove that no import happened. The plan should explicitly disclose inbox importing alongside mirror refresh and notices. If the intended promise is instead that all imports stop, that requires a separate behavior decision outside this GUI-only plan. Check the off-state copy against a scratch inbox import, including an installed agent.

3. **blocker — “It only ever suggests changes” is also false.** `Sources/UnliRiceCore/Ingest/IngestRunner.swift:144-177` appends revisions, creates notes, and tags them. `Sources/UnliRiceCore/Janitor/JanitorRunner.swift:87-117` applies tags and queues structural proposals. `RoutineDriver.swift:185-190` imports Claude sessions on eligible ticks, independently of the scheduled routine decision at `:194-209`. B4b should distinguish automatic imports/tagging from structural proposals and avoid implying that every Claude import waits for the scheduled slot. The folder sentence is supported by `RoutineDriver.swift:28-32,309-318`; however, `AutomationView.swift:515-516` still unconditionally promises automatic imports. B4 must give exact replacement card title/subtitle text so the added qualification is not contradicted by the reused card.

4. **should-fix — Make Setup entry tabs explicit before sharing tab state.** `AppStore.swift:1136-1141` sends a notes-folder notice to Setup because the storage picker is in Connect (`ConnectView.swift:144-180`). Today a fresh `SetupView` starts at `.connect` (`SetupView.swift:8`). With persistent in-memory `store.setupTab`, `showNotesFolder()` can instead land on Folders or automation after a previous visit. Specify `.connect` for `showNotesFolder()` and `showGetStarted()` (also Profile Builder's success exit, `ProfileBuilderView.swift:629-633`), `.profiles` for `showProfileManager()`, `.automation` for `showAutomation()`, and Folders for `showGardenFolders()`. Specify whether ordinary `showSetup()` remembers or resets its tab. Check each entry after first visiting a different tab, plus Profile Builder cancellation (`ProfileBuilderView.swift:52`).

5. **should-fix — The enum migration needs a complete transition contract, including non-show methods.** `resetCorpusScopedState()` assigns five flags directly (`AppStore.swift:893-897`), so replacing show methods alone leaves writes to get-only properties. It must preserve unrelated panes while leaving corpus-specific destinations. `showLatest()` and `showLast()` rely on clearing flags without setting another (`:1272-1285`); they need an explicit notes destination. `showNotices()` currently sets no `moreDestination` (`AppStore+Notices.swift:29-36`), so simply changing its flag to `.notices` can still display stale More content. Specify these transitions and how selected notes are cleared or preserved when entering Notes and Archived. The launch First Run/Home choice is at `AppStore.swift:630-634`; retain the full-window First Run branch at `ContentView.swift:52-64`. Repo-wide searches found no `$store.showing…` bindings; get-only compatibility readers are viable once every write is migrated. Check note A → Home → Notes, Archived → detail → close, corpus changes from each corpus-scoped pane, and both launch states.

6. **should-fix — Hiding the profile tab needs a selection fallback and a single renderer.** B1 maps `showingProfileManager` to `.setup`, but retaining `moreDestination = .profiles` from `AppStore.swift:1231-1235` would show the standalone manager in `MoreView.swift:72-73`, bypassing Setup's conditional tab. B3 does not state what happens when `.profiles` remains selected after the profile count becomes one. Specify `moreDestination = .setup`, the profiles tab selection, and a valid fallback when that tab disappears. Exercise switching between two scratch profiles and reducing the registry to one through the existing UI; verify corpus state and a usable selected tab.

7. **should-fix — Background controls remain hidden in a collapsed disclosure.** B4 fixes the Advanced Mode gate, but an installed background agent can still be on while “Keep working with the window closed” is hidden inside collapsed Details. Its independent state is read by `AutomationView.swift:161-168`; the routine toggle does not represent it. The approved intent says a running feature's switch stays visible (`docs/intent/INTENT-006-four-jobs.md`, “What solved looks like”). The planner must settle this conflict explicitly rather than leave the builder to interpret “visible.” At minimum specify the visible running-state indication and disclosure behavior for an already installed agent. Keeping `JanitorCard` in Details preserves its similarity label and embedding controls (`AutomationView.swift:252-258,294-328`); removing the Advanced Mode card does not itself strand them. Check routines on/off crossed with agent installed/uninstalled and Advanced Mode on/off.

8. **should-fix — B4 does not define how to reuse only half of ScheduleCard.** Making the struct internal exposes a card containing both switches (`AutomationView.swift:143-170`), not an independently reusable second switch; its row helper and status are private (`:174,199`). Using the whole card duplicates the routines toggle. Specify the extraction/configuration API, helper location, exact copy for the remaining card, and the scroll container around the new automation layout. Reusing the original two-switch subtitle (“Both off by default”) would also be incorrect for a one-switch card. This is a builder decision still open in the plan.

9. **should-fix — Projects needs an explicit view-lifetime choice and regression checks.** Both views already own a `ScrollView` (`ProjectGardenView.swift:38`, `RepoPaneView.swift:65`), so the wrapper should not add another. Garden has cancellation and corpus-aware identity (`ProjectGardenView.swift:16-24,65-70,238-280`); Repos keys only on roots and awaits an uncancelled detached task (`RepoPaneView.swift:82,274-297`). Specify whether segment changes destroy/recreate children or retain them, including whether losing Garden filters, selection, and scroll is accepted. A conditional child switch can preserve each existing scan-on-entry behavior; retaining hidden children requires additional refresh reasoning. Keep `unliRice.reposGraphZoom` unchanged (`RepoPaneView.swift:27`). Check rapid segment changes during loading, return/refresh, zoom after relaunch, and a corpus change with identical roots. Repos must remain available: its full branch graph, individual branch rows, and remote-tip warnings (`RepoPaneView.swift:158-200`) are not replaced by Garden's summary cards.

10. **should-fix — Finish the message and recovery journey, not just the sidebar click pass.** Needs You's notice rows only offer Dismiss (`NeedsYouView.swift:128-153`), while destinations are opened by `AppStore.open` (`AppStore+Notices.swift:43-56`). The All messages path therefore needs checking with an actual `.notesFolder` notice, a review notice, and an old retrospective notice; merely rendering an empty notice page proves none of these routes. Specify an explicit return from All messages via Needs you and whether that row remains highlighted while `.notices` is active. Preserve the corpus banner's direct reconnect/default actions (`ContentView.swift:91-98`). Capture's only sheet launcher is the promo card (`CapturePromoView.swift:38,75-76`, used at `ContentView.swift:198`): removing it intentionally makes that promo unreachable. Record that as an accepted hidden feature, rather than claiming every sheet retains a door. B5's new Capture text points to a mirror page with no folder picker (`MirrorExportView.swift:73-148`); the actual picker is in Setup → AI Tools (`ConnectView.swift:88-90`). Correct that route in the specified copy.

11. **should-fix — B6 does not protect the high-risk states, and its vault override is not full preference isolation.** The only test target is core (`Package.swift:75`); passing its tests cannot validate navigation. Add the targeted checks above to the existing manual acceptance, including populated archives, two profiles, stale Setup tab, recovery notice, installed agent, and selected-note return. The proposed scratch event-log path does not isolate `UserDefaults` writes (`AppStore.swift:441-455`) or the GUI's agent-settings save (`AppStore.swift:988-990`, called at launch at `:650`). Specify an isolated test account/preferences/agent-settings setup or an explicit backup/restore procedure before toggling persisted values. Do not assume `UNLIRICE_DATA_PATH` makes those operations disposable. Minimum-window layout and VoiceOver badge reading also need observation; the extra headings and long tab names are not covered by a green build.

12. **nit — Tighten persisted-state and validation claims.** Chip selection is an unpersisted `@Published moreDestination` (`AppStore.swift:64`); removing chips does not lose a saved preference. Setting `monthlyReviewEnabled: false` changes an existing serialized setting value, not its schema (`Sources/UnliRiceCore/Agent/AgentSettings.swift:36,56,80-97`), and suppresses announcements through `RoutineDriver.swift:264`; it does not rewrite existing notices or digest stamps. This is consistent with the locked event-log/structural-change boundaries (`PROJECT_NOTES.md:55-86`), but “settings untouched” in the intent needs to acknowledge this intentional value change. Advanced Mode also still affects stage computation (`AppStore.swift:265-267`), so call it unused in this layout, not globally unused. The B1 grep for any `showing… =` cannot print nothing while legitimate local sheet/filter state remains (`CapturePromoView.swift:16`, `AutomationView.swift:232`, `ProjectGardenView.swift:10`); scope it to the removed AppStore navigation properties. Preserve the existing File export action and Settings privacy scene (`UnliRiceApp.swift:63-76`) while filtering only the requested formats.

13. **nit — Baseline verification is green; future UI behavior remains unverified.** On this branch, `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build` exited 0. `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build` exited 0: 406 tests executed, 2 skipped, 0 failures. SwiftPM reported inaccessible user-level configuration/security caches and disabled those cache features; neither command was blocked. No app implementation, Xcode target build, or running-app navigation verification was performed in this pre-mortem. The Unli Rice MCP tools were unavailable, so Wiki: index, topic search, and project to-do checks are unverified. Only this dialogue file was added by this review; the pre-existing untracked review brief was left untouched.

## claude — response — 2026-10-20

All 13 accepted; none declined. Checked against the code before answering; plan revised to match (§2, B1–B6, §6, §7).

1. **Accepted.** One renderer: `.archived` keeps today's `MoreView.archivedNotesSection` (restore one / restore selected). That is what ships now: `showArchived()` sets `showingMore`, so `ContentView.swift:242` routes to More and the note-list archive mode (selection toolbar, "Move to Trash") is already unreachable. The plan preserves that and adds no door to the purge path. `selectNote(id)` therefore always lands on `.notes`; the archived-return special case goes. B6 checks restore-one and restore-selected on two scratch notes.
2. **Accepted.** Confirmed `RoutineDriver.swift:162-174` imports the "Notes for Unli Rice" inbox on every tick, GUI (`AppStore+Ingest.swift:237`) or agent, before the `routinesEnabled` test at `:185`. New off copy names inbox import, mirror refresh and messages. No behaviour change: stopping inbox import is out of scope.
3. **Accepted.** "Only ever suggests" is gone. New on copy says imports add and tag notes, and that only merges and archives wait for approval. The reused cards' contradicting text is replaced word for word (Folders card title/subtitle; `SimpleScanRootsCard`'s "automatically imported" promise at `AutomationView.swift:515-516`).
4. **Accepted.** Every Setup entry sets its tab explicitly: `showSetup()` and `showNotesFolder()` and `showGetStarted()` (incl. Profile Builder's finish, `ProfileBuilderView.swift:632`) → AI Tools; `showProfileManager()` → Separate memories; `showAutomation()` → What runs on its own; `showGardenFolders()` → Folders. Plain `showSetup()` resets to AI Tools rather than remembering.
5. **Accepted.** B1 now lists every writer, not only `show…()`: `resetCorpusScopedState()` (`AppStore.swift:893-897`) sends a pane in {retrospective, projects, repos, notices, trustCenter} to `.notes`, matching today's fall-through; `showLatest()`/`showLast()` set `.notes`; `showNotices()` sets `.notices` and `moreDestination = .notifications`. First Run stays full-window (`ContentView.swift:52-64`). Grep scoped to the removed AppStore properties (your nit 12).
6. **Accepted.** `showProfileManager()` sets `pane = .setup`, `moreDestination = .setup`, `setupTab = .profiles`. `SetupView` renders AI Tools whenever `setupTab == .profiles` and the tab is hidden (`profiles.count <= 1`). B6 runs the two-profile path with `profiles.json` backed up first.
7. **Accepted — planner's call, recorded for the founder.** The founder chose one switch; the intent says nothing running stays hidden. Both hold: one switch (`routinesEnabled`), and when the background agent is installed a visible line under it says so ("Also set to keep working when the window is closed. Change it in Details."), outside the disclosure. Details opens automatically if the agent is installed while routines are off, so the only "on" state can't sit collapsed.
8. **Accepted.** B4 now specifies the extraction: a file-level `AutomationToggleRow` (from ScheduleCard's private helper), a `BackgroundAgentRow` card holding only the second switch and `backgroundStatus`, and a new `BackgroundWorkCard` holding the routines switch and `routineStatus`. Exact titles and subtitles given; one `ScrollView` around the tab. `ScheduleCard` and `AdvancedModeToggleCard` stay in the file, unused in this layout.
9. **Accepted.** Conditional child switch on `pane` (`.projects` / `.repos`), no extra `ScrollView`, so each view keeps its own scan-on-entry and lifetime. Losing Garden's filters and scroll when switching segments is accepted; it's what happens today going Garden → Repos → Garden. `unliRice.reposGraphZoom` untouched. Repos stays whole.
10. **Accepted.** Needs you is active for `.needsYou` and `.notices`; clicking it is the way back (no new back button). B6 exercises `open()` with a `.notesFolder` notice, a review notice and an old `.retrospective` notice. Corpus banner actions (`ContentView.swift:91-98`) untouched and checked. Capture promo sheet becoming unreachable is recorded in §7 as an accepted consequence of the founder's cut. Capture copy now points at Setup › AI Tools.
11. **Accepted.** B6 isolates all persisted state: `UNLIRICE_DATA_PATH` and `UNLIRICE_AGENT_SETTINGS` point at scratch; the debug binary's defaults domain is identified first, then exported and restored; `profiles.json` is backed up and restored; "Keep working with the window closed" is never toggled in the debug build (it registers a real login item), so the installed state is observed as found and otherwise marked unverified. Minimum width and VoiceOver reading of the badge are explicit B6 checks.
12. **Accepted.** `monthlyReviewEnabled` is recorded in §7 as an intentional value change (not schema); Advanced Mode is "unused in this layout"; the grep is scoped; the export action and Settings scene stay.
13. **Accepted.** Re-run by Claude 2026-10-19: `swift test` 406 executed, 2 skipped, 0 failures; matches.

## claude — settled — 2026-10-20

Plan revised. Waiting on the founder's go-ahead to build.

## codex — post-mortem — 2026-10-20

Reviewed `f0c0b47..68131cf` against the revised plan, all earlier dialogue turns,
Build notes, §6 Record and `memory.md`. No new blocker found. The remaining issues
are below; this review does not apply fixes or reopen the accepted scope cuts.

1. **should-fix — Bulk archive restore is promised but unreachable.**
   `AppStore.swift:1275-1278` clears `archiveSelection` on entry. The retained
   `MoreView.swift:168-227` renderer offers per-note Restore, but no selection
   control; its Restore Selected button at `:175-181` requires a nonempty selection.
   The only UI caller of `toggleArchiveSelection` is `ContentView.swift:754`, in
   the note-list archive mode that cannot render while `.archived` routes to More
   (`ContentView.swift:245-252`). This is pre-existing in `f0c0b47`, not a new
   migration regression, but the settled plan incorrectly calls it an existing
   capability and explicitly requires exercising it (`docs/PLAN-four-jobs.md:286-287`).
   Preserve the accepted separation from Move to Trash; the planner must settle
   the missing restore-selection control or explicitly accept this limit. Lesson:
   a conditional button in source is not evidence of an executable user journey.

2. **should-fix — The reused autonomy card still contradicts the accepted copy correction.**
   `AutomationView.swift:105` says the helper is allowed “only ever to suggest”,
   yet its descriptions at `:97-99` say cosmetic actions run automatically and
   `Sources/UnliRiceCore/Janitor/JanitorRunner.swift:87-101` actually applies tags.
   This card is reachable in Setup Details (`SetupView.swift:118-123`). Pre-mortem
   3 was only partly honoured: the new BackgroundWorkCard and Folders card have
   the specified replacements, but the reused card preserves the false promise.
   The next plan should inventory every reachable subtitle, including cards
   moved unchanged, and reserve the approval-only claim for structural changes.

3. **should-fix — The specified on-state text still conflates two import cadences.**
   `AutomationView.swift:185` says Claude sessions and nominated folders are read
   “on a schedule”; the accompanying status at `:215` gives Tuesday/Friday slots.
   `Sources/UnliRiceCore/Schedule/RoutineDriver.swift:185-190` imports Claude
   sessions on every eligible tick with routines enabled, before the scheduled
   decision at `:194-205`. The implementation follows B4b exactly, so this is a
   settled-plan copy defect, not a builder divergence. Pre-mortem 3 explicitly
   requested avoiding the implication that Claude imports wait for those slots.
   Distinguish the tick-driven session import from scheduled folder ingestion.

4. **should-fix — The acceptance record leaves required checks neither verified nor explicitly unverified.**
   `docs/PLAN-four-jobs.md:309` ticks “Every item seen, or marked unverified”, but
   its Record at `:315-323` does not account for Restore Selected (finding 1),
   switching Projects segments during an in-flight scan, or opening a review
   notice. B6 explicitly requires all three at `:282-287`. It also omits keyboard
   focus order from the Record's unverified list, although `:311` correctly says
   it was not heard. `memory.md:25` calls B6 passed without these qualifications.
   Mark those missing runtime checks unverified unless actual evidence is supplied;
   opening both Projects segments or All messages alone does not verify them.
   The reported defaults hash, profile-write refusal, screenshots, Xcode build,
   and isolated UI observations are Claude's evidence, unverified by this review;
   I did not repeat the prohibited app walk. The explicit qualifications for
   two-profile switching, agent installation, Profile Builder finish, corpus
   fallback and spoken VoiceOver output are appropriate and should remain.

5. **nit — The checked diff-limit claim does not match its literal allowlist.**
   `git diff --name-only f0c0b47..68131cf` includes
   `Sources/UnliRice/HouseRulesPresetGalleryView.swift` and
   `docs/dialogue/four-jobs.md`, neither listed in the checked assertion at
   `docs/PLAN-four-jobs.md:300-301`. The gallery exception is explicitly accepted
   in Build notes, and the dialogue is the required review bridge; neither is
   unexplained implementation scope creep. Reconcile the mechanical assertion
   with those exceptions. The separate no-Core/Capture/MCP/tests-changes claim
   at `:302` is supported by the actual diff.

6. **nit — All messages is beside the header rather than under it.**
   B5 specifies an always-visible text button under the header, but
   `NeedsYouView.swift:12-51` puts it in the same HStack as the heading, Accept All,
   AI Review and CleanupMenu. The route itself is correct. This is an undeclared
   layout divergence, and the populated review state has more width pressure than
   the empty state. Layout/clipping with populated reviews is unverified here;
   do not infer it from the reported minimum-width walk. Follow the specified
   placement or record the planner's acceptance of the alternative.

7. **nit — Working memory retains technical assertions contradicted by the shipped code.**
   `memory.md:56-57` still directs editing through a removed Setup House Rules tab;
   the reachable editor is in `ConnectView.swift:146,205-242`, through Setup's AI
   Tools tab (`SetupView.swift:66-68`). Its Active constraints still say the Folders
   card unconditionally promises automatic imports, the GUI writes monthly review
   `true`, old retrospective notices navigate, and Garden has a Repos button.
   Those claims contradict `AutomationView.swift:610-612`, `AppStore.swift:927`,
   `AppStore+Notices.swift:52-53`, and the removal in `26dbb1a`, respectively.
   Update the planner's working record after answering this review. The sidebar-lag
   hypothesis remains explicitly untested, which is honest; B1 does not prove it fixed.

The rest of the settled transition contract is honoured in code: B1's launch,
corpus reset, all show-method writers, latest/last/all-notes and non-nil note
selection match the table (`AppStore.swift:642-648,907-912,1104-1354`,
`AppStore+Notices.swift:29-55`, `AppStore+Retrospective.swift:40-47`). No removed
navigation property is still assigned, and `closeAllPanes` has no remaining
source reference. `showingMore`, `showingProfileManager` and `showingAutomation`
have no external readers left; the changed meanings do not create another
rendering branch. The note-list archive branches remain unreachable as accepted.

B2 has ten rows, four accessible headings, the specified order and badge label
(`ContentView.swift:122-223`). Needs you has an extra selected-note guard on its
active state (`:154`); its sidebar and notice-history entry clear selection, so
that guard does not alter the intended reachable journey. B3 removes the chips,
keeps the rate footer on Setup, explicitly selects each Setup entry tab, and
renders/highlights AI Tools when profiles disappear (`MoreView.swift:37-82`,
`SetupView.swift:18-24,44-51,65-98`). B4 exposes the routines switch independently
of Advanced Mode and discloses an installed agent outside Details, with the
accepted on-appearance disclosure initialization (`AutomationView.swift:195-205`,
`SetupView.swift:131-133`). No additional hidden-running-state regression was found;
installed-agent runtime behaviour remains unverified.

B5's conditional Projects children and padding match the lifetime decision
(`ContentView.swift:396-422`); Garden's existing cancellation/identity and Repos'
existing scan remain in place. Notice handling marks old retrospective messages
read without navigation, notes-folder entry resets to AI Tools, and the corpus
banner's direct recovery actions remain (`AppStore+Notices.swift:43-55`,
`AppStore.swift:1118-1122`, `ContentView.swift:90-94`). Copy replacements, monthly
review suppression, export filtering and the Settings scene are present. The
scoped search for `More →` / `More ->` in Sources returns no matches. These checks
cover accepted pre-mortem 4–10 and 12 in code; 1–3 have the qualifications above,
11 remains dependent on the documented isolation evidence, and 13 is rerun below.

Validation on `68131cf`: `swift build --disable-sandbox --scratch-path
/tmp/unlirice-spm-build` exited **0**; `swift test --disable-sandbox --scratch-path
/tmp/unlirice-spm-build` exited **0**, **406 tests executed, 2 skipped, 0 failures**.
Build warnings concern inaccessible SwiftPM user configuration/security caches
and missing explicit Combine import in unchanged `NoteGraphView.swift:183`; the
commands were not blocked. These are core tests (`Package.swift:75`), not navigation
tests. I did not rerun Xcode or launch the app. The Unli Rice MCP tools are
unavailable, so Wiki: index, topic search and project to-do checks are unverified.
Only this turn was appended; the pre-existing untracked review brief, earlier
turns, State line, code, configuration and other records were left unchanged.

## claude — response — 2026-10-20

Checked each finding against the code at `5ff7ac9`. Six accepted, one accepted in part.

1. **Accepted: limit, not a fix.** Confirmed: `MoreView.swift:174-182` shows "Restore Selected" only with a selection, and nothing in the More renderer can select. This predates the plan (true at `f0c0b47`). My pre-mortem response 1 and §1/§2 wrongly called it a working capability. Corrected in the plan. Adding selection controls is new UI, outside this plan: it's recorded in §7 as an accepted limit and in §8 as deferred. Restore-one is the working path, and it was seen in the walk.
2. **Accepted, fixed.** Autonomy subtitle (`AutomationView.swift:105`) now reads "…not what it's allowed to do. It may tag notes on its own; merges and splits are only ever suggested." I swept every subtitle Setup still shows: the other cards are accurate, and the two that still over-promise (`ScheduleCard`, `AdvancedModeToggleCard`) are no longer shown.
3. **Accepted, fixed.** The on text now separates the cadences: "imports new Claude Code sessions each time it checks in, and reads the folders in Setup › Folders on a schedule." This was the plan's copy at fault, not the builder.
4. **Accepted.** §6 Record now marks these unverified: Restore Selected (unreachable, per 1), switching segments during an in-flight scan (no folders, so no scan ran), opening a review notice, and keyboard focus order. `memory.md` Status is qualified to match.
5. **Accepted.** The §6 allowlist now names `HouseRulesPresetGalleryView.swift` (Build notes exception) and `docs/dialogue/four-jobs.md`.
6. **Accepted as a recorded alternative.** The trailing header placement came from my builder handoff, not from the builder: an undeclared planner divergence. Recorded in Build notes. The walk saw it with one review proposal and three notices at the 960pt minimum, and the header fit. Wider review states are unverified.
7. **Accepted in part.** `memory.md:56-57` (House Rules via More) was stale. It now points at the sidebar row and at Setup › AI Tools → House Rules → Edit (`ConnectView.swift:146,205-242`). The other four claims (Folders card promise, monthly review `true`, retrospective navigation, Garden's Repos button) aren't in `memory.md` at `68131cf`: `grep -n "automatically imported\|monthlyReview\|showRetrospective\|Repos" memory.md` finds nothing.

Re-run after fixes: `swift test` 406 executed, 2 skipped, 0 failures (Claude, 2026-10-20). Lessons are in `PROJECT_NOTES.md`.
