# PLAN — The AI to-do list as a widget, in plain words, kept current at every handoff

**Intent:** `docs/intent/INTENT-005-todo-widget.md`
**Stage:** 2 (Claude, plan). **Next: stage 3, the Codex pre-mortem.** The last two plans
(`PLAN-ai-todo-actions`, `PLAN-copy-that-overstates`) both skipped it. This one should not
skip it: it adds a new process (the widget) that writes to the event log, and it changes
a studio-wide contract (`memory.md` fields).
**Verified against:** working tree at `5d1d123`, branch `feature/copy-that-overstates`.
This should get its own branch off `main` once that branch merges.

## 0. What the founder asked for, in four briefs from one session

1. "A widget on the screen that has an actionable to do list based on the chats with
   various llms."
2. "The to do list needs to be understandable by anyone reading it, also non developers."
3. "All LLMs need to update the to do list as part of their hand off."
4. "Pressing an item in the to do list takes me to that specific handoff" / "or generates
   a prompt based on the hand off." Both are planned. Tapping the row opens the handoff,
   and a **Prompt** button copies a pick-up-where-it-left-off prompt (§4 B6).

## 1. What already exists (checked, not assumed)

- **The list itself shipped in `1b4779a`.** An LLM files an item with `create_note` and
  tags it `todo` plus the lowercased project folder name. `StudioTodo.Kind.aiFlagged`
  renders it, and "Done" archives it on the Mac (`TodoPaneView.swift:163`, via
  `AppStore.archive`, `source: "human"`) and in Capture (`CaptureStore.swift:572`,
  `reason: "done"`, `source: "human"`). "Based on the chats" is therefore already served:
  the widget is a new *view* of the existing list, not a new list.
- **The event log already lives where a widget can reach it.** By default it is at
  `DataLocation.supportDirectory()`, which is the App Group container
  `group.com.calmdownoscar.unlirice` (`DataLocation.swift:104`). A user-chosen folder is
  held as a security-scoped bookmark in `AgentSettings`, which also lives in the group.
  The three helper executables already resolve that bookmark from their own processes,
  with `UnliRiceHelper.entitlements` (sandbox + app group + `bookmarks.app-scope`). A
  widget extension gets the same entitlements and resolves the corpus the same way.
- **Cross-process writes are already safe.** `EventStore.append` holds an exclusive `flock`
  (`EventStore.swift:90`), and reads take a shared one. The widget archiving a note is
  one more writer of exactly the kind the MCP helper already is.
- **The AI-flag filter is written out twice**, identically: `TodoPaneView.swift:238` and
  `Capture/TodoView.swift:264`. The widget would be a third copy, so this plan extracts
  it once.
- **The Mac app can already select one note:** `AppStore.selectedNoteID`
  (`AppStore.swift:38`). `WikiLink.targets(in:)` already parses `[[Title]]` links.
- **The app has no URL scheme.** No `CFBundleURLTypes` and no `onOpenURL` anywhere.
  Deep-linking from the widget needs one.
- **Mac deployment target is 13.0** (`project.yml:14`). Interactive widget buttons
  (`Button(intent:)`) need macOS 14.
- **The handoff today is the six `memory.md` fields**, enforced by `lint-memory.sh` in
  pre-commit (canonical copy in the vault). The to-do list is not part of it.
  `AGENTS.md` only asks agents to *ask* about open items before finishing, and forbids
  closing them.

## 2. Decisions (defaults taken; the founder can overturn any of them)

