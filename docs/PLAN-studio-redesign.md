# PLAN — Studio redesign: two tabs, a record-crate Garden, build-gate lights

**Intent:** `docs/intent/INTENT-009-studio-redesign.md` (approved 2026-10-30, amended after pre-mortem)
**Spec:** `docs/SPEC-studio-redesign.md` (ids A1–E4)
**Idea:** not needed — Unli Rice has existed since 2026-07; this is a redesign, not a new app
**Planner:** claude. **Reviewer:** codex.
**Stage:** 3 — settled 2026-10-30 after Codex's pre-mortem (`docs/dialogue/studio-redesign.md`,
14 findings, all accepted). The S1 and S2 stop reports were settled in §2.6 and §2.8 the same day.
Phase A's code is built: **S1, S2, S4, S5, S6 and S7 are merged** into `claude/studio-redesign`
(515 tests, 0 failed, 2 skipped; Xcode Debug build succeeded, verified by Claude at `35bd656`,
2026-10-30). S8 (the QA walk with the founder) is next. The stage number stays 3 until S8–S10
are done, because a number of 5 or more turns `BuildGate`'s Build light on (§2.6). Phase B (Idea Clinic) is blocked, see §6.
**Branch:** `claude/studio-redesign`, cut from `main` at `8d2189c` (1.4 (9), in App Review).
**Who builds (founder, 2026-10-30):** "I am tired of copy pasting." Claude Code on the Mac is now
**planner and build driver** together, per `docs/BUILD-studio-redesign-HANDOFF.md`; Codex is used
only as the CLI builder for one step at a time (`codex -p build`), and later as the post-mortem
reviewer — never as a relay between the founder and either tool.
**Verified against:** `946e28b` (the S5 merge commit). Earlier sections were checked against
`0bb4582` when no Swift toolchain was available; `file:line` citations from S6 onward are
re-checked against the tip in use at the time, per §7/the handoff's loop, step 1.
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

### 2.3a S4 exact changes (settled before handoff, 2026-10-30)

**`AppStore.swift`:**
- `Pane` gains `case studio, guardrailsGrounding`.
- Add `@Published var lastTab: Pane = .studio`.
- Add `func showStudio() { selectNote(nil); pane = .studio; lastTab = .studio }`.
- Add `func showGuardrailsGrounding() { selectNote(nil); pane = .guardrailsGrounding; lastTab = .guardrailsGrounding }`.
- **Launch** (`:679-684`): the `else` branch sets `pane = .studio`, where it was `.home`.
  `.firstRun` is unchanged.
- **Switching notes folders** (`:943-947`): the `case .retrospective, .projects, .repos,
  .notices, .trustCenter:` branch sets `pane = .studio`, where it was `.notes`.
- No other `pane =` line changes.

**`ContentView.swift`:**
- In `body`, replace `HStack(spacing: 0) { sidebar; Divider().opacity(0.3); mainColumn }` with
  `VStack(spacing: 0) { StudioToolbar(); Divider().opacity(0.3); mainColumn }`.
- Delete `sidebar`, `sidebarRows`, `sidebarCapture`, `sidebarHeading` and `sidebarRow`
  (`:108-268`).
- In `mainColumn`, add `case .studio: StudioView()` and
  `case .guardrailsGrounding: GuardrailsGroundingView()`.
- `CapturePromoCard` stays in its file, unused. It is not deleted in this step.

**`AutomationView.swift:160`:** iterate `Extra.allCases.filter { $0 != .projects }`.
`Extras.swift` is unchanged.

**`Studio/StudioToolbar.swift`** (new):
- `struct StudioToolbar: View`, holding `@EnvironmentObject var store: AppStore` and
  `@State private var showingCapture = false`.
- Layout: `HStack { Spacer(); tabs; Spacer(); gear }`, height 52, horizontal padding 16,
  background `Theme.bgMain`.
- **Tabs:** two `Button`s, "Studio" and "Guardrails & Grounding", in an `HStack(spacing: 4)`
  with 4 pt padding and `.liquidGlassCapsule()`.
  - Their actions are `store.showStudio()` and `store.showGuardrailsGrounding()`.
  - The selected tab is the one equal to `store.lastTab`. It gets a
    `Capsule().fill(Theme.accentSoft)` background, `Theme.textPrimary` text and
    `.accessibilityAddTraits(.isSelected)`. The other uses `Theme.textSecondary`.
  - Font: `.system(size: 13, weight: .semibold)`. Padding: 16 horizontal, 7 vertical. Style:
    `.buttonStyle(.plain)`.
  - Shortcuts: `.keyboardShortcut("1", modifiers: .command)` and `"2"`.
- **Gear:** `Menu`, in this order:
  - "Setup" calls `store.selectNote(nil); store.showSetup()`.
  - "Trust Center" calls `store.showTrustCenter()`.
  - "Archived notes" calls `store.showArchived()`.
  - A `Divider()`.
  - "To do" calls `store.showTodo()`, "Map" calls `store.showGraph()` and "Your year so far"
    calls `store.showRetrospective()`. Each appears only when `store.isOn(.todo)`, `.map` or
    `.yearSoFar` is true.
  - "iPhone Capture" sets `showingCapture = true`, and appears only when
    `store.isOn(.capturePromo)` is true.
  - A `Divider()`.
  - "Rate Unli Rice" calls `NSWorkspace.shared.open(AppStore.writeReviewURL)`.
  - Label: `Image(systemName: "gearshape")`, style `.menuStyle(.borderlessButton)`,
    `.menuIndicator(.hidden)`, frame 44×44 and `.liquidGlassCapsule(interactive: true)`, with
    `.accessibilityLabel("Settings and more")`.
- `.sheet(isPresented: $showingCapture) { CapturePromoSheet().environmentObject(store) }`.

**`Studio/StudioView.swift` and `Studio/GuardrailsGroundingView.swift`** (new placeholders):
`struct StudioView: View { var body: some View { Text("Studio") } }`, and the same for the
other, with the text "Guardrails & Grounding".

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

### 2.4a S5 exact changes (settled before handoff, 2026-10-30)

This changes one thing in §2.4: **`RepoSnapshotLoader` is not extracted**, and `RepoPaneView`
is not touched. The Branches deck reads the published ancestry itself, in the few lines given
below. Changing `RepoPaneView` would add risk for no visible gain.

**`AppStore.swift`.** Add three stored properties next to `lastTab`:
- `@Published var studioSleeves: [GardenCrate.Sleeve] = []`
- `@Published var studioFrontIndex: Int = 0`
- `@Published var studioGardenState: StudioGardenState = .loading`

Nothing else in this file changes.

**`AppStore+Studio.swift`** (new):
- `enum StudioGardenState: Equatable { case loading, loaded, failed(String) }`
- `extension AppStore`:
  - `var studioFrontSleeve: GardenCrate.Sleeve?`: the sleeve at `studioFrontIndex` when it is in
    range, otherwise nil.
  - `func refreshStudioGarden() async`:
    - Set `studioGardenState = .loading`, then run **the same detached worker body as
      `ProjectGardenView.load()` (`ProjectGardenView.swift:249-264`)**. That means: open the
      corpus folder and the scan roots with security scope, list notes, read the optional
      published snapshot, and call `ProjectGarden.load`.
    - On success: `studioSleeves = GardenCrate.sleeves(from: report)`, and
      `studioFrontIndex = min(studioFrontIndex, max(studioSleeves.count - 1, 0))`, then
      `studioGardenState = .loaded`.
    - On an error other than cancellation: `.failed(error.localizedDescription)`.
  - `@Published` can't go in an extension, so the gate result goes in a fourth stored property
    in `AppStore.swift`: `@Published var studioFrontGate: BuildGate.Result? = nil`.
  - `func refreshStudioGate() async`:
    - Run `BuildGate.current(folder:)` for `studioFrontSleeve?.folderURL` in
      `Task.detached`, with every scan root opened by security scope (the same open/close pair as
      above). Assign the result.
    - Nil when there is no folder.

**`Studio/StudioColor.swift`** (new): `extension Color { init(studio token:
StudioPalette.Token, scheme: ColorScheme) }`. It parses `StudioPalette.hex(token, scheme == .dark
? .dark : .light)` as sRGB.

**`Studio/BuildGateLights.swift`** (new): `struct BuildGateLights: View { let result:
BuildGate.Result?; var showsLabels: Bool }`. It shows the seven stages in `Stage.allCases` order.

| Light | SF Symbol | Palette token | Spoken word |
|---|---|---|---|
| `done` | `circle.fill` | `lightDone` | "done" |
| `draft(r)` | `circle` | `lightDraft` | r |
| `missing`, `notRecorded` | `circle.dotted` | `lightMissing` | "missing", "not recorded" |
| `skipped(q)` | `slash.circle` | `lightMissing` | "skipped: q" |
| `notRequired(r)` | `minus` | `lightMissing` | "not needed: r" |
| `unknown(r)` | `questionmark.circle.fill` | `lightUnknown` | r |

- A nil result shows all seven as `unknown("not read yet")`.
- Each symbol is 12 pt. Its `.accessibilityLabel` is `"<Stage title>: <word>"`. The stage
  titles are Idea, Intent, Spec, Agents, Pre-mortem, Build and Post-mortem.
- With `showsLabels`, each symbol has its stage title under it in 10 pt `textSecondary`.
- Add `static func nextStep(_ result: BuildGate.Result?) -> String`. It returns
  `"Next: <Stage title>"` for the first stage whose light is not `done`, `notRequired` or
  `skipped`, and "All seven lights are in" when there is none.

