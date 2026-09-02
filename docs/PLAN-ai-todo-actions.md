# PLAN — Letting an LLM file a to-do item

**Intent:** `docs/intent/INTENT-004-ai-todo-actions.md`
**Stage:** 2 (Claude's plan). **Not built.** Next stop is Codex's pre-mortem, then a
stage-4 revision, then the swarm. Nothing in this file has been implemented.
**Verified against:** working tree at `a962a26`

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
- **No "Done" button on the phone in this plan.** The pane's header text already says
  "Read-only — tap an item to leave a note about it," and the existing `noteSheet`
  flow already lets you leave a thought against any item, `.aiFlagged` included, for
  free. Archiving stays Mac-only; the phone's read-only framing doesn't need
  re-litigating for this feature. (Open question for the pre-mortem: is that the
  right call, or does "flag something in the studio the same week I file it" want to
  work from the phone too?)
- `kindBlurb` / label: same text as 2.3, mirrored.
- **Sync-timing question, unresolved here:** the rest of this view reads a
  `RepoSnapshotFile` published by the Mac — a photograph, explicitly stale-tolerant.
  Notes sync on a different path (`ShardWriter`/the event log mirror), and it's not
  verified in this plan whether that sync completes independently of
  `store.sharedFolderURL` being set, or whether the two can disagree about freshness
  in a way that's visible here. Flagged for the pre-mortem, not resolved.

### 2.5 Tests — `Tests/UnliRiceCoreTests/StudioTodoTests.swift`

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

1. §2.2 — the `Kind` case, `Item` field, and `derive` parameter, with tests. Nothing
   calls the new parameter yet; existing behaviour is unchanged (default `[:]`).
2. §2.1 — the `AGENTS.md` section. Cheap, unblocks nothing else, but should land
   before or alongside the read path so the convention exists the moment it's
   readable.
3. §2.3 — Mac pane: query, render, "Done" button.
4. §2.4 — phone pane: query, render only. Resolve the sync-timing question first if
   the pre-mortem flags it as load-bearing.

## 4. Explicitly not in this plan

- Due dates, scheduling, notifications.
- Priority beyond where `.aiFlagged` sits in `Kind`'s ordering.
- Editing a filed item's title or body after creation.
- A reply thread beyond the existing "leave a note" sheet.
- A new MCP tool. `create_note` / `tag_note` / `archive_note` are enough.
- Archiving from the phone.
- Deduplicating near-identical items across sessions.
- Retiring or changing `.declared` / memory.md's Next step field.

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
- **No "Done" on the phone** trades a real capability (flag it in the studio, resolve
  it from the studio, same week) for not touching the read-only framing. That trade
  might be wrong — flag it rather than assume my call is right.