| # | Decision | Why |
|---|---|---|
| D1 | Mac widget only in this pass. No iOS/Capture widget yet. | Capture reads data through `SharedFolderManager`, a different path. Prove the Mac one first. |
| D2 | The widget shows only AI-filed items (`.aiFlagged`), not the git-derived kinds. | Those are the "from the chats" items. The git kinds (at risk, unshared, clutter) are developer-facing by nature. |
| D3 | The widget extension targets **macOS 14.0**; the app stays at 13.0. | Avoids a read-only fallback UI. On 13 the widget simply isn't offered. |
| D4 | **A handoff becomes a note.** At each handoff checkpoint the agent writes one note tagged `handoff` + project, and every to-do item it files links to it with `[[…]]`. Tapping an item opens that handoff note. | Brief 4 needs "that specific handoff" to be a real object the app can open. `memory.md` is overwritten at the next checkpoint and lives in git, which the sandboxed app cannot read by revision. A note is permanent, searchable and already renderable. One handoff note per checkpoint, rather than copying the snapshot into every item, keeps three items from one session pointing at one place. |
| D5 | **Agents may close an item, narrowly** (reverses an INTENT-004 constraint). Only when they finished it in this session, with evidence in `reason`. | Brief 3, "update the to do list", cannot mean append-only without the list rotting. Archive is soft and reversible, and the reason is shown in Archived. **Founder decision — see §9 Q1.** |
| D6 | The handoff rule is enforced by the linter: a **seventh `memory.md` field, `**To-dos:**`**. | Guardrails §"A plan's own Handoff does not bind anything — a hook does" is the studio's own lesson. Text in `AGENTS.md` alone is what already failed to keep the list current. |
| D7 | Order: oldest open item first. | The widget's job is to stop things being forgotten. The longest-waiting one is the most at risk. |

## 3. Part A — shared core (`Sources/UnliRiceCore/`), swarm

### A1. `StudioTodo.swift` — extract the filter

```swift
/// Open AI-filed to-do notes, grouped by the project they name.
/// Key: repo name exactly as in the snapshot (not the lowercased tag).
public static func aiFlags(from notes: [Note], repoNames: Set<String>) -> [String: [Note]]
```

The body is the existing loop, keyed by the snapshot's real name. The existing loop keys
by the lowercased tag, and `derive` then matches that key against repos. **Check how
`derive` currently matches the `aiFlags` keys before changing the key**, and keep
`derive`'s behaviour identical. If re-keying would change it, keep the lowercased key
and add a separate display-name lookup instead. Replace both existing loops
(`TodoPaneView.swift:238`, `Capture/TodoView.swift:264`) with calls to it. No
behaviour change in either pane.

### A2. New `TodoWording.swift` — the plain-language layer, one place

```swift
public enum TodoWording {
    /// "claude" → "Claude", "chatgpt" → "ChatGPT", "gemini" → "Gemini", "kimi" → "Kimi",
    /// "codex" → "Codex", "antigravity" → "Antigravity", "human" → "you".
    /// Anything else: returned as written, first letter capitalised. Never "unknown".
    public static func assistantName(forSource: String) -> String

    /// "Suggested by Claude · 2 days ago · CalmdownOscar"
    public static func subtitle(creator: String, createdAt: Date, project: String, now: Date) -> String

    /// The handoff note an item links to: the first `[[…]]` target in its body that
    /// resolves to a note tagged `handoff`. Nil for items filed before this plan.
    public static func handoffTitle(inBody: String) -> String?
}
```

Use it for the `.aiFlagged` evidence line in **both** panes as well as the widget, so all
three say the same thing. This changes a string the public guide quotes ("Flagged by …").
See §8.

### A3. Tests — `Tests/…/TodoWordingTests.swift`, `StudioTodoTests.swift`

- `assistantName`: each known source; an unknown source; the empty string.
- `subtitle`: fixed `now`, so the relative date is deterministic.
- `handoffTitle`: no link; a link to a non-handoff title; two links (the first one wins).
- `aiFlags`: a note tagged `todo` + a known repo; `todo` + an unknown tag (excluded);
  archived (excluded); tagged for two repos (appears under both). This matches today's
  loop.

## 4. Part B — the widget (`Sources/UnliRiceWidget/`), swarm

### B1. `project.yml`