**`Studio/StudioDeck.swift`** (new): `struct StudioDeck<Content: View>: View`, with fields
`title: String`, `accent: StudioPalette.Token`, `shortcut: KeyEquivalent`, `expand: () -> Void`
and `@ViewBuilder content`.
- Background: a `RoundedRectangle(cornerRadius: 24, style: .continuous)` filled with `surface`.
  Padding 20.
- Header: the title in uppercase, 13 pt bold, `.tracking(1.5)`, in the accent colour. Beside it
  a `Button(action: expand)` with the symbol `arrow.up.left.and.arrow.down.right`,
  `.accessibilityLabel("Open \(title)")`, `.keyboardShortcut(shortcut, modifiers: [])` and
  `.liquidGlassCapsule(interactive: true)`.

**`Studio/StudioView.swift`** (replaces the placeholder):
- **Top strip** (when `studioFrontSleeve` exists): the sleeve's name (17 pt semibold),
  `BuildGateLights(result: store.studioFrontGate, showsLabels: true)`,
  `BuildGateLights.nextStep(…)` and the caption "Lights show which files exist in this repo."
  (11 pt `textSecondary`).
- **Decks** in a `GeometryReader`:
  - At a width of 1080 or more: `HStack(spacing: 20)` of three equal decks.
  - Below that: `VStack(spacing: 20) { garden; HStack(spacing: 20) { branches; notes } }`.
  - Padding 24, inside a `ScrollView(.vertical)`, so nothing clips at 960×600 (A7).
- **The three decks:**
  - Garden: `GardenCrateView(compact: true)`, accent `garden`, shortcut "1", expand
    `store.showGarden()`.
  - Branches: `BranchesDeck()`, accent `branches`, shortcut "2", expand `store.showRepos()`.
  - Notes: `NotesDeck()`, accent `notes`, shortcut "3", expand `store.showAllNotes()`.
- **Loading:**
  - `.task(id: StudioLoadKey(dataPath: store.dataURL.path, roots: store.scanRoots.map(\.path),
    noteCount: store.notes.count)) { await store.refreshStudioGarden() }`, where `StudioLoadKey`
    is a private `Equatable` struct in this file.
  - `.task(id: store.studioFrontSleeve?.id) { await store.refreshStudioGate() }`.

**Layout correction (settled after the S5 driver's finding, 2026-10-30).**
- The `GeometryReader` is the outermost container below the top strip, and it only reads the
  width. Inside it goes `ScrollView(.vertical) { deckLayout(width:).padding(24) }`.
- Rows use `alignment: .top`, and each deck has `.frame(maxWidth: .infinity, alignment: .top)`.
- No container gets a fixed or computed height. The only fixed heights are the 320-pt graph and
  the 180-pt ring.

**`Studio/GardenCrateView.swift`** (new, a placeholder until S6): `struct GardenCrateView: View {
let compact: Bool }`. Its body shows the number of sleeves ("N projects") and
`store.studioFrontSleeve?.name`. It also handles two states: `.failed(m)` shows m, and an empty
`.loaded` shows "Plant your first idea" with a `Link` to
`https://www.calmdownoscar.com/idea-clinic/`.

**`Studio/BranchesDeck.swift`** (new):
- With no front sleeve, or a sleeve with no `folderURL`: the sentence "Pick a folder with a
  project in it" and a `Button("Pick a folder") { store.chooseScanRoot() }`.
- Otherwise, use `.task(id: folderURL)`, detached, with every scan root opened by security
  scope:
  - `snapshot = try? GitRepoScanner().scan(repositoryAt: folderURL)`.
  - The ancestry file, read with the corpus folder (`store.dataURL.deletingLastPathComponent()`)
    opened by security scope: `try? RepoSnapshotFile.read(fromFolder:)`.
- With no snapshot: "No git repository in <name>".
- Otherwise: a header "<snapshot.branches.count> branches" (headline, 28 pt bold), then
  `BranchGraphView(snapshot:, ancestry: file?.repos.first { $0.name == snapshot.name },
  ancestryAge: file?.generatedAt, ancestryStale: file?.isStale() ?? false)`, at a fixed height
  of 320 inside a `ScrollView`.

**`Studio/NotesDeck.swift`** (new):
- If `store.errorMessage` is set: "Can't read your notes" plus the message, and no number (B7).
- Otherwise:
  - `open = store.notes.filter { !$0.archived }`.
  - **Ring:** 180 pt, made of `Circle().trim` segments. The counts per bucket are by
    `note.creator`, lowercased: `claude`, `codex`, `human`, `ingest`, and everything else is
    "other". The colours are the `notes` colour at opacity 1.0, 0.7, 0.45, 0.28 and 0.15, in
    that order. A text legend beside the ring gives each bucket's name and count.
  - **Headline:** `open.count`, 34 pt bold, centred in the ring.
  - **List header:** "<pending.count + unreadNoticeCount> need you · newest by <creator of the
    newest open note>".
  - **List:** the five newest open notes by `updatedAt`, as plain `Button`s with the title on
    one line, calling `store.selectNote(note.id)`.

**`Studio/StudioToolbar.swift`:**
- Add a leading back button, visible when `store.pane` is not `.studio`,
  `.guardrailsGrounding` or `.firstRun`, and `store.selectedNoteID == nil`. It reads
  `Label("All decks", systemImage: "chevron.left")`.
- Its action: `store.lastTab == .studio ? store.showStudio() : store.showGuardrailsGrounding()`.
- It takes `.keyboardShortcut(.cancelAction)` and `.liquidGlassCapsule(interactive: true)`.
- Layout: `HStack { back-or-Spacer; Spacer(); tabs; Spacer(); gear }`. The back slot keeps a
  fixed width of 110 pt, so the tabs stay centred.

### 2.5 The Garden crate (core: `GardenCrate`)

```swift
public enum GardenCrate {
    public enum State: Equatable, Sendable {
        case fine, needsYou, noStatus, cantRead(String)
    }
    public struct Sleeve: Identifiable, Equatable, Sendable {
        public let id: String          // Project.id
        public let name: String
        public let subtitle: String    // nextStep ?? status ?? "No notes yet"; first line only; over 60 chars → first 59 + "…"
        public let state: State
        public let lastActivity: Date?
        public let folderURL: URL?
        public let coverIndex: Int     // 0..<8, stable hash of id
    }
    public static func state(of project: ProjectGarden.Project) -> State
    public static func sleeves(from report: ProjectGarden.Report) -> [Sleeve]
    public static func stableIndex(_ id: String, modulo: Int) -> Int   // 32-bit FNV-1a over UTF-8 (basis 2166136261, prime 16777619), then % modulo
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

### 2.5a S6 exact changes (settled before handoff, 2026-10-30)

Checked against `946e28b`. **No frame, padding, spacing, minimum or maximum size, and no colour,
other than the ones written here.** S5's builder added `minHeight`s that no section asked for,
and those caused two of its stops.

**Shared names used below.**
- `reduceMotion` is `@Environment(\.accessibilityReduceMotion) private var reduceMotion`.
- `colorScheme` is `@Environment(\.colorScheme) private var colorScheme`.
- `C(token)` is short for `Color(studio: token, scheme: colorScheme)` (`StudioColor.swift`).
- `flip` is the animation `reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45,
  dampingFraction: 0.78)`.

**`Studio/BuildGateLights.swift`** (refactor only; its drawing doesn't change). The sleeve back
reuses its helpers:
- `title(for:)` (`:42`) stays `static` and loses `private`. Delete the instance wrapper at `:54`.
  Call sites inside the struct use `Self.title(for:)`.
- `symbol(for:)` (`:56`), `token(for:)` (`:67`) and `spoken(for:)` (`:76`) become `static func`,
  with no `private`. Call sites inside the struct use `Self.`.
- Add `static func nextStage(_ result: BuildGate.Result?) -> BuildGate.Stage?`. It returns the
  first stage in `Stage.allCases` whose light (nil result: `.unknown("not read yet")`) is not
  `.done`, `.notRequired` or `.skipped`, and nil when there is none.
- `nextStep(_:)` (`:31`) becomes `nextStage(result).map { "Next: \(title(for: $0))" } ?? "All
  seven lights are in"`. Its output doesn't change.

