# PLAN — Studio redesign: two tabs, a record-crate Garden, build-gate lights

**Intent:** `docs/intent/INTENT-009-studio-redesign.md` (approved 2026-10-30, amended after pre-mortem)
**Spec:** `docs/SPEC-studio-redesign.md` (ids A1–E4)
**Idea:** not needed — Unli Rice has existed since 2026-07; this is a redesign, not a new app
**Planner:** claude. **Reviewer:** codex.
**Stage:** 3 — settled 2026-10-30 after Codex's pre-mortem (`docs/dialogue/studio-redesign.md`,
14 findings, all accepted). Phase A may be built. Phase B (Idea Clinic) is blocked, see §6.
**Branch:** `claude/studio-redesign`, cut from `main` at `8d2189c` (1.4 (9), in App Review).
**Who builds (founder, 2026-10-30):** "If the build is happening on Mac Codex has to do it."
Claude Code on the Mac is out of weekly usage. Codex drives the build on the Mac by §7. Claude
stays the planner: it reviews every pushed step from a cloud session and merges it.
**Verified against:** `0bb4582`. No Swift in the cloud container that wrote this plan, so every
`file:line` was read, not compiled. The driver re-checks each step's cited lines before handing
it over (§7, step 1).
**Mockup:** claude.ai artifact `JQZD7Bq97CwaX3pFYiemtJ` (sample data).

## 0. What was asked for

> "Let's rebuild Unli Rice. I want a sleeker simpler easier look. Right now I barely understand my
> own app. … similar to the djay pro app … One could be all the tracked repos in the garden, the
> other could be the different branches and a third the notes."
> "Make sure whenever an app is built there is intent, spec and agent markdowns before building as
> well as pre mortem sent back and forth through the bridges." "Also add in the idea clinic."
> "Make the cards flip like albums in a record store." "Let's add tabs. One for guardrails and
> grounding." "Make things in the app Apple design fluid."

The founder's decisions are in INTENT-009 § "Answered". Keep macOS 13 with the glass fallback,
and name the first tab "Studio".

## 1. What already exists (checked, not assumed)

- **The window** is `ContentView.body` (`ContentView.swift:42-66`): `corpusBanner` over
  `HStack { sidebar; mainColumn }`. The sidebar is `:108-268`. `mainColumn` (`:270-302`) is an
  exhaustive `switch store.pane`. The minimum window is 960×600 (`UnliRiceApp.swift:42`).
- **Navigation** is `AppStore.pane: Pane` (`AppStore.swift:72-78`, 17 cases), with a `show…()`
  method per case (`AppStore.swift:1139-1390`). The launch pane is `.notes`, or `.firstRun` for a
  new install.
- **Garden data.** `ProjectGarden.load(roots:notes:publishedSnapshot:now:)`
  (`ProjectGarden.swift:82`) is pure.
  - `Project` (`:18-44`) carries `status`, `statusDate`, `notes`, `repository` and
    `issues: [String]`.
  - `needsAttention` (`:33`) is counts only. It says nothing about read health; `issues` does.
  - `Project` is copied field by field in five places (`:144,250,364,370,417`), so adding a
    field is costly. This plan adds none.
  - The project markers are `.git`, `memory.md` and `PROJECT_NOTES.md` (`:179`).
- **Branches.** `RepoPaneView` (341 lines) scans with `GitRepoScanner` and draws
  `BranchGraphView`.
- **Folder grants.** `AppStore.addScanRoot(_:)` (`AppStore+Ingest.swift:124`) is the one place
  that stores a security-scoped bookmark for a Garden folder.
- **Glass.** `LiquidGlass.swift`: `.liquidGlass(…)` / `.liquidGlassCapsule(…)`. It is
  `.glassEffect` on macOS 26 and `.ultraThinMaterial` below that. Materials turn opaque under
  Reduce Transparency.
- **Keyboard.** `.keyboardShortcut` with `KeyEquivalent.leftArrow` / `.rightArrow` is
  available on macOS 11+, so the arrow keys need no version exception. This is unverified on a
  real macOS 13 machine (Q-row K1 in §4).
- **Tests** cover `UnliRiceCore` only. Anything decidable as a pure function goes in core.