- New target `UnliRiceWidget`: `type: app-extension`, `platform: macOS`,
  `deploymentTarget: "14.0"`, `dependencies: [UnliRiceCore]`,
  `CODE_SIGN_ENTITLEMENTS: UnliRiceWidget.entitlements`, and Info.plist with
  `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
- `UnliRice` target: depend on `UnliRiceWidget` with `embed: true`.
- `UnliRice` Info: add `CFBundleURLTypes` with scheme `unlirice`.
- New file `UnliRiceWidget.entitlements`: identical to `UnliRiceHelper.entitlements`.
- **Run `xcodegen generate`.** This adds a target and new `Sources/` files.

### B2. Reading the list: `TodoTimelineProvider.swift`

1. Resolve the event log **with the exact call `unlirice-mcp/main.swift` uses**
   (`AgentSettings` + `CorpusLocation.resolve`). Do not write a new resolver.
2. Open `NoteService` read-only and list notes (`includeArchived: false`).
3. Read the repo snapshot (`RepoSnapshotFile.read(fromFolder:)`, the same folder as the
   event log, inside `startAccessingSecurityScopedResource`) → `repoNames`.
4. `StudioTodo.aiFlags(…)`, flatten, sort oldest first.
5. Entry states: `.items([Row])`, `.empty`, `.unknown(reason)`. **Any** failure in steps
   1–3 is `.unknown`, never `.empty` (INTENT-002).
6. Timeline policy `.after(now + 15 min)`. The app additionally calls
   `WidgetCenter.shared.reloadTimelines(ofKind: "UnliRiceTodo")` after any archive or
   note refresh. The MCP helper does not: WidgetKit from a command-line tool is
   unproven, so new items filed by an LLM appear within 15 minutes, or sooner if the app
   is open. This is an accepted limitation.

### B3. Layout: `TodoWidget.swift`

Kind `"UnliRiceTodo"`, `StaticConfiguration`, families `.systemSmall`, `.systemMedium`,
`.systemLarge`. Display name "To do", description "Things your AI assistants suggested
doing later."

| Family | Shows |
|---|---|
| Small | The count ("3 to do") and the oldest title. One tap target, which opens the To Do pane. |
| Medium | Up to 3 rows. |
| Large | Up to 6 rows. |

Each row: title (2 lines max), `TodoWording.subtitle` underneath, and two buttons on the
right: **Prompt** (a `Link` to `unlirice://prompt/<itemNoteID>`, see B6) and **Done**.
The rest of the row is a `Link` to `unlirice://handoff/<itemNoteID>`. On Medium, if
two buttons crowd the title, drop **Prompt** from the row and keep it on Large.
Decide this by looking at the running widget, not from code. If there are
more items than fit: "+N more — open Unli Rice".

All copy, verbatim (this is the plain-language brief; do not paraphrase):

- Empty: "Nothing to do. When an AI assistant spots something for later, it shows up here."
- Unknown: "Can't read your to-do list right now. Open Unli Rice to fix it."
- Done button: "Done". The accessibility label is "Mark done: <title>".

### B4. `MarkTodoDoneIntent.swift`

`AppIntent` with `@Parameter var noteID: String`. `perform()`: resolve the corpus as in
B2, then call `NoteService.archiveNote(id:, reason: "done", source: "human")`. These
match Capture's call exactly. Return `.result()`, and WidgetKit reloads the timeline
itself. On failure, throw. Never mark a row done optimistically.

### B5. Opening "that specific handoff": `UnliRiceApp` / `AppStore`

`.onOpenURL` on the main window:

- `unlirice://handoff/<itemNoteID>` → look up the item. If
  `TodoWording.handoffTitle(inBody:)` names a note that exists, set
  `selectedNoteID` to **that handoff note**. Otherwise set it to the item note itself.
  Both cases switch to the Notes pane. Use whatever pane-selection property the sidebar
  already uses; find it, do not add a second one.