**`Studio/GardenCrateView.swift`** (replaces S5's placeholder; `struct GardenCrateView: View {
let compact: Bool }` keeps that signature, so `StudioView.swift` is unchanged).
- `side` (the sleeve's width and height) is `compact ? 200 : 340`. `peek` is `78` (3 × 26).
- **States.** `store.studioGardenState`:
  - `.loading`: `ProgressView("Reading your garden…")`, as now.
  - `.failed(m)`: `Text(m)` in `Theme.textSecondary`, as now.
  - `.loaded` with no sleeves: the empty state below.
  - `.loaded` with sleeves: `VStack(alignment: .leading, spacing: 12) { headline; crate;
    controls }`.
- **Headline:** `"\(store.studioSleeves.count) projects"`, 28 pt bold, `Theme.textPrimary`. Shown
  only when `compact`. The expanded header names the Garden itself.
- **Crate:** `ZStack(alignment: .bottom)`, frame `width: side, height: side + peek`. It draws
  the sleeves at indices `max(front - 1, 0) ... min(front + 3, count - 1)`, where `front` is
  `store.studioFrontIndex`, in a `ForEach` keyed by `sleeve.id`. For index `i`, `d = i - front`:
  - `d == -1` (the flipped sleeve): `.rotation3DEffect(.degrees(-84), axis: (x: 1, y: 0, z: 0),
    anchor: .bottom, perspective: 0.5)`, `.opacity(0)`, `.zIndex(1)`, and hit testing off. It
    isn't drawn at all when `reduceMotion` is on.
  - `d == 0` (the front): no transform, `.zIndex(0)`.
  - `d` of 1 to 3 (behind): `.scaleEffect(1 - 0.06 * Double(d))`, then `.offset(y: -26 *
    CGFloat(d))`, then `.zIndex(-Double(d))`. `.onTapGesture { select(i) }` and
    `.accessibilityAddTraits(.isButton)`.
  - The whole crate takes `.gesture(DragGesture(minimumDistance: 40).onEnded { v in … })`. When
    `abs(v.translation.width) > abs(v.translation.height)`, it calls `move(by:)` with `1` for a
    negative width and `-1` for a positive one; otherwise it does nothing.
  - With `reduceMotion` on, the crate gets `.id(store.studioFrontIndex)` and
    `.transition(.opacity)`, so a flip is a fade and nothing moves. With it off, it gets neither.
- **One sleeve** (`private struct SleeveFront: View { let sleeve: GardenCrate.Sleeve; let side:
  CGFloat }`):
  - `RoundedRectangle(cornerRadius: 10, style: .continuous)` filled with `C(cover)`, where
    `cover` is `[.cover0, .cover1, .cover2, .cover3, .cover4, .cover5, .cover6,
    .cover7][sleeve.coverIndex]`. Frame `side` × `side`.
  - `.shadow(color: .black.opacity(0.25), radius: 8, y: 4)`.
  - Overlaid, `VStack(alignment: .leading, spacing: 6)` with 16 pt padding:
    - the sticker, top-trailing (see below), then `Spacer(minLength: 0)`;
    - the name: `side > 200 ? 24 : 17` pt semibold, `C(.coverText)`, `.lineLimit(2)`,
      `.truncationMode(.tail)`;
    - the subtitle: `side > 200 ? 14 : 12` pt, `C(.coverSubtext)`, `.lineLimit(2)`.
  - `.help(sleeve.name)`. `.accessibilityElement(children: .ignore)` with
    `.accessibilityLabel("\(sleeve.name), \(GardenCrateView.sticker(for: sleeve.state))")`.
- **Sticker:** `static func sticker(for state: GardenCrate.State) -> String`: `.fine` "FINE",
  `.needsYou` "NEEDS YOU", `.noStatus` "NO NOTES YET", `.cantRead` "CAN'T READ". Drawn as
  `Text`, 10 pt bold, `.tracking(1)`, with 8 pt horizontal and 4 pt vertical padding, on a
  `Capsule()` fill:

  | State | Fill | Text |
  |---|---|---|
  | `.fine` | `stickerFineFill` | `stickerDarkText` |
  | `.needsYou` | `stickerNeedsYouFill` | `stickerDarkText` |
  | `.noStatus` | `stickerNoStatusFill` | `stickerDarkText` |
  | `.cantRead` | `stickerCantReadFill` | `stickerLightText` |

  `.cantRead(reason)` also adds `.help(reason)` to the sticker.
- **Controls:** `HStack(spacing: 12) { previous; indicator; next }`.
  - Previous: `Button { move(by: -1) } label: { Image(systemName: "chevron.left") }`,
    `.keyboardShortcut(.leftArrow, modifiers: [])`, `.accessibilityLabel("Previous project")`,
    `.disabled(front == 0)`, `.liquidGlassCapsule(interactive: true)`.
  - Next: the same with `chevron.right`, `.rightArrow`, "Next project", and `.disabled(front ==
    count - 1)`.
  - Indicator, at 20 sleeves or fewer: `HStack(spacing: 6)` of 6 × 6 `Circle()`s, the front one
    in `Theme.textPrimary` and the others in `Theme.textSecondary.opacity(0.35)`. Above 20:
    `Text("\(front + 1) of \(count)")`, 11 pt, `Theme.textSecondary`. Either way, the indicator
    is one accessibility element labelled `"\(front + 1) of \(count)"`.
  - The arrow shortcuts exist only while this view is on screen, because they belong to these
    buttons. Nothing else registers ← or →.
- **Moving:**
  - `private func move(by delta: Int) { select(store.studioFrontIndex + delta) }`.
  - `private func select(_ index: Int) { let target = min(max(index, 0), store.studioSleeves.count
    - 1); guard target != store.studioFrontIndex else { return }; withAnimation(flip) {
    store.studioFrontIndex = target } }`.
- **Empty state** (`.loaded` with no sleeves): a sleeve-sized
  `RoundedRectangle(cornerRadius: 10, style: .continuous)`, stroked with
  `Theme.textSecondary.opacity(0.4)` and `StrokeStyle(lineWidth: 1.5, dash: [6, 4])`, frame `side`
  × `side`. Centred inside it is the existing `Link` to
  `https://www.calmdownoscar.com/idea-clinic/`, labelled `Label("Plant your first idea",
  systemImage: "plus.circle")`, 16 pt semibold. Beside it is `Button("Pick a folder") {
  store.chooseScanRoot() }` (`AppStore+Ingest.swift:103`). "Beside" means `HStack(spacing: 16)`
  when not compact, and `VStack(alignment: .leading, spacing: 12)` when compact, because a
  compact deck is too narrow for both.
- The view keeps `.frame(maxWidth: .infinity, alignment: .topLeading)` and nothing else.

**`Studio/SleeveBackView.swift`** (new): `struct SleeveBackView: View { let sleeve:
GardenCrate.Sleeve; let result: BuildGate.Result? }`, with `@State private var copied = false`.
- `VStack(alignment: .leading, spacing: 14)`, in this order:
  1. The name, 20 pt semibold, `Theme.textPrimary`. The subtitle, 12 pt, `Theme.textSecondary`.
     When `result?.slug` is set: `Text("Feature: \(slug)")`, 11 pt monospaced,
     `Theme.textSecondary`.
  2. **No folder** (`sleeve.folderURL == nil`): `Text("This project has no folder, so it has no
     lights.")`, 13 pt, `Theme.textSecondary`. Nothing below it is drawn.
  3. **Side A:** the label "SIDE A", 11 pt bold, `.tracking(1.5)`, `Theme.textSecondary`. Then a
     row for each of Idea, Intent, Spec, Agents and Pre-mortem, numbered A1 to A5.
  4. **Side B:** "SIDE B" the same way, then rows for Build (B1) and Post-mortem (B2).
  5. **Issues:** each of `result?.issues ?? []`, 11 pt, `Theme.textSecondary`.
  6. **Next step:** `BuildGateLights.nextStep(result)`, 15 pt semibold, `Theme.textPrimary`.
  7. **Copy prompt**, only when `SleeveBackView.prompt(sleeve:result:)` is non-nil:
     `Button { … } label: { Label(copied ? "Copied" : "Copy prompt", systemImage: copied ?
     "checkmark" : "doc.on.doc") }`, `.liquidGlassCapsule(interactive: true)`. Its action is
     `NSPasteboard.general.clearContents()`, then
     `NSPasteboard.general.setString(prompt, forType: .string)`, then `copied = true`, and
     `copied = false` again after 2 seconds (`DispatchQueue.main.asyncAfter`). It writes no file
     (C10).
  8. The caption "Lights show which files exist in this repo.", 11 pt, `Theme.textSecondary`.
- **A track row:** `HStack(spacing: 10)`:
  - the number ("A1"), 11 pt monospaced, `Theme.textSecondary`, frame width 24, leading;
  - `Image(systemName: BuildGateLights.symbol(for: light))`, 12 pt, in
    `C(BuildGateLights.token(for: light))`;
  - the stage title (`BuildGateLights.title(for:)`), 13 pt, `Theme.textPrimary`;
  - `Spacer()`;
  - `BuildGateLights.spoken(for: light)`, 12 pt, `Theme.textSecondary`, `.lineLimit(1)`.

  `light` is `result?.lights[stage] ?? .unknown("not read yet")`. Each row is
  `.accessibilityElement(children: .ignore)` with `.accessibilityLabel("\(title): \(word)")`.
- **The prompt:** `static func prompt(sleeve: GardenCrate.Sleeve, result: BuildGate.Result?) ->
  String?`. It returns nil when `sleeve.folderURL` is nil, when `result` is nil, or when
  `BuildGateLights.nextStage(result)` is nil. Otherwise it returns these lines joined with `"\n"`:
  - `Project: <sleeve.name>, in <folderURL.path>.`
  - With `result.slug == nil`: `This project has no docs/PLAN-*.md yet. Write the intent file for
    the next feature in docs/intent/, following AGENTS.md § "The order, for every app". Ask me
    what the feature is before you write anything.` The prompt ends here.
  - With a slug: `Feature: <slug> (plan: docs/PLAN-<slug>.md).`
  - `Next stage: <title>. Right now: <spoken word for that stage's light>.`
  - The stage's line:

    | Stage | Line |
    |---|---|
    | Idea | `Write docs/idea/IDEA-<slug>.md. If this feature needs no idea brief, add the line "**Idea:** not needed — <reason>" to the plan's header instead.` |
    | Intent | `Finish the intent file named on the plan's **Intent:** line. Its **Status:** line says approved only after I approve it.` |
    | Spec | `Finish the spec file named on the plan's **Spec:** line. Its **Intent:** line must name the same intent file, and its **Status:** line says approved only after I approve it.` |
    | Agents | `Make AGENTS.md at the repo root current for this work. If there is a CLAUDE.md, it needs a line that is exactly @AGENTS.md.` |
    | Pre-mortem | `Get the reviewer's pre-mortem of the plan into docs/dialogue/<slug>.md, answer it, and add the planner's settled turn after it.` |
    | Build | `Build the plan's steps. When they are built, set the plan's **Stage:** line to 5.` |
    | Post-mortem | `Get the reviewer's post-mortem turn into docs/dialogue/<slug>.md, after the planner's settled turn.` |

  - `Follow AGENTS.md.`

**`Studio/GardenExpandedView.swift`** (new): `struct GardenExpandedView: View`, with
`@EnvironmentObject var store: AppStore` and `@State private var showsList = false`.
- `VStack(alignment: .leading, spacing: 16)` with 24 pt padding, on `C(.background)`:
  - **Header:** `HStack(spacing: 12)`:
    - `Text("Garden")`, 22 pt bold, `Theme.textPrimary`;
    - `Spacer()`;
    - `Button { Task { await store.refreshStudioGarden() } } label: { Label("Refresh",
      systemImage: "arrow.clockwise") }`, `.liquidGlassCapsule(interactive: true)`;
    - `Picker("View", selection: $showsList) { Text("Crate").tag(false); Text("List").tag(true)
      }`, `.pickerStyle(.segmented)`, `.labelsHidden()`, `.frame(width: 160)`.
  - **Body:**
    - `showsList`: the existing `ProjectGardenView()`, unchanged.
    - Otherwise: `HStack(alignment: .top, spacing: 32) { GardenCrateView(compact: false); back
      }`. `back` is `ScrollView(.vertical) { SleeveBackView(sleeve: front, result:
      store.studioFrontGate) }` with `.frame(maxWidth: .infinity, alignment: .topLeading)`, and
      it is shown only when `store.studioFrontSleeve` (`front`) exists.
- **Loading:**
  - `.task { if store.studioGardenState == .loading { await store.refreshStudioGarden() } }`.
    This is needed because `StudioView`'s task is cancelled when the Studio tab disappears, and
    `refreshStudioGarden()` (`AppStore+Studio.swift:16`) returns without changing state when it
    is cancelled. Arriving mid-load would otherwise leave the spinner up for good.
  - `.task(id: store.studioFrontSleeve?.id) { await store.refreshStudioGate() }`, the same as
    `StudioView.swift:25`, because the expanded crate moves the front sleeve too.

**`ContentView.swift`** (that one case only, `:121-122`): `case .projects, .repos:
ProjectsPane()` becomes `case .projects: GardenExpandedView()` and `case .repos: ProjectsPane()`.
`ProjectsPane` (`:282`) is unchanged. Its "Overview" segment calls `store.showGarden()`, which now
leads to the expanded Garden.

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
        case notRecorded            // nothing names evidence for this stage (see below)
        case missing                // folder read fine, file absent
        case unknown(String)        // could not read / too large / ambiguous
    }
    public struct Result: Equatable, Sendable {
        public let slug: String?
        public let openPlans: [String]   // slugs of plans not yet built, sorted
        public let lights: [Stage: Light]   // always holds all seven stages
        public let issues: [String]          // non-fatal notes, in the order found; shown under the tracklist
    }
    public static func read(folder: URL, slug: String) -> Result
    public static func current(folder: URL) -> Result
}
```

**Picking the feature (`current`).**
- List `docs/` at depth 1 only, with at most 500 entries. Over 500 gives every light
  `unknown("too many files in docs/")`.
- Collect the `PLAN-<slug>.md` files. **Stage number:** the integer immediately after
  `**Stage:** ` on the plan's first `**Stage:**` line (regex `^\*\*Stage:\*\* (\d+)`).
  A plan is **open** when that number is 4 or lower. A plan with no number is an older plan and
  is never open.
- Exactly one open plan → that slug. Several → the one with the newest modification date. The
  others are listed in `openPlans` and on the sleeve back.
- **Modification dates only choose which feature to show.** They never decide which files count
  as evidence.
- No plans: `slug = nil`. Agents is still read, and every other light is `notRecorded`.
- **`notRecorded` means nothing names evidence for this stage.** It is used in exactly two
  cases: Idea when the plan has no `IDEA-<slug>.md` and no `**Idea:**` line, and every stage
  except Agents when the folder has no plan at all. It is drawn as a dashed grey ring with the
  word "Not recorded". (Settled 2026-10-30 after the S1 stop report.)

**Reading one feature (`read`).** Every path comes from the plan, never from a search:

| Stage | Evidence (paths are relative to the repo root) | Light |
|---|---|---|
| Intent | The path on the plan's `**Intent:**` line | `done` if that file's `**Status:**` starts with "approved"; `draft("not approved yet")` if it exists otherwise; `missing` if absent, or if the plan has no Intent line |
| Spec | The path on the plan's `**Spec:**` line | No Spec line: `notRequired("older plan")`, so legacy plans are not shown as failures. Otherwise `done` if `**Status:**` starts with "approved" **and** its `**Intent:**` line names the same intent path; a different intent gives `unknown("spec names a different intent")`; any other status gives `draft(<status>)`; a file that isn't there gives `missing` |
| Agents | `AGENTS.md` and `CLAUDE.md` at the root | `missing` if there is no `AGENTS.md`. With a `CLAUDE.md` that has no line equal to `@AGENTS.md` (after trimming), `draft("CLAUDE.md doesn't import AGENTS.md")`. Otherwise `done` |
| Idea | `docs/idea/IDEA-<slug>.md`, and the plan's `**Idea:**` line | `done` if the file exists; `notRequired(reason)` for "not needed — reason"; `skipped(quote)` for "skipped — quote"; otherwise `notRecorded` |
| Pre-mortem | `docs/dialogue/<slug>.md`, and the plan's `**Pre-mortem:**` line | See below |
| Build | The plan's stage number | `done` if 5 or higher (5 = built, 6 = post-mortem). 4 or lower gives `missing`. No number gives `unknown("plan stage has no number")` |
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
- A turn whose author is neither header tool is ignored and appends
  `"dialogue turn by <author> on line <n> ignored: not the planner or reviewer"` to
  `Result.issues`.
- **Other things appended to `issues`:** extra open plans, as
  `"<n> other open plans: <slugs>"`, and a `CLAUDE.md` without an `@AGENTS.md` line, as the
  draft reason. Issues never change a light; they only explain it.

**Reading header lines** (settled 2026-10-30 after the S1c stop report). These rules apply to
every `**Name:**` line the gate reads: in plans, intents, specs and dialogue files.

- **Finding the line.** Use the first line among the file's first 40 that starts exactly with
  `**Name:**`. Its value is the rest of that line, trimmed. Continuation lines are ignored.
- **Pulling out a path.** Take the first match of `docs/[A-Za-z0-9._/-]+\.md` in the value.
  This works with or without backticks and ignores any text around the path. For example,
  `` `docs/intent/INTENT-009-studio-redesign.md` (approved …) `` gives
  `docs/intent/INTENT-009-studio-redesign.md`. Paths resolve against the repo root, and two
  paths are compared as these extracted strings.
- **An Intent or Spec line with no path:**
  - If the lowercased value starts with `none` or `no `, the light is
    `notRequired(<value, first 80 chars>)`. Older plans say "none. This comes from …".
  - Otherwise the light is `unknown("no path on the <Name> line")`.
  - A missing `**Spec:**` line is still `notRequired("older plan")`.
- **Status.** The lowercased value starts with `approved`.
- **Planner and Reviewer.** The value's first word, lowercased, with trailing punctuation
  removed.
- **Code fences.** A line whose trimmed text starts with three backticks toggles "inside a
  fence". Turn headings and header lines inside a fence are ignored.

**"After" means later in the file** (settled 2026-10-30 after the S1b stop report). Turns are
ordered by their line number in the dialogue file. Dates are display text and never decide
order, because several turns often share one date. A reviewer rebuttal on a later line than the
planner's settled turn therefore makes the Pre-mortem light `draft`, even on the same day. A
post-mortem on a later line than the settled turn counts, even on the same day.

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

### 2.7a S7 exact changes (settled before handoff, 2026-10-30)

Checked against `e3d781c`. The layout follows the mockup's `GuardrailsGrounding` artboard, with
two changes. Both memory-file bars are "coming later", because §2.7 says so and the mockup's
sample "15" was invented. Every colour comes from `StudioPalette`, where the mockup used tints
that aren't in it. **No frame, padding, spacing, size or colour other than the ones written
here.** One file changes: `Studio/GuardrailsGroundingView.swift` replaces S4's placeholder. It
reads only what `AppStore` already publishes, and adds nothing to `AppStore`.

**Names.** `colorScheme` and `C(token)` are as in §2.5a.

**`struct GuardrailsGroundingView: View`**, with `@EnvironmentObject var store: AppStore` and
`@State private var mirrorWritten: Date?`.
- Body: `ScrollView(.vertical) { HStack(alignment: .top, spacing: 20) { grounding; guardrails }
  .padding(24) }`. Each deck has `.frame(maxWidth: .infinity, alignment: .top)`. The window is
  at least 960 pt wide, so the two decks always sit side by side.
- **A deck** (`private struct TabDeck<Content: View>: View`, with `title`, `subtitle`, `accent:
  StudioPalette.Token` and `@ViewBuilder content`): `VStack(alignment: .leading, spacing: 16) {
  header; content }`, padding 20, `.background(C(.surface))`,
  `.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))`. The header is
  `HStack(alignment: .firstTextBaseline)`:
  - the title in uppercase, 13 pt bold, `.tracking(1.5)`, `C(accent)`;
  - `Spacer()`;
  - the subtitle, 13 pt, `Theme.textSecondary`.

  This is `StudioDeck`'s look without its expand button, because these decks expand into
  nothing.

**Grounding** (`TabDeck(title: "Grounding", subtitle: "What your AI knows", accent:
.grounding)`). Its content is `VStack(alignment: .leading, spacing: 10) { shelf; shelfLine;
labels; buttons }`.
- **Shelf:** `HStack(alignment: .bottom, spacing: 12)` of four columns. Each column is
  `VStack(spacing: 6) { value; bar }` with `.frame(maxWidth: .infinity)`. The shelf's frame is
  height 230, aligned to the bottom.

  | Column | Value | Bar |
  |---|---|---|
  | Your notes | `store.errorMessage == nil ? "\(open)" : "—"`, where `open` is `store.notes.filter { !$0.archived }.count` | height 190, filled `C(.grounding)` |
  | The folder your AI reads | `GuardrailsGroundingView.age(mirrorWritten, now: Date())` | height 137, filled `C(.grounding).opacity(0.7)` |
  | Claude Code memory files | "Later" | height 57, dashed |
  | Codex memory files | "Later" | height 57, dashed |

  - A value is 22 pt bold. It is `Theme.textPrimary` for the first two columns and
    `Theme.textSecondary` for the two later ones.
  - A filled bar is `RoundedRectangle(cornerRadius: 8, style: .continuous).fill(…)`. A dashed bar
    is the same shape, with `.strokeBorder(C(.grounding).opacity(0.6), style:
    StrokeStyle(lineWidth: 1.5, dash: [6, 4]))`.
  - Each column is `.accessibilityElement(children: .ignore)`, labelled in order: "Your notes:
    <value>", "The folder your AI reads: written <value> ago" (or "not written yet" when
    `mirrorWritten` is nil), "Claude Code memory files: coming later" and "Codex memory files:
    coming later".
- **Shelf line:** `Rectangle().fill(Theme.textSecondary.opacity(0.3)).frame(height: 2)`.
- **Labels:** `HStack(alignment: .top, spacing: 12)` of four `Text`s, the column names above,
  each 11 pt, `Theme.textSecondary`, `.multilineTextAlignment(.center)`, `.frame(maxWidth:
  .infinity)` and `.accessibilityHidden(true)`.
- **Buttons:** `HStack(spacing: 10)` of three buttons. Each has a 13 pt semibold label, 14 pt
  horizontal and 8 pt vertical padding, and `.liquidGlassCapsule(interactive: true)`:
  - "Open notes" calls `store.showAllNotes()`;
  - "Open the folder" calls `store.showAIFolder()` (`AppStore.swift:1261`);
  - "Details" calls `store.showHome()` (`AppStore.swift:1207`).
- **The folder's date:** `.task(id: store.exportFolderURL) { … }` sets `mirrorWritten` from a
  `Task.detached` that reads the `.modificationDate` attribute of `READ ME FIRST.md` inside the
  mirror folder, or nil when it can't. The mirror folder is `store.exportFolderURL ??
  URL(fileURLWithPath: NSString(string: "~/Documents/Unli Rice").expandingTildeInPath,
  isDirectory: true)`, the same as `triggerExportMirror()` (`AppStore.swift:1025-1028`), and it
  is opened with `startAccessingSecurityScopedResource()` and closed again inside the task.
  `MirrorExporter` rewrites that file on every export (`MirrorExporter.swift:152`).
- **`static func age(_ date: Date?, now: Date) -> String`:** nil gives "—". Otherwise, with `s`
  as `max(0, now.timeIntervalSince(date))`: under 60 gives "now", under 3,600 gives
  `"\(Int(s / 60))m"`, under 86,400 gives `"\(Int(s / 3600))h"`, and anything older gives
  `"\(Int(s / 86400))d"`.

**Guardrails** (`TabDeck(title: "Guardrails", subtitle: "What your AI must do", accent:
.guardrails)`). Its content is `VStack(alignment: .leading, spacing: 14) { houseRules; tiles;
later }`.
- **House Rules card:** `VStack(alignment: .leading, spacing: 10)`, padding 18, background
  `RoundedRectangle(cornerRadius: 18, style: .continuous).fill(C(.background))`, overlaid with
  the same shape `.stroke(C(.guardrails).opacity(0.35), lineWidth: 1)`.
  - **Header:** `HStack`:
    - `Text("HOUSE RULES · \(presetName.uppercased())")`, 11 pt bold, `.tracking(1.2)`,
      `C(.guardrails)`, `.lineLimit(1)`;
    - `Spacer()`;
    - `Button("Edit") { store.showHouseRules() }` (`AppStore.swift:1255`), 12 pt semibold, 12 pt
      horizontal and 5 pt vertical padding, `.liquidGlassCapsule(interactive: true)`,
      `.accessibilityLabel("Edit House Rules")`.
  - **`presetName`:** the `title` of the first preset in `HouseRulesPreset.builtIn +
    store.customHouseRulesPresets` whose `HouseRulesRevision.normalized(body)` equals
    `HouseRulesRevision.normalized(store.houseRulesText)`, otherwise "Your own rules". The
    default text matches "Standard Memory".
  - **Lines:** `static func ruleLines(_ text: String) -> [String]`. It splits on newlines,
    trims each line, drops empty lines and lines starting with `#` or `<!--`, removes a leading
    `- `, `* ` or `• `, removes every `**` and backtick, and keeps the first three. Each line is
    `Text(verbatim:)`, 14 pt semibold, `Theme.textPrimary`, `.lineLimit(2)`. With no lines:
    `Text("No House Rules yet.")`, 13 pt, `Theme.textSecondary`.