## 2. Design

### 2.1 Phases

- **Phase A** (built now): tabs, toolbar, the Studio decks, the Garden crate with build-gate
  lights, and the Guardrails & Grounding tab. The empty Garden shows one sleeve,
  **"Plant your first idea"**, which opens `https://www.calmdownoscar.com/idea-clinic/` in the
  browser through `NSWorkspace.open`. The app itself makes no network call.
- **Phase B** (blocked, §6): the native Idea Clinic, seeds and the save panel. It waits for one
  shared, language-neutral clinic data file on the website (pre-mortem finding 8).

### 2.2 What the lights mean (pre-mortem finding 1)

The lights **report files that exist**. They do not prove that anyone followed the rules, and
they block nothing. The gate itself is a rule in `AGENTS.md` that agents are asked to follow.
Every place the app shows lights says so in one line: "Lights show which files exist in this
repo."

### 2.3 Navigation

- **Pane changes.** `Pane` gains `.studio` and `.guardrailsGrounding`. The launch pane becomes
  `.studio`, and a new install still starts at `.firstRun`.
- **Sidebar removed.** The `sidebar`, `sidebarRows`, `sidebarCapture`, `sidebarHeading` and
  `sidebarRow` code (`ContentView.swift:108-268`) is **deleted**. It stays recoverable from git
  history (finding 13).
- **A toolbar replaces it.** On the left, a glass segmented control with **Studio** and
  **Guardrails & Grounding**, using `.liquidGlassCapsule`, ⌘1 and ⌘2. On the right, a glass
  gear `Menu` with:
  - Setup;
  - Trust Center;
  - Archived notes;
  - To do, Map and Your year so far, each only when its Extra is on;
  - the iPhone Capture item, only when that Extra is on;
  - Rate Unli Rice, which calls the existing rating action.
- **Expanded decks** show a glass "All decks" button with `.keyboardShortcut(.cancelAction)`,
  so Esc works too.
- **`Extra.projects`** stays in the enum, so saved arrays decode, but it gates nothing, and its
  row is filtered out of Setup › Extras.
- **Routing table (A4, A5).** S8 walks every row of it, there and back.

| `Pane` | Reached from | Back to |
|---|---|---|
| `.studio` | Tab 1, and launch | — |
| `.projects` | The Garden deck's expand button | The Studio tab |
| `.repos` | The Branches deck's expand button | The Studio tab |
| `.notes` | The Notes deck's expand button, and Grounding's "Open notes" | Its tab of origin |
| `.guardrailsGrounding` | Tab 2 | — |
| `.home` | Grounding's "Details" | Tab 2 |
| `.aiFolder` | Grounding's "Open the folder" | Tab 2 |
| `.houseRules` | Guardrails' House Rules card | Tab 2 |
| `.needsYou`, `.notices` | Guardrails' "Need you" tile | Tab 2 |
| `.trustCenter` | Guardrails' "Safety checks" tile, and the gear menu | Tab 2 |
| `.archived` | Guardrails' "Archived" tile, and the gear menu | Tab 2 |
| `.setup`, `.profileBuilder`, `.whyNotTextFile` | The gear menu, then Setup | Tab 1 |
| `.todo`, `.map`, `.retrospective` | The gear menu, when that Extra is on | Tab 1 |
| `.firstRun` | Unchanged | Unchanged |

- **"Back to"** is `AppStore.lastTab: Pane`, either `.studio` or `.guardrailsGrounding`. It is
  set whenever a tab is shown, and the back button calls `show(lastTab)`.

### 2.4 The Studio tab

- **Layout.** At 1080 pt and wider there are three equal columns. Below that, Garden takes the
  full width, with Branches and Notes in a row beneath it.
- **Collapsed decks** show one picture, one headline number and at most one short list of up to
  five items (A2, revised for finding 5).
- **Top strip.** The front sleeve's name, its seven lights and its next step (A8), plus the line
  "Lights show which files exist in this repo."
- **Branches deck.** `BranchGraphView` for the front sleeve's folder, read-only. It shares the
  existing loader through `RepoSnapshotLoader`, extracted from `RepoPaneView` (B4). With no
  repository it shows the sentence "Pick a folder with a project in it" and a button that calls
  `chooseScanRoot()` (B5).