- `unlirice://prompt/<itemNoteID>` → do the handoff case above, then B6.
- `unlirice://todo` → switch to the To Do pane.
- Anything else → ignore.

Items filed before this plan have no handoff link and open themselves. That is correct,
not a bug.

### B6. "Generate a prompt based on the handoff": extend, don't duplicate

`AppStore.copyTodoPrompt(for:item:repo:)` (`AppStore+TodoPrompt.swift:18`) already
backs the pane's "Fix with AI…" menu. For `.aiFlagged` items, extend the prompt it
builds so it contains: the item title, the item body, and **the full body of its handoff
note** (when one is linked), under a heading like "Where the last session left off". End
with a plain instruction: "Pick this up. Check the repository's current state first;
this handoff may be out of date." Keep the existing repo-state section.

The widget can't show the pane's target menu, and it shouldn't read the clipboard
through an extension. So `unlirice://prompt/…` opens the app, copies the prompt for
the **first configured target** (`store.availableTargets.first`), and shows the existing
3-second confirmation: "Prompt copied. Paste it into <target>." If no target is
configured, copy a target-neutral version and say "Prompt copied. Paste it into any AI
assistant." Put the same Prompt action on the handoff note view in the app, so the tap
path and the button path end in the same place.

Test (A3 file or a new one): the prompt for an item with a handoff note contains the
handoff body. With no handoff note, it still builds and does not include the heading.

## 5. Part C — plain language from the LLMs themselves (`AGENTS.md`, MCP instructions), Claude

The widget can only render what agents write. Rewrite `AGENTS.md` §"Filing a to-do
item", step 1:

> **Title: one plain sentence a non-developer understands.** Say what needs doing and,
> if it fits, why. No file paths, branch names, code names, version numbers or
> acronyms in the title. Those go in the body.
>
> - ✗ "Bump ClearSpace Marketing URL field post-redirect"
> - ✓ "Update the website link on the ClearSpace App Store page"
> - ✗ "Fix flaky SnapshotTests on CI"
> - ✓ "Fix the automatic check that sometimes fails for no reason"
>
> **Body:** first line `Handoff: [[<title of the handoff note>]]` (see "At every
> handoff"), then the technical detail.

Also add three sentences to the `instructions` string in `unlirice-mcp/main.swift:83`.
That string is the only thing a chat-app LLM (claude.ai, the ChatGPT app) ever sees:
how to file a to-do (tags), the plain-language title rule, and "if you finished one, archive it
with the reason". Keep it short: it is sent on every connection.

## 6. Part D — the handoff updates the list (Claude; vault + all repos)

### D-1. `AGENTS.md`: new section "At every handoff"

At each handoff checkpoint (the same moment you update `memory.md`, not only at the end):

1. **Write one handoff note.** `create_note`, title
   `Handoff — <Project> — YYYY-MM-DD HH:MM — <tool>`, body = the six `memory.md`
   fields as they stand now plus `git rev-parse --short HEAD`. `tag_note` with `handoff`
   and the project tag. (`handoff` becomes a reserved tag, like `todo`.)
2. **File what you deferred** as to-do items (plain-language titles), each body starting
   `Handoff: [[<that title>]]`.
3. **Close what you finished**, and only that: `archive_note`, with a reason naming the
   evidence ("done in a1b2c3d"). Never close something you did not do, and never
   close something because it looks stale. Use `flag_for_review` for that.
4. Record the result in `memory.md` `**To-dos:**` (D-2).

Replace the current "Before you finish work… Ask; do not just do them" paragraph.
Checking open items first still stands. What changes is who may close them.

### D-2. The seventh field

`memory.md` gains `**To-dos:**` after `**Gotchas:**`, before `**Left by:**`. It holds
"filed N, closed N" with titles, or the literal `none this checkpoint`. It is enforced by
`lint-memory.sh`, so it binds every tool that commits.

Changes, **in the vault first** (canonical), then propagated:

- `~/Documents/Unli Rice Vault/scripts/lint-memory.sh`: require the field and the order.
- `_AI Context/04_Guardrails.md`: "six fields" → "seven". Explain the field and link here.
- The contract block at the top of every studio project's `memory.md` (all repos
  `install-studio-hooks.sh` covers), plus the field itself, added as
  `none this checkpoint`.