- **Tiles:** `HStack(spacing: 12)` of three `Button`s with `.buttonStyle(.plain)`. Each label
  is `VStack(spacing: 6) { big; caption }`, `.frame(maxWidth: .infinity)`, 20 pt vertical
  padding, background `RoundedRectangle(cornerRadius: 18, style:
  .continuous).fill(C(.background))`, overlaid with the same shape
  `.stroke(Theme.textSecondary.opacity(0.2), lineWidth: 1)`. The caption is 13 pt,
  `Theme.textPrimary`. Each tile is one accessibility element with the label given.

  | Tile | Big | Caption | Action | Accessibility label |
  |---|---|---|---|---|
  | Need you | `Text("\(store.pending.count + store.unreadNoticeCount)")`, 40 pt bold, `C(.notes)` | "Need you" | `store.showNeedsYou()` | "Need you: <n>" |
  | Safety checks | `Image(systemName:)` at 36 pt, from the table below | from the table below | `store.showTrustCenter()` | the caption |
  | Archived | `Text("\(store.archivedNotes.count)")`, 40 pt bold, `Theme.textPrimary` | "Archived" | `store.showArchived()` | "Archived: <n>" |

  The Safety checks tile reads `store.trustChecks`, which the launch already fills
  (`AppStore.swift:681`). This view never calls `refreshTrustCenter()`, because that reads the
  whole event log on the main thread. The first matching row wins:

  | `store.trustChecks` | Symbol | Colour | Caption |
  |---|---|---|---|
  | empty | `shield` | `Theme.textSecondary` | "Not checked yet" |
  | any `.failed` | `xmark.shield` | `C(.guardrails)` | "Safety checks failed" |
  | any `.attention` | `exclamationmark.shield` | `C(.notes)` | "Safety checks need a look" |
  | otherwise | `checkmark.shield` | `C(.garden)` | "Safety checks pass" |
