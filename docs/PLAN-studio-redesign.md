# PLAN — Studio redesign: two tabs, a record-crate Garden, build-gate lights, Idea Clinic

**Intent:** `docs/intent/INTENT-009-studio-redesign.md` (approved 2026-10-30)
**Spec:** `docs/SPEC-studio-redesign.md` (ids A1–E4)
**Planner:** claude. **Reviewer:** codex.
**Stage:** 2 — plan drafted, waiting for Codex's pre-mortem in `docs/dialogue/studio-redesign.md`.
No `build` or `build-light` step is handed over until that file says `settled`.
**Branch:** `claude/studio-redesign`, cut from `main` at `8d2189c` (1.4 (9), in App Review).
**Who builds (founder, 2026-10-30):** "If the build is happening on Mac Codex has to do it."
Claude Code on the Mac is out of weekly usage. Codex therefore runs the build on the Mac by the
procedure in §7. Claude stays the planner: it answers the pre-mortem, settles, and reviews every
pushed step from a cloud session.
**Verified against:** `8d2189c` plus this branch's doc commits. No Swift in the cloud container
that wrote this plan, so every `file:line` below was read, not compiled.
**Mockup:** claude.ai artifact `JQZD7Bq97CwaX3pFYiemtJ`. It shows four screens: Studio, Garden
opened, Plant an idea, and Guardrails & Grounding. The data in it is sample data.

## 0. What was asked for

> "Let's rebuild Unli Rice. I want a sleeker simpler easier look. Right now I barely understand my
> own app. … similar to the djay pro app … One could be all the tracked repos in the garden, the
> other could be the different branches and a third the notes."
> "Make sure whenever an app is built there is intent, spec and agent markdowns before building as
> well as pre mortem sent back and forth through the bridges." "Also add in the idea clinic."
> "Make the cards flip like albums in a record store." "Let's add tabs. One for guardrails and
> grounding." "Make things in the app Apple design fluid."

The founder's decisions from 2026-10-30 are in INTENT-009 § "Answered". The founder also chose
to keep macOS 13 with the glass fallback, and to name the first tab "Studio".

## 1. What already exists (checked, not assumed)

- **The window and its sidebar.** `ContentView.body` (`ContentView.swift:42-66`) stacks
  `corpusBanner` over `HStack { sidebar; mainColumn }`.
  - The sidebar is `ContentView.swift:108-232`, 190 pt wide, with GROUNDING, GUARDRAILS and
    EXTRAS headings.
  - `mainColumn` (`:270-302`) is an exhaustive `switch store.pane`. A new `Pane` case therefore
    fails to compile until it is routed, which already covers spec A5.
- **Navigation state** is one `@Published var pane: Pane` (`AppStore.swift:72-78`). It has 17
  cases, and a `show…()` method for each (`AppStore.swift:1139-1390`). The launch pane is
  `.notes`, or `.firstRun` for a new install.
- **The minimum window** is 960×600 (`UnliRiceApp.swift:42`).
- **Garden data.** `ProjectGarden.load(roots:notes:publishedSnapshot:now:)`
  (`ProjectGarden.swift:82`) is pure and read-only.
  - It returns `Project`s with `status`, `statusDate`, `nextStep`, `notes`, `repository` and
    `needsAttention` (`:18-52`).
  - A folder counts as a project when it holds `.git`, `memory.md` or `PROJECT_NOTES.md`
    (`:179`).
  - `ProjectGardenView` (`ProjectGardenView.swift`, 533 lines) loads it off the main actor
    (`:239-264`) and renders a searchable list plus a detail sheet.
- **Branches.** `RepoPaneView` (341 lines) scans with `GitRepoScanner` and draws `BranchGraphView`
  (346 lines) with published ancestry. `ProjectsPane` (`ContentView.swift:440-468`) is a
  two-segment picker between the two.
- **Projects is an Extra.** `Extra.projects` (`Extras.swift`) gates the sidebar door
  (`ContentView.swift:199-206`). It is on for existing installs that used it and off for new
  installs.
- **Glass.** `LiquidGlass.swift` gives `.liquidGlass(cornerRadius:tint:interactive:)` and
  `.liquidGlassCapsule(…)`. It uses `.glassEffect` on macOS 26, and `.ultraThinMaterial` plus a
  hairline below that. System materials already turn opaque under Reduce Transparency.