- **Notes deck.**
  - A ring split by `Note.creator`, with five buckets: `claude`, `codex`, `human`, `ingest` and
    "other".
  - The headline number is open (non-archived) notes, with "N need you" as the list's header.
    N is `pending.count + unreadNoticeCount`.
  - The list is the five newest titles. Its header names the source of the newest write.
  - An unreadable corpus shows the `CorpusHealth` reason, never 0 (B7).

### 2.5 The Garden crate (core: `GardenCrate`)

```swift
public enum GardenCrate {
    public enum State: Equatable, Sendable {
        case fine, needsYou, noStatus, cantRead(String)
    }
    public struct Sleeve: Identifiable, Equatable, Sendable {
        public let id: String          // Project.id
        public let name: String
        public let subtitle: String    // nextStep ?? status ?? "No notes yet", first line, ≤ 60 chars
        public let state: State
        public let lastActivity: Date?
        public let folderURL: URL?
        public let coverIndex: Int     // 0..<8, stable hash of id
    }
    public static func state(of project: ProjectGarden.Project) -> State
    public static func sleeves(from report: ProjectGarden.Report) -> [Sleeve]
    public static func stableIndex(_ id: String, modulo: Int) -> Int   // FNV-1a over UTF-8
}
```

**State** (finding 4). The first rule that matches wins:
1. `project.issues` is not empty: `.cantRead(issues[0])`.
2. `needsAttention`: `.needsYou`.
3. `status == nil && repository == nil`: `.noStatus`.
4. Otherwise `.fine`.

A project with a repository but no memory file is `.fine` only when the repository scan reported
no issue.

**Activity and order.**
- `lastActivity` is the maximum of `statusDate` and the related notes' `updatedAt`. It is nil
  when neither exists.
- The order is `lastActivity` descending. Nil dates go last. Ties and nil dates go by
  case-insensitive name.

**Stickers.** fine → "FINE", needsYou → "NEEDS YOU", noStatus → "NO NOTES YET",
cantRead → "CAN'T READ".

**View** (app: `GardenCrateView`, `SleeveBackView`):
- **Stack.** The front sleeve sits on top, with up to three behind it. The behind ones are offset
  26 pt upward and scaled −6 % per step. Flipped sleeves rotate −84° about the bottom edge and
  fade.
- **Motion.** `.spring(response: 0.45, dampingFraction: 0.78)`. With
  `@Environment(\.accessibilityReduceMotion)` on, `.easeInOut(duration: 0.2)` with opacity only
  (A10).
- **Input:**
  - the previous and next buttons, with `.keyboardShortcut(.leftArrow, modifiers: [])` and
    `.rightArrow`, active only while the crate is on screen;
  - a click on a sleeve behind;
  - a `DragGesture(minimumDistance: 40)` horizontal swipe.
- **Position indicator.** At 20 sleeves or fewer, a dots row. Above 20, the text "12 of 60"
  plus the expanded view's **List** toggle (finding 10).
- **Names** wrap to two lines, then truncate at the tail. The full name goes into
  `.help(…)` and `.accessibilityLabel` as "<name>, <sticker>".
- **Expanded (`.projects`):**
  - A big crate on the left. On the right, the sleeve back: the seven stages as a tracklist,
    Side A (Idea to Pre-mortem) and Side B (Build, Post-mortem). Each row has its light and its
    word.
  - Under the tracklist: the next step's sentence and **Copy prompt**. The prompt names the
    feature slug and the exact file the next stage needs. It is plain text, and it writes no
    file (C10).
  - A **List** toggle shows the existing `ProjectGardenView`, unchanged.
- **Empty state.** One sleeve, "Plant your first idea", with a "Pick a folder" link beside it.

### 2.6 `BuildGate` (core), bound to one feature (findings 2, 3, 7, 10, 12)