- **Later row:** `Text("Did your AI follow the rules? Checks are coming later.")`, 13 pt,
  `Theme.textSecondary`, `.frame(maxWidth: .infinity)`, 14 pt vertical padding, overlaid with
  `RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.textSecondary.opacity(0.4),
  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))`.

**Routing.** Every destination above is a row in §2.3's routing table. `lastTab` is already
`.guardrailsGrounding` while this tab shows, so S5's "All decks" button brings each one back here.

### 2.8 Colour and contrast (core: `StudioPalette`, finding 10; settled after the S2 stop report)

```swift
public enum StudioPalette {
    public enum Mode: String, CaseIterable, Sendable { case dark, light }
    public enum Token: String, CaseIterable, Sendable {
        case background, surface, textPrimary, textSecondary
        case garden, branches, notes, grounding, guardrails          // deck title and accent
        case lightDone, lightDraft, lightMissing, lightUnknown       // build-gate light glyphs
        case stickerFineFill, stickerNeedsYouFill, stickerNoStatusFill, stickerCantReadFill
        case stickerDarkText, stickerLightText
        case cover0, cover1, cover2, cover3, cover4, cover5, cover6, cover7, coverText, coverSubtext
    }
    public struct Pair: Sendable { public let foreground: Token; public let background: Token; public let minimum: Double }
    public static func hex(_ token: Token, _ mode: Mode) -> String   // "#RRGGBB", uppercase
    public static let pairs: [Pair]
    public static func contrastRatio(_ a: String, _ b: String) -> Double   // WCAG 2.x
}
```

**Values.** Where a row has one value, it is the same in both modes. These ratios were computed
2026-10-30, and the test recomputes them.

| Token | Dark | Light |
|---|---|---|
| background | `#0E0F12` | `#F5F5F7` |
| surface | `#15171C` | `#FFFFFF` |
| textPrimary | `#F2F3F5` | `#1D1D1F` |
| textSecondary | `#9AA0AB` | `#5E636E` |
| garden | `#3DDC97` | `#0B7A4B` |
| branches | `#5AA9FF` | `#1F5FBF` |
| notes | `#FFB547` | `#8F5300` |
| grounding | `#6FD3D9` | `#0B6B70` |
| guardrails | `#FF8A6B` | `#B23C1C` |
| lightDone | `#3DDC97` | `#14915C` |
| lightDraft | `#FFB547` | `#B86E00` |
| lightMissing | `#8A909B` | `#7A808B` |
| lightUnknown | `#6B707A` | `#878C96` |
| stickerFineFill | `#3DDC97` | |
| stickerNeedsYouFill | `#FFB547` | |
| stickerNoStatusFill | `#C9D3E0` | |
| stickerCantReadFill | `#4A4F59` | |
| stickerDarkText | `#0E0F12` | |
| stickerLightText | `#F2F3F5` | |
| cover0 to cover7 | `#1F3B2E`, `#3A2A14`, `#1C2A3D`, `#3A1F2B`, `#2E2414`, `#26272D`, `#1E3336`, `#2B2B2E` | |
| coverText | `#F2F3F5` | |
| coverSubtext | `#C9CDD4` | |