- Re-run `install-studio-hooks.sh`. Commit per repo.

**Sequence:** the D-2 edits land in the same sweep across all repos. If the linter
lands before the field exists in a repo, that repo's next commit fails. Order it
field-first, linter-second.

### D-3. What this cannot reach

Chat apps have no `memory.md` and no pre-commit. For them, §5's instruction text is the
whole mechanism, and it is advisory. Say so in `AGENTS.md` rather than implying the rule
covers them equally.

## 7. Acceptance (verify against reality, not the swarm's report)

- `swift build`, `swift test`: all green, test count up by the new cases. Also an
  `xcodebuild` of the `UnliRice` scheme, which builds the embedded extension.
- `git diff` touches only: `project.yml`, `UnliRiceWidget.entitlements`,
  `Sources/UnliRiceWidget/*`, `StudioTodo.swift`, `TodoWording.swift`, the two pane
  files (filter + evidence line only), the app entry/`AppStore` (URL handling only),
  `AppStore+TodoPrompt.swift` (the handoff section only), the handoff note view (Prompt button only),
  tests, and generated `UnliRice.xcodeproj`.
- By hand, in a running build (the founder, or computer-use):
  1. Add the widget. With no open items it shows the empty copy.
  2. File an item through MCP with a handoff note. It appears within 15 minutes (or on
     app refresh) with "Suggested by Claude · …".
  3. Tap the row. The app opens on the **handoff note**, not the item.
  4. Press Prompt. The app opens, the confirmation shows, and the clipboard holds a prompt
     that includes the handoff body.
  5. Press Done. The row disappears, the item shows under Archived with reason "done",
     and the pane agrees.
  6. Point the app at a custom data folder. The widget follows it. If it can't, it shows
     the Unknown copy, never Empty.
- Part C/D: lint passes in every repo after the sweep. One real handoff in some other
  project produces a handoff note + `**To-dos:**` line.

## 8. Things that ride along

- **The public guide** (`CalmdownOscar:unlirice/user_guide.html`) must gain a widget
  section and the new evidence wording. `memory.md` Active constraints says the guide
  and the app copy are expected to agree. The founder or Claude does this, not the swarm
  (other repo).
- **`TodoWording` overlaps `KNOWN_EVENT_KINDS`?** No. No new event kind, so the Python
  prompt hook's fold is untouched. Checked: this plan adds tags, not kinds.
- The prelaunch post-mortem (`_AI Context/07_Prelaunch_Post_Mortem.md`) applies before a
  build carrying the widget is submitted.

## 9. Open questions for the founder

1. **May agents close items (D5)?** **Answered 2026-09-19: yes.**
2. **The seventh field (D6)?** **Answered 2026-09-19: yes.** Done as tooling the same day.
   Both vault linters require `**To-dos:**`, and their field pattern now admits a hyphen
   (it did not, so "To-dos" was invisible to them). Also done: the guardrails, the
   template, `AGENTS.md` § "At every handoff", and the field itself in six repos. Not
   yet in UnliDisk or Butter Smooth; see `memory.md`.
3. **iOS widget** next, or not at all? Still open.

## Handoff

Stage 3: send this file and `INTENT-005` to Codex for the pre-mortem. After stage 4:
Parts A + B go to the swarm through the MCP bridge (bare filename, then move the brief
into `docs/`, per the memory.md Gotchas). Parts C + D are docs/tooling, and Claude does
them directly once §9 Q1–Q2 are answered. Check `git diff` against §7; a `SUCCESS` report
proves nothing.