```swift
public enum BuildGate {
    public enum Stage: String, CaseIterable, Sendable {
        case idea, intent, spec, agents, premortem, build, postmortem
    }
    public enum Light: Equatable, Sendable {
        case done
        case draft(String)          // exists, not yet approved/settled; reason shown
        case skipped(String)        // founder skip recorded in the plan header; quote shown
        case notRequired(String)    // e.g. "older plan", "not a new app"
        case notRecorded            // nothing says either way (Idea only)
        case missing                // folder read fine, file absent
        case unknown(String)        // could not read / too large / ambiguous
    }
    public struct Result: Equatable, Sendable {
        public let slug: String?
        public let openPlans: [String]   // slugs of plans not yet built, sorted
        public let lights: [Stage: Light]
    }
    public static func read(folder: URL, slug: String) -> Result
    public static func current(folder: URL) -> Result
}
```

**Picking the feature (`current`).**
- List `docs/` at depth 1 only, with at most 500 entries. Over 500 gives every light
  `unknown("too many files in docs/")`.
- Collect the `PLAN-<slug>.md` files. A plan is **open** unless its `**Stage:**` line contains
  "built", "closed" or "post-mortem".
- Exactly one open plan → that slug. Several → the one with the newest modification date. The
  others are listed in `openPlans` and on the sleeve back.
- **Modification dates only choose which feature to show.** They never decide which files count
  as evidence.
- No plans: `slug = nil`. Agents is still read, and every other light is `notRecorded`.

**Reading one feature (`read`).** Every path comes from the plan, never from a search:

| Stage | Evidence (paths are relative to the repo root) | Light |
|---|---|---|
| Intent | The path on the plan's `**Intent:**` line | `done` if that file's `**Status:**` starts with "approved"; `draft("not approved yet")` if it exists otherwise; `missing` if absent, or if the plan has no Intent line |
| Spec | The path on the plan's `**Spec:**` line | No Spec line: `notRequired("older plan")`, so legacy plans are not shown as failures. Otherwise `done` if `**Status:**` starts with "approved" **and** its `**Intent:**` line names the same intent path; a different intent gives `unknown("spec names a different intent")`; any other status gives `draft(<status>)`; a file that isn't there gives `missing` |
| Agents | `AGENTS.md` and `CLAUDE.md` at the root | `missing` if there is no `AGENTS.md`. With a `CLAUDE.md` that has no line equal to `@AGENTS.md` (after trimming), `draft("CLAUDE.md doesn't import AGENTS.md")`. Otherwise `done` |
| Idea | `docs/idea/IDEA-<slug>.md`, and the plan's `**Idea:**` line | `done` if the file exists; `notRequired(reason)` for "not needed — reason"; `skipped(quote)` for "skipped — quote"; otherwise `notRecorded` |
| Pre-mortem | `docs/dialogue/<slug>.md`, and the plan's `**Pre-mortem:**` line | See below |
| Build | The plan's `**Stage:**` line | `done` if it contains "built" or "post-mortem"; otherwise `missing` |
| Post-mortem | The dialogue file | `done` if a post-mortem turn **by the reviewer** comes after the planner's `settled` turn; otherwise `missing` |

**Parsing the dialogue file.**
- Read the header lines `**Planner:**`, `**Reviewer:**` and `**State:**`.
- Turns are lines matching `^## ([a-z]+) — (pre-mortem|response|settled|post-mortem|rebuttal) — (\d{4}-\d{2}-\d{2})\s*$`.
  Lines inside fenced code blocks don't count.

**The Pre-mortem light:**
- `skipped(quote)` if the plan has `**Pre-mortem:** skipped — <quote>`.
- `missing` if the dialogue file is absent.
- `unknown("reviewer and planner are the same tool")` if the header names the same tool for
  both.
- `done` only if all of these hold:
  - `State` is settled, built or closed;
  - a pre-mortem turn's author equals `Reviewer`;
  - a settled turn's author equals `Planner`;
  - that settled turn comes after the reviewer's last pre-mortem or rebuttal turn.
- `draft("waiting for the planner to settle")` if there is a reviewer pre-mortem but no valid
  settled turn.
- A turn whose author is neither header tool is ignored and adds an issue.

**Bounds and reading rules.**
- Each file is read up to 128 KB. A larger file gives that stage
  `unknown("file too large to check")`.
- A path that resolves outside the folder (`..` or a symlink) gives `unknown`.
- Every read failure gives `unknown(reason)`, never `missing` (C2).
- Nothing is written (C9).