Sleeve covers and stickers are the same in both modes, because a sleeve is artwork, not chrome.

**`pairs`, checked in both modes:**
- **4.5:1:**
  - `textPrimary`, `textSecondary` and the five deck accents, each on `background` and on
    `surface`;
  - `stickerDarkText` on the Fine, Needs you and No-status fills;
  - `stickerLightText` on `stickerCantReadFill`;
  - `coverText` and `coverSubtext` on each of `cover0` to `cover7`.
- **3:1:** the four light glyphs on `surface`.

**The test.** `testAllTextPairsMeetContrast` iterates `pairs` × `Mode.allCases`, and
`testEveryTokenHasAValidHexInBothModes` checks the hex values. The ratios computed on
2026-10-30:
- lowest text pair: light `garden` on `background`, 4.95;
- lowest glyph: light `lightUnknown` on `surface`, 3.38.

**Use.** The app builds its `Color`s from these values in S5–S7. `GardenCrate.Sleeve.coverIndex`
selects `cover<n>`.

### 2.9 Changes asked for during S8 (founder, 2026-10-31; settled before handoff)

> "fix the tile, but also make the garden cards swipeable with two fingers using track pad maybe
> even add some swoosh sounds like when flipping cards"

Tier 1 (UI only: nothing persisted, no new dependency; AudioToolbox and AppKit are system
frameworks). Two steps on separate branches, because they touch different files.