- **Nothing reads Reduce Motion today.** A grep for `accessibilityReduceMotion` finds nothing.
- **Keyboard.** The only shortcuts are `.cancelAction` and ⌘⏎ (`ContentView.swift:994,1338`).
  There is no key handling for decks yet.
- **Entitlements.** `files.user-selected.read-write` is already granted, so a save panel needs
  nothing new. `network.client` is present, but Idea Clinic and BuildGate must not use it
  (D6, C9).
- **Idea Clinic source.** `CalmdownOscar/idea-clinic/app.js` was last changed at `3a3a10d`
  (2026-10-29). It has 20 question nodes, three endings and two shared helpers (`yesNo`, prompt builders).
- **Tests.** `swift test` covers only `UnliRiceCore`. App-target behaviour needs a QA bundle
  walk (`memory.md` § Gotchas). So anything that can be decided as a pure function goes in
  core.

## 2. Design

### 2.1 Where the logic lives

| Piece | Target | Why |
|---|---|---|
| `BuildGate`: seven light states from a folder | `UnliRiceCore` | Pure and testable (C1–C9) |
| `GardenCrate`: sleeves from `ProjectGarden.Report` plus seeds, state, order | `UnliRiceCore` | Ordering and state mapping are tested (B1, B2) |
| `IdeaClinic`: question tree, path, brief, three prompts | `UnliRiceCore` | Copy and branching are pinned by tests (D1, D3) |
| Tabs, decks, crate, sleeve back, clinic screens | `UnliRice` (app) | Views only. They call core and decide nothing |

### 2.2 Navigation

- `Pane` gains `.studio` and `.guardrailsGrounding`. These are the two tabs. The launch pane
  becomes `.studio`, and new installs still start at `.firstRun`.
- The sidebar is removed from `ContentView.body`, and a **toolbar** takes its place: a glass
  segmented control for the two tabs (`.liquidGlassCapsule`) and a gear button. The gear opens a
  menu: Setup, AI Tools, House Rules, Trust Center, Archived, the Extras that are switched on
  (To do, Map, Your year so far) and Rate Unli Rice. The rating row is required by the studio
  guardrails.
- `corpusBanner` stays above everything, unchanged.
- The `sidebar` code moves into `LegacySidebar.swift`, which nothing references. It is kept for
  one release so the change is easy to revert, then deleted in a later plan. **Pre-mortem
  target:** keep it, or delete it now?
- **Routing table (A4, A5).** Every existing case keeps its view.

| `Pane` | Reached from |
|---|---|
| `.studio` | Tab 1, and the launch pane |
| `.projects` | The Garden deck, expanded (now the crate, §2.4) |
| `.repos` | The Branches deck, expanded (`RepoPaneView`) |
| `.notes` | The Notes deck, expanded, and Grounding's "Open notes" |
| `.guardrailsGrounding` | Tab 2 |
| `.home` | Grounding's "Details" |
| `.aiFolder` | Grounding's "Open the folder" |
| `.houseRules` | The Guardrails House Rules card |
| `.needsYou`, `.notices` | The Guardrails "Need you" tile |
| `.trustCenter` | The Guardrails "Safety checks" tile, and the gear menu |
| `.archived` | The Guardrails "Archived" tile, and the gear menu |
| `.setup`, `.profileBuilder`, `.whyNotTextFile` | The gear menu, then Setup, unchanged |
| `.todo`, `.map`, `.retrospective` | The gear menu, when that Extra is on |
| `.firstRun` | Unchanged |

- Expanded decks show a glass "All decks" back button. Esc (`.onExitCommand`) does the same.
  Keys 1, 2 and 3 open each deck while the Studio tab has focus. ⌘1 and ⌘2 switch tabs, through
  `.keyboardShortcut` on the segmented items. These shortcuts are standard macOS, so they need
  no global key monitor.
- **Projects stops being an Extra.** The Studio tab is now the core. `Extra.projects` stays in
  the enum, so saved arrays still decode, but it gates nothing and its row leaves Setup › Extras.
  This reverses part of INTENT-007, at the founder's direction (INTENT-009 answer 1).

### 2.3 The Studio tab