### 2.7 The Guardrails & Grounding tab

Two decks, built only from existing data. The destinations are in §2.3.

- **Grounding.** Four bars: open notes, the mirror folder (its last export date), Claude Code
  memory files and Codex memory files. The last two are dashed and labelled "Coming later",
  because INTENT-007 Phase B is not built.
- **Guardrails.** The House Rules card shows the active preset's name and the first three
  non-empty lines of its text. It sits beside three tiles: Need you, Safety checks and
  Archived. A dashed row reads "Did your AI follow the rules? Coming later" (Phase C).

### 2.8 Colour and contrast (core: `StudioPalette`, finding 10)

`StudioPalette` lists every text-on-surface pair the Studio uses, as sRGB hex for dark and
light. `contrastRatio(_:_:)` implements the WCAG 2.x relative-luminance formula. A test asserts
4.5:1 or better for every text pair, and 3:1 for the light and sticker glyphs against their
surfaces. The app builds its `Color`s from these values.

## 3. Phase A steps

Each step is given to a builder with the handoff in §7. "Tests" means
`swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`. "App build" means
`swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build --product UnliRiceApp`.

| Step | Label | What | Files (exact; anything else is a stop) | Spec | Verify |
|---|---|---|---|---|---|
| S1 | build | `BuildGate` exactly as §2.6, with tests: `testFeatureBindingIgnoresOtherFeaturesFiles`, `testTwoOpenPlansPicksNewestButListsBoth`, `testCopiedTimestampDoesNotChangeEvidence`, `testDraftSpecIsDraft`, `testSpecNamingOtherIntentIsUnknown`, `testLegacyPlanSpecNotRequired`, `testSettledByWrongAuthorIsNotDone`, `testSettledBeforeLastPremortemIsNotDone`, `testHeadingInsideCodeFenceIgnored`, `testSameToolBothRolesUnknown`, `testPremortemSkipRecorded`, `testIdeaNotRecordedByDefault`, `testIdeaNotRequiredLine`, `testClaudeMdWithoutImportIsDraft`, `testUnreadableFolderIsUnknownNotMissing`, `testOversizeFileUnknown`, `testDocsOver500EntriesUnknown`, `testSymlinkOutsideFolderUnknown`, `testReadsNothingOutsideDocsAndRoot` | `Sources/UnliRiceCore/BuildGate.swift` (new), `Tests/UnliRiceCoreTests/BuildGateTests.swift` (new). Fixtures are built in a temp directory inside the tests; there are no fixture files | C1–C9 | Tests |
| S2 | build | `GardenCrate` as §2.5, and `StudioPalette` as §2.8, with tests: `testIssuesMeanCantRead`, `testAttentionMeansNeedsYou`, `testNoStatusNoRepoIsNoStatus`, `testRepoWithoutMemoryIsFine`, `testOrderNewestFirstNilLastByName`, `testSubtitleFallbackAndTruncation`, `testStableIndexIsStable`, `testAllTextPairsMeetContrast` | `Sources/UnliRiceCore/GardenCrate.swift` (new), `Sources/UnliRiceCore/StudioPalette.swift` (new), `Tests/UnliRiceCoreTests/GardenCrateTests.swift` (new), `Tests/UnliRiceCoreTests/StudioPaletteTests.swift` (new) | B1, B2, A6 | Tests; the existing `ProjectGardenTests` (23) still pass |
| S3 | planner | Review S1 and S2 (on separate branches), merge both into `claude/studio-redesign`, and record the test counts | — | — | Rerun the tests at the merge |
| S4 | build | Navigation shell as §2.3. Add the `Pane` cases and `lastTab`. Delete the sidebar code. Add `StudioToolbar` (tabs and gear menu). Make `.studio` the launch pane. Hide `Extra.projects` from Setup › Extras. Add `mainColumn` cases that render `StudioView()` and `GuardrailsGroundingView()` as **placeholder views in the same new files** (a `Text` each), so the switch stays exhaustive | `Sources/UnliRice/AppStore.swift`, `Sources/UnliRice/ContentView.swift`, `Sources/UnliRice/Extras.swift`, `Sources/UnliRice/SetupView.swift`, `Sources/UnliRice/Studio/StudioToolbar.swift` (new), `Sources/UnliRice/Studio/StudioView.swift` (new, placeholder), `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` (new, placeholder) | A1, A4, A5, A9 | App build; `xcodegen generate` and the Xcode build |
| S5 | build | The Studio tab as §2.4. Replace the `StudioView` placeholder. Add the Notes and Branches decks. Extract `RepoSnapshotLoader` from `RepoPaneView` with no behaviour change. Add the top strip, the 1080 pt layout switch and the deck expand buttons routing to `.projects`, `.repos` and `.notes`. The Garden deck slot shows `GardenCrateView(compact: true)` from S6, so S5 uses a placeholder `GardenCrateView` in `Studio/GardenCrateView.swift` | `Sources/UnliRice/Studio/StudioView.swift`, `Sources/UnliRice/Studio/NotesDeck.swift` (new), `Sources/UnliRice/Studio/BranchesDeck.swift` (new), `Sources/UnliRice/Studio/GardenCrateView.swift` (new, placeholder), `Sources/UnliRice/RepoSnapshotLoader.swift` (new), `Sources/UnliRice/RepoPaneView.swift` | A2, A3, A7, A8, B4–B7 | App build; Xcode build |
| S6 | build | The Garden crate as §2.5. Replace the placeholder. Add `SleeveBackView`, the expanded `.projects` route (the `mainColumn` case changes from `ProjectsPane()` to `GardenExpandedView()`, which holds the List toggle to `ProjectGardenView`), Copy prompt and Reduce Motion | `Sources/UnliRice/Studio/GardenCrateView.swift`, `Sources/UnliRice/Studio/SleeveBackView.swift` (new), `Sources/UnliRice/Studio/GardenExpandedView.swift` (new), `Sources/UnliRice/ContentView.swift` (that one case only) | B1–B3, C10, A10 | App build; Xcode build |
| S7 | build | The Guardrails & Grounding tab as §2.7, replacing the placeholder | `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` | A1 | App build; Xcode build |
| S8 | planner (the founder or the Codex driver executes it, and Claude reviews the results) | The QA matrix (§4) in an isolated `.app` bundle against a throwaway vault | — | A3–A10 | §4 |
| S9 | planner | Copy sync with `docs/USER_GUIDE.md`. The public guide needs its own CalmdownOscar change | `docs/USER_GUIDE.md` | E4 | Review |
| S10 | planner | `PROJECT_NOTES.md` and `memory.md`; ask Codex for the post-mortem | — | — | — |