**S8a — tile (build-light).** In `Sources/UnliRice/Studio/GuardrailsGroundingView.swift`, and
nothing else:
1. In `tiles`, append `.fixedSize(horizontal: false, vertical: true)` to the `HStack(spacing: 12) { … }`.
2. In `tileLabel`, add `.multilineTextAlignment(.center)` to the caption `Text`, and change
   `.frame(maxWidth: .infinity)` to `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
The three tiles then share the tallest tile's height, and a two-line caption is centred.

**S8b — two-finger swipe and flip sound (build).** Why each choice:
- The existing `DragGesture` is a click-and-drag. A trackpad two-finger swipe arrives as
  scroll-wheel events with phases, which SwiftUI gestures don't see, so an AppKit monitor reads them.
- One flip per swipe, after 50 pt of horizontal finger travel. A gesture that starts vertical stays
  vertical, so the Studio tab's `ScrollView` still scrolls. Momentum after a horizontal swipe is
  swallowed so it doesn't scroll the page. A mouse wheel (no precise deltas) is ignored.
- Fingers moving left flip to the next (older) sleeve, the same as the drag. The direction follows
  the fingers whatever the user's natural-scrolling setting.
- The swoosh is generated in code, so no audio file ships and nothing needs a licence. It plays as
  a macOS UI sound, so it is silent when System Settings › Sound › "Play user interface sound
  effects" is off. No new setting. It plays on every flip that changes the front sleeve (buttons,
  ← →, a click on a sleeve behind, drag, swipe) and on nothing else.

Exact changes:

1. **`Sources/UnliRiceCore/TrackpadSwipe.swift` (new).** No AppKit import.
   ```swift
   public struct TrackpadSwipe {
       public enum Phase: Equatable { case began, changed, ended, momentum, other }
       public static let threshold: Double = 50
       public static let decideAfter: Double = 4
       public init() {}
       /// fingerDX: horizontal finger travel in points for this event, negative = fingers moved left.
       /// Returns whether the event should be consumed, and +1 (next) / -1 (previous) when a flip fires.
       public mutating func handle(phase: Phase, fingerDX: Double, dy: Double) -> (consume: Bool, flip: Int?)
   }
   ```
   State: `active`, `axis` (undecided / horizontal / vertical), `absX`, `absY`, `total`, `fired`,
   `lastWasHorizontal`. Rules:
   - `.began`: reset every field (so `lastWasHorizontal = false`), set `active = true`, then
     handle the event's deltas exactly like `.changed`.
   - `.changed`: if not `active`, return `(false, nil)`. Add `fingerDX` to `total`, `|fingerDX|` to
     `absX`, `|dy|` to `absY`. If the axis is undecided and `absX + absY >= decideAfter`, it becomes
     horizontal when `absX > absY`, else vertical. If horizontal: when not `fired` and
     `|total| >= threshold`, set `fired` and flip `total < 0 ? +1 : -1`; return `(true, flip)`.
     Otherwise return `(false, nil)`.
   - `.ended`: `lastWasHorizontal = (axis == horizontal)`; return `(lastWasHorizontal, nil)`; then
     `active = false` and the axis is undecided again.
   - `.momentum`: return `(lastWasHorizontal, nil)`.
   - `.other`: return `(false, nil)`.
2. **`Sources/UnliRiceCore/FlipSwoosh.swift` (new).**
   ```swift
   public enum FlipSwoosh {
       public static let sampleRate = 44_100
       public static let duration = 0.22
       public static let peak = 0.25
       public static func samples() -> [Int16]
       public static func wav() -> Data   // 44-byte RIFF/WAVE header: PCM, mono, 16-bit, little-endian; then samples()
   }
   ```
   `samples()`, exactly (filtered noise whose brightness rises and falls, under a sin² envelope):
   ```swift
   let n = Int(Double(sampleRate) * duration)            // 9702
   var seed: UInt32 = 0x2545F491
   var y1 = 0.0, y2 = 0.0
   var raw = [Double](repeating: 0, count: n)
   for i in 0..<n {
       let t = Double(i) / Double(n - 1)
       seed = seed &* 1_664_525 &+ 1_013_904_223
       let x = Double(seed) / Double(UInt32.max) * 2 - 1
       let cutoff = 400 + 3200 * sin(.pi * t)
       let a = exp(-2 * .pi * cutoff / Double(sampleRate))
       y1 = (1 - a) * x + a * y1
       y2 = (1 - a) * y1 + a * y2
       raw[i] = y2 * pow(sin(.pi * t), 2)
   }
   let maxAbs = raw.map(abs).max() ?? 0
   let scale = maxAbs > 0 ? peak / maxAbs : 0
   return raw.map { Int16(($0 * scale * 32767).rounded()) }
   ```
3. **`Sources/UnliRice/Studio/TrackpadSwipeCatcher.swift` (new).** `struct TrackpadSwipeCatcher:
   NSViewRepresentable` with `let onFlip: (Int) -> Void`, backed by an `NSView` subclass that:
   - returns `nil` from `hitTest(_:)`, so clicks, taps and the drag still reach the sleeves;
   - in `viewDidMoveToWindow()` removes any monitor, then, when `window != nil`, installs
     `NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)`; `updateNSView` refreshes `onFlip`;
   - in the monitor: returns the event untouched unless `event.window === window`; maps the event to a
     phase (`.other` unless `hasPreciseScrollingDeltas`; `.momentum` if `momentumPhase` is non-empty;
     else `.began` / `.changed` / `.ended` for `phase` containing `.began` / `.changed` /
     `.ended` or `.cancelled`; else `.other`); on `.began` with the location outside `bounds`
     (`convert(event.locationInWindow, from: nil)`), resets the tracker to `TrackpadSwipe()` and
     returns the event; otherwise calls `tracker.handle(phase:fingerDX:dy:)` with
     `fingerDX = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX`
     and `dy = event.scrollingDeltaY`, calls `onFlip` with any flip, and returns `nil` when `consume`
     is true, else the event.
4. **`Sources/UnliRice/Studio/FlipSound.swift` (new).** `@MainActor enum FlipSound { static func play() }`.
   On the first call: write `FlipSwoosh.wav()` to
   `FileManager.default.temporaryDirectory/unlirice-flip-swoosh.wav`, create a `SystemSoundID` with
   `AudioServicesCreateSystemSoundID`, and set `kAudioServicesPropertyIsUISound` to `UInt32(1)` on it.
   If any of that fails, remember the failure and stay silent from then on, with no UI and no log.
   `play()` does nothing if the last play was under 0.08 s ago (`ProcessInfo.processInfo.systemUptime`);
   otherwise `AudioServicesPlaySystemSound(id)`.
5. **`Sources/UnliRice/Studio/GardenCrateView.swift`**, two edits only: in `crate`, add
   `.background(TrackpadSwipeCatcher { move(by: $0) })` directly after
   `.frame(width: side, height: side + peek)`; in `select(_:)`, call `FlipSound.play()` directly
   after the `guard`. The `DragGesture` stays.
6. **Tests** (`Tests/UnliRiceCoreTests/TrackpadSwipeTests.swift`, `FlipSwooshTests.swift`, new):
   `testSwipeLeftFlipsNextOnce` (began, then ten `changed(-10, 0)`: exactly one flip, +1, and every
   event consumed), `testSwipeRightFlipsPrevious`, `testBelowThresholdDoesNotFlip` (total −40),
   `testVerticalGestureNeverFlipsOrConsumes` (starts `changed(-1, -20)`, then sixty `changed(-10, 0)`),
   `testMomentumAfterHorizontalIsConsumed`, `testMomentumAfterVerticalPassesThrough`,
   `testOtherPhasePassesThrough`, `testNextGestureFlipsAgain`;
   `testSampleCountAndPeak` (9702 samples, first and last are 0, largest magnitude 8192),
   `testSamplesAreDeterministic`, `testWavHeader` (44 + 19,404 bytes, `RIFF`/`WAVE`/`fmt `/`data`,
   1 channel, 44,100 Hz, 16 bits, data size 19,404).

**S8c — tiles keep their button role (build-light; Q3 failure, 2026-10-31).** §2.7a's "each tile
is one accessibility element" was built as `.accessibilityElement(children: .ignore)` on each tile
`Button`. That wraps the button in a new element with no button role (`AXUnknown`) and no keyboard
focus, so Tab skips all three tiles and VoiceOver can't press them. A `Button` already is one
element, so the wrapper is the defect. In `Sources/UnliRice/Studio/GuardrailsGroundingView.swift`,
and nothing else: on each of the three tile `Button`s in `tiles`, delete
`.accessibilityElement(children: .ignore)` and keep `.accessibilityLabel(…)` exactly as it is.
Acceptance: each tile reports `AXButton` with its label, and Tab reaches it with Keyboard
navigation on.

**S8d — crate sits on its frame's bottom; "1 project" (build-light; Q4 failures, 2026-10-31).**
§2.5a gave the crate `.frame(width: side, height: side + peek)` with the default centre alignment.
The `ZStack` is only one sleeve tall, so the frame centres it and the whole stack sits `peek / 2`
(39 pt) higher than intended: with three sleeves behind the front one (4+ projects), the top one
rises 21 pt above the crate and covers the bottom of the "N projects" headline, and the front
sleeve leaves 39 pt of empty space above the controls. §2.5a's headline also said "1 projects".
In `Sources/UnliRice/Studio/GardenCrateView.swift`, and nothing else:
1. In `crate`, change `.frame(width: side, height: side + peek)` to
   `.frame(width: side, height: side + peek, alignment: .bottom)`.
2. In `body`, change `Text("\(store.studioSleeves.count) projects")` to
   `Text(store.studioSleeves.count == 1 ? "1 project" : "\(store.studioSleeves.count) projects")`.
Acceptance: at 20 sleeves the back sleeves stop below the headline; with one sleeve it reads
"1 project".

**QA.** Q5 now includes a two-finger swipe on the trackpad, and a vertical two-finger scroll over
the crate at 960×600 that still scrolls the page. The swoosh is checked by ear with UI sounds on and
off.

**S8e and S8f — sideways sleeves; "Garden" becomes "Projects" (founder, 2026-10-31, after Q5).**

> "can we make the sleeves move sideways instead, it feels more natural to move sideways when the
> animation follows. Also we need the same animation when the garden window is enlarged. Lastly
> maybe change the name to something more fitting than Garden."

Founder's answers: the name is **Projects** (it matches Branches and Notes, which are named for what
they hold); the motion is **slide on release**, not a sleeve that tracks the fingers. The enlarged
view (`GardenExpandedView`) renders the same `GardenCrateView(compact: false)`, so it gets the new
motion with no change of its own. Code identifiers (`Garden*`, `.projects`, `showGarden`) keep
their names; only user-facing text changes.

**S8e (build) — `Sources/UnliRice/Studio/GardenCrateView.swift`, and nothing else.**
1. Sleeves behind the front one peek out to the **right**, and a flip slides the front sleeve off
   to the **left** (fading and shrinking slightly) while the next slides in from the right. Going
   back reverses it. Swipe, drag, arrow and button directions are unchanged, so the motion now
   follows a left swipe. Replace `SleeveMotion` with:
   ```swift
   private struct SleeveMotion: ViewModifier {
       let distance: Int
       let side: CGFloat
       let reduceMotion: Bool

       // One unconditional chain, so a sleeve keeps its identity as it changes
       // place and the spring animates the change instead of crossfading.
       func body(content: Content) -> some View {
           let behind = max(distance, 0)
           let gone = distance == -1
           content
               .scaleEffect(gone ? 0.94 : 1 - 0.06 * Double(behind))
               .offset(x: gone && !reduceMotion ? -side * 0.6 : 26 * CGFloat(behind))
               .opacity(gone ? 0 : 1)
       }
   }
   ```
   and pass `side: side` where `crate` applies it.
2. In `crate`, `ZStack(alignment: .bottom)` becomes `ZStack(alignment: .leading)`, and
   `.frame(width: side, height: side + peek, alignment: .bottom)` becomes
   `.frame(width: side + peek, height: side, alignment: .leading)`. Nothing else in `crate` changes
   (indices, `zIndex`, hit testing, tap, the swipe catcher, the drag, `ReduceMotionCrate`).
3. Copy in this file: `ProgressView("Reading your garden…")` → `ProgressView("Reading your projects…")`;
   `Label("Plant your first idea", systemImage: "plus.circle")` →
   `Label("Start your first project", systemImage: "plus.circle")`.

**S8f (build-light) — the rest of the rename, exact strings only:**
- `Sources/UnliRice/Studio/StudioView.swift`: `StudioDeck(title: "Garden"` → `StudioDeck(title: "Projects"`
  (its expand button's label becomes "Open Projects" through `StudioDeck`).
- `Sources/UnliRice/Studio/GardenExpandedView.swift`: `Text("Garden")` → `Text("Projects")`.
- `Sources/UnliRice/ProjectGardenView.swift`: `Text("Project Garden")` → `Text("Projects")`;
  `"Garden could not refresh"` → `"Projects could not refresh"`;
  `"Start your project garden"` → `"No projects yet"`.
- `Sources/UnliRice/AppStore.swift`: `"Garden — a quiet overview of your projects and their notes."`
  → `"Projects — a quiet overview of each project and its notes."`

Acceptance: Q5 re-run (every flip method; mid-animation captures show sideways motion in the deck
and the enlarged view); Q4's 20-sleeve and long-name captures re-taken; no "Garden" left on screen
in either tab, the enlarged view, its List mode or the empty state.

## 3. Phase A steps

Each step is given to a builder with the handoff in §7. "Tests" means
`swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`. "App build" means
`swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build --product UnliRiceApp`.

| Step | Label | What | Files (exact; anything else is a stop) | Spec | Verify |
|---|---|---|---|---|---|
| S1 | build | `BuildGate` exactly as §2.6, with tests: `testFeatureBindingIgnoresOtherFeaturesFiles`, `testTwoOpenPlansPicksNewestButListsBoth`, `testCopiedTimestampDoesNotChangeEvidence`, `testDraftSpecIsDraft`, `testSpecNamingOtherIntentIsUnknown`, `testLegacyPlanSpecNotRequired`, `testSettledByWrongAuthorIsNotDone`, `testSettledBeforeLastPremortemIsNotDone`, `testHeadingInsideCodeFenceIgnored`, `testSameToolBothRolesUnknown`, `testPremortemSkipRecorded`, `testIdeaNotRecordedByDefault`, `testIdeaNotRequiredLine`, `testClaudeMdWithoutImportIsDraft`, `testUnreadableFolderIsUnknownNotMissing`, `testOversizeFileUnknown`, `testDocsOver500EntriesUnknown`, `testSymlinkOutsideFolderUnknown`, `testReadsNothingOutsideDocsAndRoot`, `testUnknownAuthorAddsIssue`, `testNoPlanGivesNotRecorded`, `testStageNumberDecidesBuild`, `testNotBuiltWordingIsNotDone`, `testSameDayRebuttalAfterSettledIsDraft`, `testSameDayPostmortemAfterSettledIsDone`, `testTurnOrderIgnoresDates`, `testBacktickedPathWithTrailingTextResolves`, `testBarePathResolves`, `testIntentNoneIsNotRequired`, `testIntentLineWithoutPathIsUnknown`, `testHeaderSearchStopsAt40Lines`, `testRealHeaderFormatsFromThisRepo` (fixtures copy verbatim the header lines of this repo's `PLAN-studio-redesign.md` with `SPEC-studio-redesign.md` and `INTENT-009`'s Status line; `PLAN-four-jobs.md` with `INTENT-006`'s Status line; `PLAN-bridge-hardening.md`; and `PLAN-cleanup-menu-toast.md`. Expected, in that order: Intent done, Spec done, Build missing, open; Intent done, Spec notRequired, Build done, not open; Intent notRequired; no stage number, so not open and Build unknown) | `Sources/UnliRiceCore/BuildGate.swift` (new), `Tests/UnliRiceCoreTests/BuildGateTests.swift` (new). Fixtures are built in a temp directory inside the tests; there are no fixture files | C1–C9 | Tests |
| S2 | build | `GardenCrate` as §2.5, and `StudioPalette` as §2.8, with tests: `testIssuesMeanCantRead`, `testAttentionMeansNeedsYou`, `testNoStatusNoRepoIsNoStatus`, `testRepoWithoutMemoryIsFine`, `testOrderNewestFirstNilLastByName`, `testSubtitleFallbackAndTruncation`, `testStableIndexIsStable`, `testAllTextPairsMeetContrast`, `testEveryTokenHasAValidHexInBothModes` | `Sources/UnliRiceCore/GardenCrate.swift` (new), `Sources/UnliRiceCore/StudioPalette.swift` (new), `Tests/UnliRiceCoreTests/GardenCrateTests.swift` (new), `Tests/UnliRiceCoreTests/StudioPaletteTests.swift` (new) | B1, B2, A6 | Tests; the existing `ProjectGardenTests` (23) still pass |
| S3 | planner | Review S1 and S2 (on separate branches), merge both into `claude/studio-redesign`, and record the test counts | — | — | Rerun the tests at the merge |
| S4 | build | Navigation shell, exactly as §2.3a (§2.3 is the why). Add the `Pane` cases and `lastTab`. Delete the sidebar code. Add `StudioToolbar` (tabs and gear menu). Make `.studio` the launch pane. Hide `Extra.projects` from Setup › Extras. Add `mainColumn` cases that render `StudioView()` and `GuardrailsGroundingView()` as **placeholder views in the same new files** (a `Text` each), so the switch stays exhaustive | `Sources/UnliRice/AppStore.swift`, `Sources/UnliRice/ContentView.swift`, `Sources/UnliRice/AutomationView.swift`, `Sources/UnliRice/Studio/StudioToolbar.swift` (new), `Sources/UnliRice/Studio/StudioView.swift` (new, placeholder), `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` (new, placeholder) | A1, A4, A5, A9 | App build; `xcodegen generate` and the Xcode build |
| S5 | build | The Studio tab, exactly as §2.4a. | `Sources/UnliRice/AppStore.swift` (four stored properties only), `Sources/UnliRice/AppStore+Studio.swift` (new), `Sources/UnliRice/Studio/StudioView.swift`, `Sources/UnliRice/Studio/StudioToolbar.swift`, `Sources/UnliRice/Studio/StudioColor.swift` (new), `Sources/UnliRice/Studio/BuildGateLights.swift` (new), `Sources/UnliRice/Studio/StudioDeck.swift` (new), `Sources/UnliRice/Studio/GardenCrateView.swift` (new, placeholder), `Sources/UnliRice/Studio/BranchesDeck.swift` (new), `Sources/UnliRice/Studio/NotesDeck.swift` (new) | A2, A3, A7, A8, B4–B7 | App build; xcodegen and the Xcode build |
| S6 | build | The Garden crate, exactly as §2.5a (§2.5 is the why). Replace the placeholder. Add `SleeveBackView`, the expanded `.projects` route (the `mainColumn` case changes from `ProjectsPane()` to `GardenExpandedView()`, which holds the List toggle to `ProjectGardenView`), Copy prompt and Reduce Motion | `Sources/UnliRice/Studio/BuildGateLights.swift` (helpers made static, `nextStage` added), `Sources/UnliRice/Studio/GardenCrateView.swift`, `Sources/UnliRice/Studio/SleeveBackView.swift` (new), `Sources/UnliRice/Studio/GardenExpandedView.swift` (new), `Sources/UnliRice/ContentView.swift` (that one case only) | B1–B3, C10, A10 | App build; Xcode build |
| S7 | build | The Guardrails & Grounding tab, exactly as §2.7a (§2.7 is the why), replacing the placeholder | `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` | A1 | App build; Xcode build |
| S8 | planner (the founder or the Codex driver executes it, and Claude reviews the results) | The QA matrix (§4) in an isolated `.app` bundle against a throwaway vault | — | A3–A10 | §4 |
| S8a | build-light | Guardrails tiles share one height; captions centred, exactly as §2.9 | `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` | A1 | App build; Xcode build |
| S8b | build | Two-finger trackpad swipe and flip swoosh, exactly as §2.9 | `Sources/UnliRiceCore/TrackpadSwipe.swift` (new), `Sources/UnliRiceCore/FlipSwoosh.swift` (new), `Sources/UnliRice/Studio/TrackpadSwipeCatcher.swift` (new), `Sources/UnliRice/Studio/FlipSound.swift` (new), `Sources/UnliRice/Studio/GardenCrateView.swift`, `Tests/UnliRiceCoreTests/TrackpadSwipeTests.swift` (new), `Tests/UnliRiceCoreTests/FlipSwooshTests.swift` (new) | B1–B3 | Tests; app build; xcodegen and the Xcode build |
| S8c | build-light | Guardrails tiles keep their button role, exactly as §2.9 | `Sources/UnliRice/Studio/GuardrailsGroundingView.swift` | A1 | App build; Xcode build |
| S8d | build-light | Crate sits on its frame's bottom; "1 project", exactly as §2.9 | `Sources/UnliRice/Studio/GardenCrateView.swift` | B1, B2 | App build; Xcode build |
| S8e | build | Sideways sleeves, and this file's two copy changes, exactly as §2.9 | `Sources/UnliRice/Studio/GardenCrateView.swift` | B1–B3 | App build; Xcode build |
| S8f | build-light | "Garden" becomes "Projects" in the other four files, exactly as §2.9 | `Sources/UnliRice/Studio/StudioView.swift`, `Sources/UnliRice/Studio/GardenExpandedView.swift`, `Sources/UnliRice/ProjectGardenView.swift`, `Sources/UnliRice/AppStore.swift` | A2, B1 | App build; Xcode build |
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
| Q5 | **pass** on the original up-and-over motion (2026-10-31); re-run after S8e below | Claude, with real mouse and key events at `cc3f38d`: the ‹ › buttons, ← and →, a click on the visible strip of a sleeve behind (recipe-box → 2 of 3, tide-clock → 3 of 3) and a mouse drag left/right all flip; a mouse wheel over the crate does not. The founder, on the trackpad: a two-finger swipe left/right flips one sleeve per swipe; a vertical two-finger scroll over the crate at 960×600 scrolls the page without flipping; the swoosh plays on each flip and is silent with "Play user interface sound effects" off. The founder then asked for the sideways motion and the rename (S8e, S8f). Re-run at the S8e/S8f merges by Claude: Next captured mid-flip in the deck and in the enlarged view shows the front sleeve sliding left and fading while the next comes forward from the right; Q4's 20-sleeve and long-name captures re-taken (headline clear, 20 dots, two-line name, full-name tooltip); deck, enlarged view and List say "Projects". Founder's trackpad feel check of the new motion: pending |
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

### 4a. S8 results

Run in the QA wrapper (`com.calmdownoscar.unlirice.studio-qa`, unsigned debug binary built from
`b439ab3`, throwaway vault, three-project fixture garden) on macOS 27.2. Driven by Claude through
Accessibility and screenshots, and walked with the founder. Sizes are window sizes; 960×600 is
the minimum content size (a 960×628 window).

| Id | Result | Evidence |
|---|---|---|
| Q1 | **pass** (2026-10-31) | Studio: three decks in one row at 1440×900; at 960×600 Garden spans the width with Branches and Notes beneath, and scrolling reaches the bottom of Notes with its padding intact. Guardrails & Grounding: both decks side by side at both sizes, no scroll needed. Checked in light and dark. Sleeves stay dark in light mode by design (§2.8). Seen, not a failure: at 960 the "Safety checks need a look" tile is slightly taller than its neighbours and its two-line label is left-aligned (fixed by S8a, `02d7563`, and seen on screen) |
| Q2 | **pass**, except `.whyNotTextFile`: **not run, because no route to it exists** (nothing sets that pane, here or in 1.4 at `8d2189c`; a pre-existing orphan, not a regression) (2026-10-31) | Real mouse clicks (CGEvent) at Accessibility positions, at `3090c37`. Studio: Garden, Branches and Notes expand buttons → their panes → "All decks" → Studio. Tab 2: Open notes, Details (`.home`), Open the folder, Edit House Rules, the Need you tile (and its "All messages" → `.notices`), Safety checks tile (`.trustCenter`), Archived tile → each → "All decks" → tab 2. Gear: Setup, Trust Center, Archived notes, To do, and with those Extras switched on for the check, Map and Your year so far; Setup › Separate memories → Profile Builder. "Back" always returns to the tab it was opened from (`lastTab`, as §2.3 says), so the table's Tab 1 / Tab 2 column describes the usual tab of origin. Found on the way: the three Guardrails tiles are exposed as `AXUnknown`, not buttons (for Q7); Setup › Extras switches have no accessibility labels (for Q7); the iPhone Capture Extra's copy still says "in the sidebar" (for S9) |
| Q3 | **pass** after S8c (2026-10-31). First run **failed**: the three Guardrails tiles never took keyboard focus | With System Settings › Keyboard › "Keyboard navigation" on (it is off by default; turned on for the check and off after). ⌘1/⌘2 switch tabs; plain 1/2/3 expand Garden/Branches/Notes and Esc returns to Studio; ← → flip the crate. Tab order on Studio: Guardrails & Grounding tab, gear, the three expand buttons, the note rows and Next project, then the Studio tab (Previous project is skipped while disabled). Space opens, and Esc closes, Open Garden/Branches/Notes, Edit House Rules, Open notes, Open the folder and Details. Gear by keyboard: Tab to it, Space, ↓, Return opens Setup, Trust Center, Archived notes and To do, and Esc returns. The tiles: 25 Tabs never focused any of them (`AXUnknown`, see S8c). Re-run at the S8c merge: each tile reports `AXButton` with its label, and Tab, Space and Esc open Needs You, Trust Center and Archived Notes and return to tab 2 |
| Q4 | **pass** after S8d (2026-10-31). First run **failed**: back sleeves covered the headline at 4+ sleeves, and one sleeve read "1 projects" | Fixture gardens of 0, 1, 5, 20 and 60 folders with a `memory.md` each (the 5-folder set has a 60-character name, newest). 0: dashed sleeve, "Plant your first idea", "Pick a folder". 20: twenty dots. 60: "1 of 60" in place of dots. The 60-character name wraps to two lines and ends in "…"; hovering the sleeve shows the full name in its tooltip. Re-run at the S8d merge: "20 projects" clear of the sleeves, the stack resting on the controls, "1 project" for one sleeve, and the expanded Garden (340 pt sleeves) still laid out cleanly |

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