- Three equal columns at 1080 pt and wider. Below that, Garden spans the full width and
  Branches and Notes share the row beneath it, so 960×600 still fits (A7).
- **The top strip** shows the front Garden sleeve's name, its seven lights and its next step
  (A8). With no projects it shows nothing.
- **Garden deck:** a compact crate (§2.4) with its arrows and dots.
- **Branches deck:** `BranchGraphView`, read-only, for the front sleeve's repository. With no
  repository it shows one sentence, "Pick a folder with a project in it", and a link to
  Setup › Folders (B4, B5). It reuses `RepoPaneView`'s loader, extracted into a small
  `RepoSnapshotLoader` in the app target, so the two can't drift.
- **Notes deck:** a ring split by `Note.creator` (Claude, Codex, you, imports, other), the
  open-note count, "N need you" (`pending.count + unreadNoticeCount`), the newest write's source,
  and the five newest titles (B6). An unreadable corpus shows the `CorpusHealth` reason (B7).

### 2.4 The Garden crate

**`GardenCrate.Sleeve`**, in core:
- `id`, `name`, `subtitle`, `kind` (`.project` / `.seed`), `state`
  (`.fine` / `.needsYou` / `.unreadable` / `.seed`), `lastActivity: Date?` and
  `gate: BuildGate.Result?`.
- `state`:
  - a seed is `.seed`;
  - a project with no readable status and no repository is `.unreadable`;
  - otherwise `needsAttention` gives `.needsYou`, and anything else is `.fine`.
- `lastActivity` is the newest of `statusDate` and the related notes' `updatedAt`. Commit dates
  are not available, because the scanner reads refs and not objects.
- **Order:** the newest `lastActivity` first. A nil date goes last, by name. Ties go by name.
- **Seeds:** `ProjectGarden.discover` gains one more marker. A folder holding `docs/idea/` with
  at least one `IDEA-*.md` becomes a candidate. A candidate with no `.git` becomes a seed.
  **Pre-mortem target:** does this new marker make discovery pick up folders it shouldn't?

**View** (`GardenCrateView`):
- The sleeves sit in a `ZStack`. The front one is full size, and up to three show behind it,
  offset upward and dimmed. Sleeves already flipped rotate forward about their bottom edge and
  fade out, as in the mockup.
- Flips use `.spring(response: 0.45, dampingFraction: 0.78)`, interruptible by default. With
  Reduce Motion on they become `.easeInOut(duration: 0.2)` cross-fades (A10).
- Input:
  - the arrow buttons;
  - ← and → (`.onKeyPress` on macOS 14+, buttons only on 13);
  - a horizontal trackpad swipe (`DragGesture` with a 40 pt threshold);
  - a click on a sleeve behind;
  - the dots row.
- **Cover art** is drawn, not loaded: a field colour from a fixed palette of eight, picked by a
  stable hash of the name, a record circle and the name. Only the sticker shows state, so colour
  alone never carries meaning.
- **Expanded (`.projects`):** a big crate on the left, and the **back of the sleeve** on the
  right. That is the seven stages as a tracklist, Side A (Idea to Pre-mortem) and Side B (Build,
  Post-mortem), plus the next step's sentence and **Copy prompt** (C10).
  - The copied prompt names the files involved and the next stage. With Orca detected (§2.7) it
    can also give the matching `orca orchestration …` command.
  - The old `ProjectGardenView` list stays reachable through a "List" toggle in the expanded
    header, so no existing Garden feature is lost (search, attention filter, detail sheet).

### 2.5 `BuildGate` (core)

```swift
public enum BuildGate {
    public enum Stage: CaseIterable { case idea, intent, spec, agents, premortem, build, postmortem }
    public enum Light: Equatable { case done, draft, skipped, notNeeded, missing, unknown(String) }
    public struct Result { public let lights: [Stage: Light]; public let slug: String? }
    public static func read(folder: URL, isNewApp: Bool) -> Result
}
```

- **The slug.** It comes from the newest `docs/PLAN-*.md` by modification date, falling back to
  the newest intent. With no plan, Build and Post-mortem are `missing`.
- **Idea.** `done` if `docs/idea/IDEA-*.md` exists. `notNeeded` when `isNewApp` is false, which
  means the project has a `.git` with more than one branch or any existing intent doc.
  **Pre-mortem target:** this heuristic.