- **Order.** S1 and S2 may run in parallel on separate branches. S4 to S7 are sequential, and
  each is cut from the tip after Claude has merged the step before it.
- **New files.** Every new file under `Sources/` needs `xcodegen generate` before the Xcode
  build. The driver runs it, and builders don't.

## 4. QA matrix (S8)

Each row is recorded as pass, fail or "not run, because …". Nothing is left implied.

| Id | Check |
|---|---|
| Q1 | Launch at 1440×900 and at 960×600: the decks lay out without clipping, in both light and dark mode |
| Q2 | Every row of §2.3's routing table works, there and back, using the mouse only |
| Q3 | The same, using the keyboard only: ⌘1, ⌘2, Tab focus, Esc |
| Q4 | Crate with 0, 1, 5, 20 and 60 sleeves. Dots show at 20 sleeves or fewer, and "n of N" above that. A long name (60 characters) wraps to two lines, and its tooltip shows the full name |
| Q5 | Flipping works with the buttons, the ← and → keys, a click on a sleeve behind, and a swipe |
| Q6 | Reduce Motion: flips become fades. Reduce Transparency: the glass turns solid |
| Q7 | VoiceOver reads each sleeve as "<name>, <sticker>", the lights as "<stage>: <word>", and the tabs as tabs |
| Q8 | Larger text (the accessibility size in System Settings): nothing overlaps at 960×600 |
| Q9 | The lights in a fixture repo: a draft intent, a draft spec, a settled dialogue, a wrong-author settled turn, and a folder with no read permission. Each matches §2.6 |
| Q10 | Copy prompt: `pbpaste` shows the text, and `git status` in the fixture repo shows no change |
| Q11 | A project folder whose read permission is removed mid-session shows "CAN'T READ" after Refresh, not "FINE" |
| Q12 | Quit and relaunch: the app opens on the Studio tab, and the crate position is back to the newest sleeve |
| Q13 | Rate Unli Rice is in the gear menu and opens the review URL |
| K1 | The ← and → shortcuts on macOS 13, if a macOS 13 machine or VM is available. Otherwise "not run" |

