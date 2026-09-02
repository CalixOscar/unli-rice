# PLAN — Letting an LLM file a to-do item

**Intent:** `docs/intent/INTENT-004-ai-todo-actions.md`
**Stage:** revised at the founder's direction and **dispatched to the swarm without the
Codex stage-3 pre-mortem** — a deliberate skip of the studio pipeline, recorded here
because the pipeline exists to catch exactly what an unreviewed plan gets wrong.
**Verified against:** working tree at `4b714f2`

**Revision (2026-09-03, founder brief):** two changes to the version Codex never saw.
§2.4 is reversed — Capture gets the same list *and* the same "Done" action as the Mac,
not a read-only view. And §2.7 is new: the list is only half the feature if the founder
has to remember to open it, so every LLM session now reads the open items for the project
it is in and offers to batch them.

## 1. The finding that shapes the design

Every ingredient this needs already exists — the plan is almost entirely a read-side
feature, not a new write surface.

- `create_note` / `tag_note` / `archive_note` are already MCP tools, already used by
  agents in every project, already documented in `AGENTS.md` §"Tags are your
  namespace" and §"Titles are permanent."
- `Note` already carries `tags: Set<String>`, `creator: String`, `createdAt: Date`,
  `archived: Bool` — exactly what an item needs to show who flagged it, when, and
  whether it's done. No schema change.
- Every other project's `AGENTS.md` already tells its agent: *"Conventions for using
  it are in Unli Rice's `AGENTS.md` — read that... for how to title, tag, and when to
  flag."* (Verified: `CalmdownOscar/AGENTS.md`, `Nuptia/AGENTS.md`, `Badminton
  /AGENTS.md`, `UnliDisk/AGENTS.md` all carry this exact pointer.) So documenting a
  new tag convention in Unli Rice's own `AGENTS.md` is already the distribution
  mechanism — nothing else needs to ship it.
- `StudioTodo.derive` already takes derived state as arguments rather than doing I/O
  itself (`nextSteps: [String: MemoryRead]` is the existing precedent) — this plan
  adds one more argument in the same shape, not a new pattern.

So the only new code is: a fixed tag convention (documentation), one new `StudioTodo
.Kind` case plus a matching `Item` field, a query added to each pane's existing
`load()`, and one new row affordance (a "Done" button) that calls a method the Mac app
already has.

## 2. File-by-file

### 2.1 `AGENTS.md` — the convention, documented where every project already points

New section, after "Tags are your namespace":

```
## Filing a to-do item for another project

Noticed something worth doing later, but not now — a version gate, a field that
unlocks on next release, a small inconsistency not worth stopping for? File it:

1. `create_note` — title is the action, short and imperative ("Bump the ClearSpace
   Marketing URL field"). Body is the context: what you found, why it's deferred,
   anything the next reader needs that isn't in the title.
2. `tag_note` with the fixed tag `todo`.
3. `tag_note` again with the target project's exact folder name under
   `~/Documents/Projects`, lowercased — e.g. `calmdownoscar`, not `CalmdownOscar` or
   `clearspace`. This has to be the *project* (the repo), not the feature inside it;
   the To Do pane matches by repo name.

It surfaces in the To Do pane's "flagged by AI" section next time anyone looks, on
both the Mac app and Capture. You don't file it against the project you're in by
default — name the one it's actually about, which may not be this one.
```

`todo` joins `janitor` and `ingest` as a reserved string, but as a *tag*, not a
`source` — the existing reserved-string rule doesn't cover it verbatim and the new
section says so explicitly rather than leaving it implied.

### 2.2 `Sources/UnliRiceCore/StudioTodo.swift`

- New case in `Kind`, inserted after `.declared`:

  ```swift
  case atRisk = 0
  case declared = 1
  case aiFlagged = 2      // new
  case unshared = 3       // was 2
  case clutter = 4        // was 3
  ```

  `rawValue` isn't persisted anywhere (checked: no `Codable` on `Kind`, only used for
  `ForEach(..., id: \.rawValue)` and the `<` ordering) — renumbering is safe.
  `label` gets `"flagged by AI"`.

- `Item` gains one additive field:

  ```swift
  /// The underlying note, when this item came from one — lets the UI archive it
  /// directly instead of parsing an intent back out of `id`. Nil for every kind
  /// that isn't `.aiFlagged`.
  public let noteID: UUID?

  public init(id: String, project: String, kind: Kind, title: String,
              evidence: String, fix: String? = nil, noteID: UUID? = nil) { ... }
  ```

  Existing call sites are unaffected — the parameter has a default.

- `derive(from:nextSteps:worktreeDirt:aiFlags:)` gains one parameter:

  ```swift
  aiFlags: [String: [Note]] = [:]   // key: project name, lowercased
  ```

  For each `(project, notes)` in `aiFlags` where `project` matches a repo in the
  snapshot (same `reposSet` guard the other steps use), emit one `Item` per note:

  ```swift
  out.append(Item(
      id: "\(p)/ai-todo/\(note.id.uuidString)",
      project: p,
      kind: .aiFlagged,
      title: note.title,
      evidence: "Flagged by \(note.creator), "
              + note.createdAt.formatted(.relative(presentation: .named)),
      fix: nil,
      noteID: note.id))
  ```

  Caller is responsible for having already filtered to `tags.contains("todo") &&
  tags.contains(project.lowercased()) && !archived` — `derive` stays pure and
  untangled from `NoteService`, matching how `nextSteps` is read by the caller too.

### 2.3 `Sources/UnliRice/TodoPaneView.swift` (Mac)

- `load()`: after building `byName`, add:

  ```swift
  let allNotes = (try? store.service.listNotes(includeArchived: false)) ?? []
  var aiFlags: [String: [Note]] = [:]
  for note in allNotes where note.tags.contains("todo") {
      for tag in note.tags where reposSet.contains(where: { $0.lowercased() == tag }) {
          aiFlags[tag, default: []].append(note)
      }
  }
  ```

  (`reposSet` — the project names from the snapshot — needs to be available here;
  currently it's local to `StudioTodo.derive`. Simplest: compute it in `load()` from
  `snap.repos.map(\.name)` once, pass to both `derive` and this loop.)

  Pass `aiFlags` into `StudioTodo.derive(...)`.

- `row(_:_:)`: the existing `if kind == .declared { AITodoMenu(...) }` block becomes
  two conditions — add:

  ```swift
  if kind == .aiFlagged, let noteID = item.noteID, let note = store.note(id: noteID) {
      Button("Done") { store.archive(note); Task { await load() } }
          .font(.system(size: 11))
  }
  ```

  `store.archive(_:reason:)` already exists (`AppStore.swift:1433`) — soft, reversible,
  `source: "human"`, already calls `reload()` internally for the notes list. The
  follow-up `load()` re-runs this pane's own derivation so the archived item drops out
  of `todo.items` on the next pass. (`store.note(id:)` already exists too —
  `AppStore.swift`, used for wiki-link resolution.)

- `kindBlurb(.aiFlagged)`: `"an AI session flagged this, not you"`.
- Header copy: add a clause — "...and notes tagged `todo`."

### 2.4 `Sources/UnliRiceCapture/TodoView.swift` (phone)

- Same query shape as 2.3, using `store.noteService.listNotes(includeArchived: false)`
  — `CaptureStore` already exposes `noteService` (`CaptureStore.swift:168`).
- **The phone gets the same list and the same "Done" action as the Mac.** (Reversed
  from the pre-revision plan, which scoped archiving to the Mac.) `CaptureStore`
  already holds a full `NoteService`, and the phone already writes to the log today
  via `appendToProjectNote` — archiving is the same class of write, not a new
  capability. Add:

  ```swift
  public func archiveTodo(noteID: UUID) {
      _ = try? noteService.archiveNote(id: noteID, reason: "done", source: "human")
      sync()
  }
  ```

  `source: "human"` matches the Mac (`AppStore.swift:1435`) — a founder tap on either
  device is the same actor, and using a device-specific source would fragment the
  audit trail for no gain. Confirm `sync()` is the right post-write call by checking
  what `appendToProjectNote` does after its write, and mirror that exactly.
- **The header copy must change.** It currently reads "From your Mac's last snapshot.
  Read-only — tap an item to leave a note about it." That is now false for one section.
  Reword so read-only is scoped to the git-derived items rather than the whole pane —
  the git items genuinely are read-only on the phone (it has no repositories), and the
  distinction is the honest one. Do not delete the read-only language wholesale; a
  pane that quietly stops saying what it cannot do is how the "unknown becomes a
  positive claim" bug class started.
- `kindBlurb` / label: same text as 2.3, mirrored.
- The existing `noteSheet` "leave a note about this" flow stays available on
  `.aiFlagged` rows too — Done and "leave a thought" are different actions and both
  make sense here.
- **Sync-timing question, unresolved here:** the rest of this view reads a
  `RepoSnapshotFile` published by the Mac — a photograph, explicitly stale-tolerant.
  Notes sync on a different path (`ShardWriter`/the event log mirror), and it's not
  verified in this plan whether that sync completes independently of
  `store.sharedFolderURL` being set, or whether the two can disagree about freshness
  in a way that's visible here. Flagged for the pre-mortem, not resolved.

### 2.6 `Scripts/unlirice-prompt-hook.py` — every LLM reads the list, and offers to batch

This is the half that makes the feature work without the founder remembering to look.
A filed item that only surfaces in a pane you have to open is a note in a drawer.

**The prior decision this builds on, unchanged:** `docs/PLAN-studio-cockpit.md:37`
records that this hook "is registered in no settings file, so it currently does
nothing," and that wiring it up is "per-machine settings the user installs — not
something the app does for them." That still holds. **This plan changes what the hook
says, never where it is installed.** See §4.

Extend `main()` so `additionalContext` carries the project's open to-dos:

1. **Identify the project** from `os.getcwd()` — the folder name directly under
   `~/Documents/Projects`. If cwd is not under that root, inject the existing static
   line unchanged and stop. A session in an unknown directory must not guess a project.
2. **Read the corpus** via `corpus_folder()`, which already exists in this file and
   already mirrors `DataLocation`'s precedence.
3. **Fold `events.jsonl`** for notes carrying tags `todo` + the project name lowercased,
   excluding archived. See the drift guard below.
4. **Inject**, when and only when there is at least one:

   ```
   Unli Rice vault active: consult the vault's notes if relevant, and say so
   explicitly if no relevant notes exist.

   Open to-do items filed for <project> (3):
   - Bump the ClearSpace Marketing URL field — filed by claude, 12 days ago
   - <title> — filed by <creator>, <relative date>
   Before you finish a change in this project, ask the founder whether any of these
   should be done in the same pass. Do not act on one without asking; they were
   deferred on purpose, and the reason may still hold.
   ```

   The last two sentences are the requirement, not decoration. The failure mode this
   guards against is an agent reading three deferred items as a work queue and
   clearing it unprompted — every one of these was deferred by someone who had a
   reason, and "the redirect went live so the bump is no longer urgent" is exactly the
   kind of reason that does not survive being skimmed by a fresh session.

**The drift risk, and the guard.** Folding the event log in Python duplicates
`Sources/UnliRiceCore/Projector.swift`, which is the source of truth. Two rules keep
that honest:

- **Fold conservatively and fail open.** The hook needs `created`, `tagged`, `untagged`,
  `archived`, `unarchived` and nothing else. On *any* unrecognized event kind,
  malformed line, unreadable file, or unexpected schema, inject the existing static
  line and stop — never a partial list. A hook that silently under-reports is the
  drawer problem again; a hook that fails loudly on every prompt gets uninstalled.
  Print the reason to stderr, which `record_context_delivery` already establishes as
  this file's diagnostic channel.
- **Pin it with a test.** Add a fixture corpus under `Tests/` and a test asserting the
  Python fold and `Projector` agree on which notes are open-and-tagged for a project.
  Without this, the two implementations drift the first time an `EventKind` is added
  and nothing tells anyone.
- **Never fail prompt submission.** The existing `record_context_delivery` already
  wraps everything in a bare `except` for exactly this reason. Hold that line: a
  broken corpus must cost the founder a missing list, never a blocked prompt.

**Size guard.** Cap the injected list (10 items, then "and N more — open the To do
pane"). This text goes into *every prompt of every session in that project*; an
uncapped list is a per-turn tax on the founder's context budget, and
`PLAN-studio-cockpit.md` already names the 119,551-character lesson.

### 2.7 `AGENTS.md` — the reading half of the contract

§2.1 covers filing. Add the other direction to the same section, since every other
project's `AGENTS.md` already points here:

```
Before you finish work on a project, check whether it has open to-do items — the
prompt hook injects them if one is installed, and `search_notes` for the project's
tag finds them if not. If there are any and you are already changing that project,
ask the founder whether to fold them into this pass. Ask; do not just do them. They
were deferred deliberately and the reason may still hold.
```

Belt and braces with the hook on purpose: the hook is per-machine and may not be
installed, `AGENTS.md` is in the repo and always is. Neither alone reaches every agent.

### 2.8 Tests — `Tests/UnliRiceCoreTests/StudioTodoTests.swift`

- A note tagged `todo` + a matching project tag produces one `.aiFlagged` item with
  the right `noteID`.
- A note tagged `todo` only (no project tag matching any repo in the snapshot) — or a
  project tag only, no `todo` — produces nothing.
- An archived note produces nothing (verifies the caller-side filter contract, even
  though `derive` itself doesn't see `archived` — the test passes a pre-filtered list
  to prove the boundary is where the plan says it is).
- Two notes tagged for the same project produce two items, sorted with the rest by
  `(kind, project, title)`.
- `Kind.allCases` ordering places `.aiFlagged` between `.declared` and `.unshared`.

## 3. Order of work

1. §2.2 — the `Kind` case, `Item` field, and `derive` parameter, with tests (§2.8).
   Nothing calls the new parameter yet; existing behaviour is unchanged (default `[:]`).
2. §2.1 + §2.7 — the `AGENTS.md` sections, both directions. Cheap, and the convention
   must exist before anything can be filed against it.
3. §2.3 — Mac pane: query, render, "Done" button.
4. §2.4 — phone pane: query, render, "Done", and the header rewording.
5. §2.6 — the prompt hook, last. It is the only piece that touches every session in
   every project, so it lands once the thing it advertises actually exists. Build the
   fold + its agreement test before the injection text.

## 4. Explicitly not in this plan

- Due dates, scheduling, notifications.
- Priority beyond where `.aiFlagged` sits in `Kind`'s ordering.
- Editing a filed item's title or body after creation.
- A reply thread beyond the existing "leave a note" sheet.
- A new MCP tool. `create_note` / `tag_note` / `archive_note` are enough.
- Deduplicating near-identical items across sessions.
- Retiring or changing `.declared` / memory.md's Next step field.
- **Installing the hook into any settings file.** `Scripts/unlirice-prompt-hook.py` is
  registered nowhere today, and `PLAN-studio-cockpit.md` already settled that wiring it
  up is per-machine configuration the founder installs, not something this codebase
  does for them. The swarm changes what the hook *says*; a global
  `~/.claude/settings.json` edit reaches every session the founder has on this machine
  and is theirs to make. **Founder step, after the build lands.**
- An agent *acting* on a to-do it found. The contract is ask-then-batch, never
  batch-then-report.

## 5. For the pre-mortem

- **Tag-matching by exact lowercased folder name** is fragile the moment a project is
  renamed or moved — an item filed against the old name silently stops matching.
  Same fragility class as the existing `nextSteps` dictionary keyed by folder name, so
  I judged it consistent rather than a new risk, but it compounds: this is now two
  features that go silent on a rename instead of one.
- **Any session connected to `unlirice` MCP can file an item against any project by
  name, including ones it isn't running in.** I judged this a feature (a session
  working on the marketing site should be able to flag something about the app it's
  marketing) rather than a spoof risk, since `source`/`creator` still records who —
  but it's worth attacking directly rather than accepting my framing.
- **`.aiFlagged`'s position in `Kind`** (right after `.declared`) is a judgement call,
  not derived. It could as easily rank below `.unshared` on the grounds that nothing
  here is validated the way a memory.md next-step is founder-authored.
- **The phone's sync-timing question in §2.4** is stated as unresolved rather than
  answered — I did not verify how `ShardWriter`'s sync path relates to
  `store.sharedFolderURL`'s gating, and this plan should not be built past that point
  without an answer.
- **The Python fold in §2.6 is the single biggest risk in this plan** and the reason a
  pre-mortem would have earned its place. It duplicates `Projector.swift` in a second
  language, in a file that runs on every prompt of every session, where a bug is
  invisible (a silently short list) rather than loud. The fail-open rule and the
  agreement test are the mitigations; whether they are sufficient is the question to
  attack first.
- **Injecting into every prompt has a standing cost.** The hook fires on
  `UserPromptSubmit`, not session start, so the list rides along on every turn for the
  life of the session. The 10-item cap bounds it, but the right design might be
  session-start-only, or a cache keyed on the corpus mtime. Not resolved here.
- **"Ask before batching" is a text instruction, not an enforced boundary.** Nothing
  stops an agent from clearing three deferred items and reporting it afterwards. That
  is the same class of limit as every other instruction in `AGENTS.md`, but it is worth
  saying out loud that this feature hands agents a *list of work* and asks politely.
- **Capture's "Done" writes to the log from the phone**, which the pre-revision plan
  deliberately avoided. `appendToProjectNote` is the precedent that makes it defensible,
  but the sync-timing question above is now load-bearing rather than cosmetic: an
  archive written on the phone and a stale read on the Mac could disagree about whether
  an item is open.