- **Intent.** `done` if the plan's `**Intent:**` intent has `**Status:** approved…`. `draft` if
  that intent exists but isn't approved (C3).
- **Spec.** `done` if `docs/SPEC-<slug>.md` exists and its `**Intent:**` line names that intent
  (C4).
- **Agents.** `done` if `AGENTS.md` exists. It is `draft` if `CLAUDE.md` also exists but neither
  imports `@AGENTS.md` nor contains the string `AGENTS.md` (C5).
- **Pre-mortem.**
  - `done` if `docs/dialogue/<slug>.md` has a line matching
    `^## \w+ — pre-mortem — \d{4}-\d{2}-\d{2}` and a later `— settled —` line.
  - `skipped` if the plan header has a line containing "pre-mortem" and "skipped".
  - `draft` if there is a pre-mortem turn but no `settled` (C6).
- **Build.** `done` if the plan's `**Stage:**` line contains "built" or "post-mortem". Otherwise
  `missing`.
- **Post-mortem.** `done` if the dialogue file has a `— post-mortem —` turn (C7).
- **Unreadable.** Any read failure of the folder gives `unknown(reason)` for every stage that
  depended on it, and never `missing` (C2).
- **Bounds.** It lists only `docs/`, `docs/intent/`, `docs/idea/` and `docs/dialogue/`, at most
  200 entries in all. It reads 128 KB at most per file, and resolves no symlink that leaves the
  folder (C8). It never writes (C9).

### 2.6 Idea Clinic (core and app)

- **The tree.** `IdeaClinicTree.swift` is a hand-port of `app.js`'s `nodes` object at
  `CalmdownOscar@3a3a10d`: ids, kickers, titles, hints, quotes, options and `next` edges.
  - `IdeaClinicTree.sourceVersion = "3a3a10d"`.
  - A test hashes a canonical JSON of the tree against a checked-in constant. Changing a word
    therefore fails the test until the constant is bumped on purpose (D1).
- **The endings.** `IdeaClinic.prompt(for:answers:)` ports the three endings, decision brief,
  build check and launch plan, word for word.
- **The brief.** `IdeaClinic.brief(answers:)` gives `# IDEA — <idea>` followed by the read-back
  as `**Label:** answer` lines. It is pure (D3).
- **The app** (`IdeaClinicView`, a full-window pane `.ideaClinic` added to `Pane`):
  - one question per screen;
  - choices as large glass buttons, with keys 1–3 through `.keyboardShortcut`;
  - Back, a read-back screen and "Change my answers".
  - Output: Copy prompt, Copy brief, and "Save brief…", which uses `NSSavePanel` with the
    default name `IDEA-<slug>.md` (D4).
  - The draft is saved to `UserDefaults` under `unliRice.ideaClinicDraft` (D5). No network and
    no model (D6).
- **Entry points:** "Plant an idea" in the Garden header, and the seed sleeve "Plant your first
  idea" that an empty Garden shows (INTENT-009 answer 2).

### 2.7 Orca (optional, copy-only)

If `~/.orca` or the Orca app's bundle is present, it is detected through a security-scoped read
the user already granted, never by probing outside the sandbox. If not, nothing changes. When
present, the Copy prompt on a Pre-mortem or Build light also includes the
`orca orchestration worker-start …` line from `AGENTS.md`. **Pre-mortem target:** is this worth
its own step, or should it be dropped to a later plan?

### 2.8 Guardrails & Grounding tab

There are two decks, made only from existing data and existing destinations (see §2.2's
routing table):

- **Grounding.** Four bars: open notes, the mirror folder (its last export date), Claude Code
  memory files and Codex memory files. The last two are dashed and marked "Coming later", since
  they belong to INTENT-007 Phase B, which is not built.