## 5. Risks and gotchas

- **Existing users lose the sidebar they know.** What's New must say where things went. That is
  a release task.
- **`AgentSettings` is rebuilt on every launch.** No new setting goes there; use `UserDefaults`
  only.
- **The App Store build is in review.** Nothing here merges to `main` until 1.4 resolves.
- **Glass stays on the controls layer only.** Decks are `Theme` surfaces built from
  `StudioPalette`.
- **No time or token savings are claimed** for this work (finding 14).

## 6. Phase B: the Idea Clinic (blocked)

Phase B starts after a CalmdownOscar change. That change moves the clinic's question tree and
the three prompt templates out of `idea-clinic/app.js`, into a versioned `idea-clinic/clinic.json`
plus fixture answer sets with their expected outputs. Both the website (a Node test) and the app
(a Swift test) render the same fixtures to the same expected Markdown (finding 8).

That change belongs to INTENT-008's area. Phase B then gets its own steps, by amendment to this
plan, covering:
- the save panel described honestly as a user-authorized write;
- seeds discovered only inside scan roots, with an "Add this folder to the Garden" step through
  `addScanRoot(_:)` for a save outside the roots;
- a seed meaning a folder with `docs/idea/IDEA-*.md` and none of the three project markers, so
  memory-only projects stay projects;
- tests for nested roots, inaccessible folders and relaunch (findings 6 and 14).

Orca integration is moved out of this plan entirely (finding 11).

## 7. Build on the Mac, by Codex

Codex has two roles here, and they are kept apart:

- **The driver** is Codex on its best model. It runs this procedure and makes no design calls.
- **The builders** are `codex -p build` runs, one per step.

For each step in §3 labelled `build`:

1. **Check the step's ground.** Cut `codex/studio-<step>` (for example `codex/studio-S1`) from
   the current tip of `origin/claude/studio-redesign`, in a fresh worktree. Re-check every
   `file:line` this plan cites for that step. A mismatch is a stop: report it, and don't hand
   the step over.
2. **Hand the step over:**

   ```text
   Role: builder
   Intent: docs/intent/INTENT-009-studio-redesign.md
   Spec: docs/SPEC-studio-redesign.md (<spec ids from §3>)
   Plan: docs/PLAN-studio-redesign.md
   Step: <id and title from §3>
   Branch: codex/studio-<step>
   Files you may change: <files from §3, exactly>
   Changes already in the tree: none
   Verify with: <verify column from §3>

   Follow AGENTS.md § "Builder contract". The design is in the plan section the step names;
   implement it exactly. Anything it does not settle is a stop.
   ```

3. **Check before committing.** The run's `model:` and `reasoning effort:` lines must match the
   `AGENTS.md` table. `git diff --stat` must touch only the step's files. The driver reruns the
   verify commands itself; the builder's pasted output is not evidence. For app steps it runs
   `xcodegen generate` and the Xcode build:

   ```bash
   xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/unlirice-studio-derived CODE_SIGNING_ALLOWED=NO build
   ```

4. **Commit and push.** Commit on the step branch as `S<n>: <title> (unreviewed)` with the test
   counts, and push it. Never merge into `claude/studio-redesign` or `main`, and never push to
   them.
5. **Write the report.** Add `docs/BUILD-studio-redesign-S<n>-REPORT.md` on the same branch. It
   records:
   - the files changed;
   - each command with its pass/fail counts;
   - the model lines;
   - the result of the ground check;
   - anything a builder stopped on, with `file:line`.

   A stop ends the step. The driver does not retry with its own design.
6. **Claude reviews and merges.** Builders keep the circuit breaker: two failed attempts, or one
   on data integrity or architecture, and the step stops.