- **Guardrails.** The active House Rules preset's name and its first three rule lines, plus three
  tiles: Need you, Safety checks (Trust Center's overall state) and Archived. A dashed row says
  "Did your AI follow the rules? Coming later", for Phase C.

## 3. Steps

Each `build` and `build-light` step goes to a builder with the full handoff (`AGENTS.md`
§ Builder contract). "Tests" means
`swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`. "App build" means
`swift build … --product UnliRiceApp` and then `xcodegen generate` plus the Xcode build (both run
on the Mac).

| Step | Label | What | Files | Spec ids | Verify |
|---|---|---|---|---|---|
| S1 | build | `BuildGate` and fixtures | `Sources/UnliRiceCore/BuildGate.swift` (new), `Tests/UnliRiceCoreTests/BuildGateTests.swift` (new), `Tests/UnliRiceCoreTests/Fixtures/BuildGate/…` (new) | C1–C9 | Tests |
| S2 | build | `GardenCrate`, plus the seed marker in `ProjectGarden.discover` | `Sources/UnliRiceCore/GardenCrate.swift` (new), `Sources/UnliRiceCore/ProjectGarden.swift`, `Tests/UnliRiceCoreTests/GardenCrateTests.swift` (new), `ProjectGardenTests.swift` | B1, B2 | Tests; the existing 23 Garden tests still pass |
| S3 | build | Idea Clinic tree, prompts and brief | `Sources/UnliRiceCore/IdeaClinic/IdeaClinicTree.swift`, `IdeaClinic.swift` (new), `Tests/UnliRiceCoreTests/IdeaClinicTests.swift` (new) | D1, D3, D5 (model only) | Tests |
| S4 | planner | Review S1–S3 together, then commit | — | — | Rerun the tests; read the diff |
| S5 | build | The navigation shell: new `Pane` cases, toolbar with glass tabs and gear menu, sidebar moved to `LegacySidebar.swift`, launch pane `.studio`, `Extra.projects` row removed | `AppStore.swift`, `ContentView.swift`, `Sources/UnliRice/Studio/StudioToolbar.swift` (new), `LegacySidebar.swift` (new), `Extras.swift`, `SetupView.swift` | A1, A4, A5, A9 | App build; route walk |
| S6 | build | The Studio tab: deck layout, expand and back, keys, top strip, Notes deck, Branches deck with `RepoSnapshotLoader` extracted from `RepoPaneView` | `Sources/UnliRice/Studio/StudioView.swift`, `NotesDeck.swift`, `BranchesDeck.swift`, `RepoSnapshotLoader.swift` (new), `RepoPaneView.swift` | A2, A3, A6–A8, B4–B7 | App build; walk |
| S7 | build | The Garden crate: compact and expanded views, sleeve back, Copy prompt, List toggle, Reduce Motion | `Sources/UnliRice/Studio/GardenCrateView.swift`, `SleeveBackView.swift` (new), `ProjectGardenView.swift` (List-toggle entry only) | B1–B3, C10, A10 | App build; walk with a 60-repo sample |
| S8 | build | The Guardrails & Grounding tab | `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` (new) | A1 | App build; walk |
| S9 | build | The Idea Clinic screens, save panel and draft persistence | `Sources/UnliRice/Studio/IdeaClinicView.swift` (new), `AppStore.swift` (`.ideaClinic` route) | D2, D4, D5 | App build; walk |
| S10 | planner | Review S5–S9 and run `xcodegen generate` plus the Xcode build on the Mac. Do the full QA walk (§4) in an isolated `.app` bundle against a throwaway vault, in light and dark mode, with Reduce Motion and Reduce Transparency on | — | A6, A7, A10 | §4 checklist |
| S11 | planner | Copy sync: the app's strings against `docs/USER_GUIDE.md`. The public guide on calmdownoscar.com needs its own CalmdownOscar change (active constraint in `memory.md`) | `docs/USER_GUIDE.md` | E4 | Review |
| S12 | planner | `PROJECT_NOTES.md` entry and `memory.md`, then ask Codex for the post-mortem | — | — | — |

S1, S2 and S3 don't touch each other's files, so Orca can run them in three worktrees in
parallel. S5 to S9 are sequential, because S5 changes the files the others build on.

## 4. By-hand walk (S10)

- [ ] The app launches into the Studio tab with three decks at 1440×900, and stacks at 960×600.
- [ ] Every row of §2.2's routing table opens its view.
- [ ] Flipping the crate works with the arrows, the keys, a swipe, a click on a sleeve behind
  and the dots. With Reduce Motion on, flips become fades.
- [ ] A sleeve's lights match a hand-built fixture repo: a draft intent shows draft, a dialogue
  without `settled` shows draft, and an unreadable folder shows grey.
- [ ] Copy prompt puts text on the clipboard (check with `pbpaste`) and changes no file (check
  with `git status`).
- [ ] The Idea Clinic runs end to end. Its brief, saved into a fixture repo's `docs/idea/`, turns
  that repo's Idea light green after Refresh.
- [ ] Glass shows on the tab bar and buttons. With Reduce Transparency on, the glass turns solid.
- [ ] Rate Unli Rice is reachable from the gear menu.

## 5. Risks and gotchas

- **The biggest change since four-jobs.** Existing users lose the sidebar they know. What's New
  must say where things went. That text is a release task, not part of this plan.
- **`AppStore` rebuilds `AgentSettings` on every launch** (PROJECT_NOTES 2026-10-29). No new
  setting goes in it. The clinic draft and the last-viewed crate position use `UserDefaults`.
- **Adding files under `Sources/` needs `xcodegen generate`.** `swift test` passes while Xcode
  fails (`memory.md`). Every app step reports its new files.
- **The App Store build is in review.** Nothing here merges to `main` until 1.4 has shipped or
  been rejected and fixed.
- **Glass stacked on glass looks muddy.** Only the toolbar and buttons get `.liquidGlass`. Decks
  stay `Theme` surfaces.

## 6. Open questions for the pre-mortem

1. Keep `LegacySidebar.swift` for one release, or delete the sidebar now?
2. Does the seed marker (`docs/idea/IDEA-*.md`) pick up folders it shouldn't?
3. Is the `isNewApp` heuristic for the Idea light good enough, or should Idea only ever be
   `done` or `notNeeded` by a marker in `AGENTS.md`?
4. Orca detection (§2.7): keep it, or move it to a later plan?
5. Is hand-porting the Idea Clinic tree from JavaScript to Swift, with a hash test, safer than
   shipping `app.js`'s data as a JSON resource that both the website and the app read?

## 7. Build on the Mac, by Codex (only after `settled`)

Codex works in two roles here, and they are kept apart:

- **The driver** is Codex on its best model. It sets up worktrees, hands steps over, runs the
  verification and pushes. It makes no design calls.
- **The builders** are `codex -p build` runs (or `build-light` where the step says so). Each one
  gets the handoff below, filled in from §3's row for its step.

For each step:

1. Create a worktree on a step branch cut from the tip of `claude/studio-redesign`:
   `codex/studio-<step>`, for example `codex/studio-S1`. S1, S2 and S3 may run at the same time,
   each in its own worktree (Orca: one workspace each). S5 to S9 run one at a time, each cut
   from the tip after Claude has merged the step before it.
2. Hand over the step:

   ```text
   Role: builder
   Intent: docs/intent/INTENT-009-studio-redesign.md
   Spec: docs/SPEC-studio-redesign.md (<spec ids from §3>)
   Plan: docs/PLAN-studio-redesign.md
   Step: <id and title from §3>
   Branch: codex/studio-<step>
   Files you may change: <files from §3>
   Changes already in the tree: none
   Verify with: swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build
                (app steps also: swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build --product UnliRiceApp)

   Follow AGENTS.md § "Builder contract".
   ```

3. **The driver checks before committing:**
   - the run's `model:` and `reasoning effort:` lines match the `AGENTS.md` table;
   - `git diff --stat` touches only the step's files;
   - the verify commands pass when the driver reruns them itself. The builder's pasted output
     is not evidence.
4. **The driver commits on the step branch and pushes it.** The message is
   `S<n>: <title> (unreviewed)`, followed by the test counts. It never merges into
   `claude/studio-redesign` or `main`.
5. **The driver writes `docs/BUILD-studio-redesign-S<n>-REPORT.md` on the same branch.** It
   records:
   - the files changed;
   - the commands run and their pass/fail counts;
   - the model lines;
   - anything a builder stopped on, with `file:line`.

   A builder that stops on an ambiguity ends the step. The driver does not guess: it pushes
   the report, and Claude decides.
6. **Claude reviews the pushed branch.** It either merges it into `claude/studio-redesign`, or
   leaves review notes in the report file for a retry. Builders keep their circuit breaker:
   two failed attempts, or one on data integrity or architecture, and the step stops.

S10 (the QA walk) needs eyes on the running app. The founder or Codex does it on the Mac, using
§4's checklist. Claude reviews the results. S11 and S12 are Claude's.
