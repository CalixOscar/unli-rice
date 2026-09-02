# PLAN — Unknown stays unknown

**Intent:** `docs/intent/INTENT-002-unknown-stays-unknown.md`
**Stage:** 4 — revised against Codex's pre-mortem. **Settled. Ready for the swarm.**
**Verified against:** `1a5b550`

## For the swarm — how to execute this

This plan is settled. It has been through Codex's pre-mortem and a stage-4 revision.

- **Implement it; do not re-plan it.** Anything this plan did not anticipate comes back as
  a plan change, not an improvised fix.
- **§9 is a hard boundary.** Do not add anything listed there, however small it looks.
- **Order matters** — follow §7. Core types land before the views that render them.
- **Verify, do not assert.** `swift test` is 343 passing / 0 failures / 2 skipped at
  `4217ba3`. Run it. A count that drops means something was removed.
- **The tree is clean at dispatch** except two untracked screenshot folders
  (`Screenshots/app-panes/`, `Screenshots/repos-pane/`) that are awaiting a founder
  decision. **Do not touch, move, commit or delete them.** Everything else in `git diff`
  afterwards is yours.
- Tests 25-34 in §6 are by-hand checks that a headless run cannot perform. Implement so
  they *can* pass, and report them as unverified rather than as done.

## 0. Stage-4 disposition

Codex's pre-mortem was checked claim-by-claim against the repo. **Every substantive
objection was confirmed true and is accepted.** Two are sharpened below where the repo
showed the mechanism differs from the description. One prescription is declined, with
reasons, in §5.7.

| Objection | Disposition |
|---|---|
| 1. Coverage turns "partly checked" into "all clean" | **Accepted.** §5.1, §5.2 rewritten around three-state coverage |
| 1b. `nextSteps.keys` means "step parsed", not "file readable" | **Accepted.** New defect the review missed — §5.2b |
| 1c. Keep coverage in Core; the phone has the same bug | **Accepted.** §5.2c added |
| 2. `lastWriteAt` needs an evidence-preservation contract | **Accepted and sharpened** — §5.4. The hook's failure mode is a lost update, not field-stripping; and bumping the envelope version is a trap, not a fix |
| 2b. Narrow aliases; attribution ≠ authentication | **Accepted.** §5.5 |
| 2c. Drop "connected N times" | **Accepted.** Confirmed it counts stored name+version records |
| 3. Correct predicates, still-broken journeys | **Accepted, and it is the strongest finding.** §5.8 widened from a flag audit to an action audit |
| 4. "Tamper-evident" repeats the problem | **Accepted.** §5.6 takes Codex's boundary text nearly verbatim |
| 5. The asserted error mapping does not exist | **Correction accepted; the `-32602` remedy declined.** §5.7 |
| 6. Tests promise more than they supply | **Accepted**, including the correction that "every test must fail before" was wrong |

## 1. The finding under the findings

Codex named the pattern as *finishing components without proving the complete user
experience*. That is true, and too broad to build against. The confirmed defects share a
tighter shape, and it is the shape that should be fixed:

> **An unknown is silently converted into a positive claim.**

| Where | The unknown | What it becomes |
|---|---|---|
| `TodoPaneView.load()` | nothing measured worktree dirt | `0` dirty files, for every repo |
| `TodoPaneView.empty` | the snapshot could not be read | "no worktree holds uncommitted work" |
| `TodoPaneView.load()` | memory.md read, step cleared | unreadable → stale snapshot step reappears |
| `UnliRiceCapture/TodoView` | the phone's read failed | "Nothing outstanding" |
| `AppStore.unwrittenClientsDiagnostic` | did this client write? | any tool call, including a search |
| `AppStore.unwrittenClientsDiagnostic` | how many times it connected | a count of name+version records |
| `WhyNotTextFileView` card 1 | who actually wrote this | "Every write is signed" |
| `HomeView` "Start Profile" | no route to the builder | a button that looks like it worked |

This codebase already knows the rule and states it well. `RepoSnapshotFile.Branch` carries
its ancestry fields optional and documents why:

> *"Optionality IS the honesty mechanism: a missing value renders as 'unknown', never as
> zero."*

`Repo.hasAncestry` is the same idea one level up. **Every fix below applies a rule this
repo already wrote down and then didn't apply consistently.** That is what makes it one
task rather than eight.

`8c95a8b` ("an unreadable corpus was shown as 'you are a new user'") was the same bug one
pane over, and `1a5b550` fixed it in the linters — they validated the shape of what was
written and could never notice that nothing was written.

## 2. Triage of the original review at HEAD

Re-verified read-only at `1a5b550`, three commits past the reviewed `8c95a8b`.

| # | Claim | Status at HEAD |
|---|---|---|
| 1 | "Start Profile" reaches no builder | **Still true, and worse.** `ProfileBuilderView` is referenced nowhere but its own definition |
| 2 | Any tool call counts as a write | **Still true.** `AppStore.swift:170` |
| 3 | Dirty-file count hardcoded to zero | **Still true.** `TodoPaneView.swift:195` |
| 4 | "Every write is signed" overstates | **Still true.** `WhyNotTextFileView.swift:24` |
| 5 | `transaction_log` traps on a negative limit | **Still true.** `NoteService.swift:210` |
| — | README quick start broken | **Was true. Fixed** — see §3 |
| — | `memory.md` disagrees with the checkout | **Already fixed** at `1a5b550` |
| — | No CI / `CONTRIBUTING` / `SECURITY` | **Confirmed absent.** Out of scope |
| — | `resolve_review` needs no confirmation | **Confirmed present**, deliberately excluded — §9 |
| — | Purge/appender concurrency | **Not re-checked.** Separate effort |
| — | Search pagination, pairwise duplicates | **Not re-checked.** Separate effort |

## 3. Already done, and why only this

`README.md:39` printed `swift run UnliRice`; `Package.swift:32` names the product
`UnliRiceApp`. The first command a stranger runs failed. Fixed directly — documentation,
not app code. Everything else below is Swift and Python and belongs to the swarm.

## 4. A constraint that shapes the whole plan

**There is one test target, `UnliRiceCoreTests`.** The `UnliRice` app target has none. Any
fix landing only in `AppStore.swift` or a SwiftUI view is untestable by construction —
which is how this bug class survives.

So: **every judgement moves into `UnliRiceCore` as a pure function, and the view renders
it.** Codex's rebuttal is correct and is now part of the plan — *moving a predicate into
Core does not make its inputs or its screen trustworthy.* Therefore each Core type below
also fixes the **input** that feeds it (§5.2b, §5.4) and the plan asserts the **screen**
that renders it (§6, tests 7-15). Core is where the claim can be tested, not where the
work stops.

## 5. File-by-file

### 5.1 `Sources/UnliRiceCore/StudioTodo.swift` — coverage that cannot round up

Codex's counterexample stands: with repos X and Y where only X was measured clean, a
nonempty `dirtMeasured` would have licensed "no worktree holds uncommitted work" for both.
Coverage must therefore be **three-state against the snapshot's own repository set**, not
a bare set of measured names.

```swift
/// What this list actually looked at.
///
/// Separate from the items, because "found nothing" and "never looked" are
/// different answers and only one of them licenses the words "nothing
/// outstanding". Measured against the snapshot's OWN repository set: a set of
/// measured names alone cannot tell partial coverage from complete, and
/// reporting partial as complete is the bug this type exists to prevent.
public struct Coverage: Equatable, Sendable {

    public enum Extent: Equatable, Sendable {
        /// Nothing was inspected. The list is uninformed, not empty.
        case none
        /// Some repositories were inspected; `missing` names those that were not.
        case partial(missing: Set<String>)
        /// Every repository in the snapshot was inspected.
        case complete
    }

    /// False means no snapshot was read at all — the whole list is uninformed.
    public let snapshotRead: Bool
    /// Every repository the snapshot contained. Empty with `snapshotRead == true`
    /// is its own answer: a snapshot that found no repositories.
    public let repositories: Set<String>
    /// How much of `repositories` had its uncommitted-file count measured.
    public let dirt: Extent
    /// How much of `repositories` had its memory.md read — successfully, whether
    /// or not a step was found. See `MemoryRead`.
    public let nextSteps: Extent
    /// When the snapshot was produced. Every finding is only as current as this.
    public let generatedAt: Date?
}
public let coverage: Coverage
```

- `Extent` is derived by comparing what the caller supplied against `repositories` —
  computed in `derive`, never assembled by a caller. A caller cannot claim `.complete`.
- **`public init(items:)` defaults to `snapshotRead: false`, `repositories: []`,
  `dirt: .none`, `nextSteps: .none`.** Codex is right that defaulting to fully-measured
  was itself the bug: items cannot reveal which clean repositories were inspected. The
  twelve existing `StudioTodoTests` construct via `derive`, so they keep passing; any that
  use `init(items:)` directly assert on items only and are unaffected.
- `public static func unread() -> StudioTodo` — empty items, `snapshotRead: false`. This
  replaces today's `StudioTodo(items: [])` on the failure path, which is indistinguishable
  from success.

**Do not** change the dirt semantics themselves: a present key with `0` still means
"measured, clean" and still produces no item. The bug is the caller fabricating the key.

### 5.2 `Sources/UnliRice/TodoPaneView.swift` — stop fabricating, and say what was seen

**`load()`, line ~195.** Delete:

```swift
let dirt = Dictionary(uniqueKeysWithValues: snap.repos.map { ($0.name, 0) })
```

Pass no `worktreeDirt`. The item output is identical today — zero produced no item either —
but the app stops asserting a measurement it never took, and `coverage.dirt` becomes
`.none`, correctly.

**`load()`, the unreadable branch.** Return `StudioTodo.unread()`. Keep the existing
`sourceNote`; it is good and already names the folder.

**`empty`, line ~68.** Choose from `todo.coverage`, and never fall through to the
full-clean copy unless it is earned:

| State | Headline | Body must say |
|---|---|---|
| `!snapshotRead` | **"Nothing to read yet."** | the snapshot at `<path>` could not be read, so this pane knows nothing about any repository. Keep the `check-repos.sh --publish` pointer |
| `snapshotRead && repositories.isEmpty` | **"This snapshot contains no repositories."** | it was read and listed none — the pane is working, the input is empty |
| `dirt == .complete && nextSteps == .complete` | today's copy | true as written, plus "as of `<generatedAt>`" |
| otherwise | **"Nothing outstanding that this can see."** | name what was *not* checked: unmeasured repositories for dirt, unread ones for next steps, and the snapshot time |

**Non-empty case.** The same qualification goes in the header whenever `dirt` or
`nextSteps` is not `.complete` — a user reading three at-risk items will otherwise assume
dirt was among the things checked. Put it beside `sourceNote`, in the same monospaced
style; that line is described in the file's own comment as what "turned 'why is this
empty' from an afternoon of elimination into one launch", and this is the same job.

Wording rule: **name the gap, don't apologise for it.** "Not measured" is a fact; "we
couldn't check" is a hedge. `.partial` must name counts, not just exist — "dirt not
measured for 4 of 7 repositories".

### 5.2b `StudioTodo` + loader — a readable file with no step is not an unreadable file

Codex found a defect the original review missed, and it is the same class. Today
`TodoPaneView.swift:189` writes `steps[name]` **only when a step parsed**:

```swift
guard let body = try? String(contentsOf: m, encoding: .utf8),
      let step = StudioTodo.nextStep(fromMemory: body) else { continue }
```

So a `memory.md` that was read fine but whose next step has been *cleared* is
indistinguishable from one that could not be read — and `StudioTodo.swift:117`
(`nextSteps[p] ?? repo.nextStep`) then falls back to the snapshot's copy. **A next step the
founder has just finished and deleted reappears from a stale snapshot.** Exactly "unknown
becomes a positive claim", pointed the other way.

Replace the `[String: String]` input with a tri-state:

```swift
/// The result of trying to read one project's memory.md.
///
/// `.readNoStep` is the case the loader could not express before: the file was
/// read successfully and names no next step. Collapsing it into "unreadable"
/// let the snapshot's older copy win, resurrecting steps already completed.
public enum MemoryRead: Equatable, Sendable {
    case unreadable
    case readNoStep
    case step(String)
}
```

`derive(from:nextSteps:worktreeDirt:)` takes `[String: MemoryRead]`. The fallback rule
becomes: `.step` wins; **`.readNoStep` suppresses the snapshot fallback**; `.unreadable`
(or absent) falls back to `repo.nextStep`, still labelled "as of the last snapshot".
`coverage.nextSteps` counts `.readNoStep` and `.step` as read, `.unreadable` as not.

The loader must distinguish a missing file (normal — most projects have none, and the
existing comment says so) from a read that failed for another reason. A file that does not
exist is `.readNoStep` only if we are certain we could have seen it; if the directory
listing itself failed, the project is `.unreadable`. Keep the existing security-scoped
access handling as-is.

### 5.2c `Sources/UnliRiceCapture/TodoView.swift` — the phone has the same bug

Confirmed at line ~35: `todo.items.isEmpty` renders "Nothing outstanding", with `status` as
the body — so a failed read on the phone reads as a clean studio. Codex's answer to §8 is
adopted: **coverage stays on the derived Core result, not in the snapshot schema**, and
because `StudioTodo` is already shared, the phone gets the data for free — but *not* the
presentation. Apply the same state table as §5.2, in the phone's card idiom. Shared types
do not fix shared presentation; that is the whole point of this plan.

### 5.3 `Sources/UnliRiceCore/MCP/MCPToolCatalog.swift` (new) — what counts as a write

Codex is right that two hand-maintained lists cannot detect drift. Make the classification
**exhaustive over a shared enum**, so a new tool cannot compile without being classified:

```swift
/// Every tool the MCP server dispatches, and whether it appends an Event.
///
/// `CaseIterable` + an exhaustive `switch` is the mechanism: adding a case
/// without classifying it is a compile error, where two parallel lists would
/// have silently agreed with each other and missed the new tool entirely.
public enum MCPTool: String, CaseIterable, Sendable {
    case createNote = "create_note"
    case appendToNote = "append_to_note"
    case tagNote = "tag_note"
    case untagNote = "untag_note"
    case archiveNote = "archive_note"
    case unarchiveNote = "unarchive_note"
    case flagForReview = "flag_for_review"
    case resolveReview = "resolve_review"
    case getNote = "get_note"
    case listNotes = "list_notes"
    case searchNotes = "search_notes"
    case noteHistory = "note_history"
    case pendingReviews = "pending_reviews"
    case transactionLog = "transaction_log"

    /// Appends an Event. No `default` — a new case must be classified here.
    public var isWrite: Bool {
        switch self {
        case .createNote, .appendToNote, .tagNote, .untagNote,
             .archiveNote, .unarchiveNote, .flagForReview, .resolveReview:
            return true
        case .getNote, .listNotes, .searchNotes, .noteHistory,
             .pendingReviews, .transactionLog:
            return false
        }
    }
}
```

Verified complete against the fourteen cases at `ToolDispatcher.swift:29-123`.

**`ToolDispatcher` must switch on `MCPTool(rawValue: name)`** rather than on string
literals, so the enum is production-linked and not a parallel list. An unrecognised name
still throws `ToolDispatchError.unknownTool(name)` exactly as now. This is the change that
makes test 11 mean something.

### 5.4 `Sources/UnliRiceCore/MCP/ConnectionActivity.swift` — record the write, and keep it

Add one optional field, in the idiom the file already uses for `lastContextDeliveredAt`:

```swift
/// When this client last called a tool that appends an Event.
///
/// Distinct from `lastToolCallAt`, which a search satisfies. Nil means no write
/// has been observed — not that none happened, but that nothing here saw one.
public var lastWriteAt: Date?
```

Set in `recordToolCall` when the tool `isWrite` **and** `succeeded`.

**Compatibility policy — this is the part Codex correctly said was missing.** Two of the
three risks are real; the repo shows the mechanism differs from the description, and the
difference matters:

1. **Older Swift binaries strip it.** Real. `save()` re-encodes typed structs, so a build
   predating this field drops it for every client on its next write. **Accepted and
   bounded:** under the new predicate a missing `lastWriteAt` means "no write observed",
   so stripping degrades toward *under*-claiming, never toward a false all-clear. That is
   the safe direction and is the reason this field can ship without a migration.
2. **The prompt hook does *not* strip it.** `Scripts/unlirice-prompt-hook.py:66` loads
   untyped JSON and mutates one key, so Python's dict preserves fields it has never heard
   of. Its real failure is a **lost update**: it read-modify-writes `connections.json`
   without taking `connections.lock`, so it can clobber a concurrent Swift write wholesale.
   **Fix in this change:** have the hook take the same `flock` on `connections.lock` that
   `MCPConnectionActivityStore.withLock` uses, for the whole read-modify-write. It is a
   handful of lines of `fcntl.flock` and it is in scope precisely because this change adds
   evidence worth not losing. This is *not* the deferred purge-concurrency effort — that
   one is about the event log and is still out of scope (§9).
3. **Do not bump the envelope version.** `load()` requires `envelope.version ==
   currentVersion` (strict equality, line 176) and the hook hardcodes `1` on both read and
   write (lines 66-86). Bumping to 2 would make the hook discard the file and write a v1
   envelope, which Swift would then reject as `.unreadable` — mutual destruction, worse
   than the problem. **Keep `currentVersion = 1`; the field is additive.** If a future
   change must bump it, the hook has to move in the same commit.

### 5.5 `Sources/UnliRiceCore/MCP/UnwrittenClients.swift` (new) — the predicate, testable

```swift
public enum UnwrittenClients {
    /// Clients that connected and have no evidence of a write.
    ///
    /// Two things count as evidence, and a plain tool call is neither: an Event
    /// in the log whose source matches this client, or an observed write-tool
    /// call. A search is not a write — suppressing the warning on one is what
    /// let unli-009 (an agent that read the vault and never wrote back) pass.
    ///
    /// Takes ALL records for a client, not the newest. See below.
    public static func firstUnwritten(
        among activities: [MCPConnectionActivity],
        knownWriterSources: Set<String>
    ) -> MCPConnectionActivity?
}
```

**Aggregation — Codex's version-collapsing objection, confirmed at `AppStore.swift:111`.**
`recentConnectionActivities` collapses by lowercased name and keeps only the newest
`lastSeenAt`, while records are keyed per *name + version*
(`ConnectionActivity.swift:207`). So: v1.2 writes, the user upgrades, v1.3 searches, the
v1.3 record wins, and the write receipt is discarded before the predicate ever sees it.

Fix at the source of the inputs: **evidence is unioned across every record sharing a
client name, before collapsing for display.** A client has written if *any* of its records
has `lastWriteAt`. Collapse newest-first for the row the user sees; never for the evidence.
`AppStore` passes the uncollapsed 7-day window in, and `firstUnwritten` does the grouping —
so the rule is in the tested Core function, not in a view model.

**Aliases — accepted, defined narrowly.** Confirmed alias space: the hook writes
`clientName = "Claude Code"` (`unlirice-prompt-hook.py:19`) while
`HomeView.humanReadableSource` already maps both `claude-code` and `claude` to "Claude".
Existing normalisation (lowercase, hyphen-stripped) matches `"Claude Code"` ↔
`"claude-code"` but **not** `"claude"`. Ship an explicit, short alias table covering
exactly that gap, with a comment stating the rest of the rule:

> Source attribution is self-reported. This maps the identifiers this studio's own tools
> actually use; it does not authenticate that a client is who it says it is, and nothing
> here should be read as proof of identity.

**Message.** Use *"No successful write has been observed for this client."* **Drop
"connected N times"** — confirmed to count stored name+version records, not connections.

`AppStore.unwrittenClientsDiagnostic` shrinks to gathering inputs and formatting prose.
`hasToolCall` disappears from the disjunction.

Expected behaviour change: the warning now appears for clients that read but never wrote.
**That is the point** — the case `evals/cases/unli-009.yaml` records. Do not soften it with
a grace period.

### 5.6 `Sources/UnliRice/WhyNotTextFileView.swift` — claim what the code does

Card 1 is "Every write is signed". `Event` carries a caller-supplied `source` string. My
first revision replaced one overclaim with two smaller ones — "tamper-evident" and
"immutable" — which Codex correctly called the same mistake. The live log is ordinary
JSONL; append-only API behaviour is not filesystem tamper detection, and the device label
is optional.

Adopt Codex's boundary, near-verbatim:

- **Title:** "Every write is attributed"
- **Body:** each event records its supplied source and timestamp, with a device label when
  available. Unli Rice's note tools append changes rather than overwrite earlier entries.
  Clients identify themselves — this is attributed history, not authenticated identity or
  tamper detection. A markdown file cannot tell you who added a line, or when.

**Recorded findings on adjacent copy, not actioned** (as the plan asked for, and not a
licence to redesign the page):

- The absolute Markdown-loss claims on this page overreach.
- "never alters your notes" is contradicted by the janitor, which tags — a real alteration,
  and one the product is otherwise proud of.

Both go to the founder as copy decisions. **Cards 2-7 are otherwise unaudited by this
plan**; anything else found there is a new finding, not a rewrite mandate.

### 5.7 `Sources/UnliRiceCore/NoteService.swift` — reject a limit that cannot mean anything

`transactionLog(limit:)` at line 209 is `.prefix(limit)` on caller input.
`Array.prefix(-1)` traps, so `{"limit": -1}` kills the stdio server — no error, no
response, the client loses its connection.

```swift
guard limit >= 0 else { throw NoteServiceError.invalidLimit(limit) }
```

Throw, do not clamp; clamping hides a caller bug, which is the same instinct this plan
removes. `limit == 0` is a legal request for nothing and returns `[]`.

**The response contract — correction accepted, remedy declined.** The stage-2 draft
asserted
`LocalizedError` and automatic `-32602` mapping. Both were wrong, and Codex is right:
`NoteServiceError` conforms to `Error, CustomStringConvertible` (line 3), and
`ToolDispatcher` catches every error into `{"content": [...], "isError": true}` (line 133),
which `main` returns as a JSON-RPC **result**.

I decline the remedy of forcing `-32602`. Codex's reasoning is that INTENT-002 asks for it —
but the intent's binding requirement is *"returns an error, not a trap"*, and its
"JSON-RPC error" phrasing was my own imprecision at stage 1, not a decision. Per the
guardrails an intent doc is never edited to match what got built, so it stands as written
and this paragraph records the divergence. On the merits, the MCP specification Codex cites
puts **invalid tool arguments in the tool-execution error channel** (`isError: true`), and
reserves `-32602` for protocol-level failures. A bad `limit` is the former. Changing the
channel would also alter the contract for all fourteen tools to fix one.

So the contract is stated here rather than left for the builder:

- `transaction_log` with a negative limit → a JSON-RPC **result** with `isError: true` and
  a message naming the parameter and the received value.
- The server process stays alive and answers the next request.
- `-32602` is **not** used, and no existing tool's error channel changes.
- The dispatcher validates `limit` at the boundary so the message is legible; the Core
  guard remains as the backstop, because the trap is the actual defect.
- **Failed-call recording is preserved:** the rejected call still reaches
  `recordToolCall(..., succeeded: false)`. Verify this on the way through — a validation
  path that returns early before recording would quietly lose the failure, which is this
  plan's own bug class.

### 5.8 Navigation — audit actions, not flags

`HomeView.swift:127` → `showProfileBuilder()` → `showingProfileBuilder = true` →
`ContentView.swift:218` routes into `MoreView`, which has no builder destination. The user
lands on `SetupView` with no error. `ProfileBuilderView` is orphaned.

`showingProfileBuilder` is already tracked separately at `ContentView.swift:120` and `:167`,
which says it was meant to be its own pane:

```swift
} else if store.showingProfileBuilder {
    ProfileBuilderView()
} else if store.showingMore || store.showingSetup || ... {
```

Ordered **before** the `MoreView` branch and removed from that branch's condition.

**Codex's third finding is the strongest in the pre-mortem and rescopes this section.** My
original audit was "the flags in that condition", which would have missed both of these:

- **`showHouseRules()` (`AppStore.swift:1204`)** is `closeAllPanes(); showingMore = true` —
  it opens the hub and selects nothing, so the "Review Rules" button on the very warning
  §5.5 fixes lands on Setup instead of House Rules. A flag audit cannot see this: the flag
  is fine, the *action* is incomplete.
- **`showGetStarted()` (`AppStore.swift:1364`)** sets `showingGetStarted`, which appears in
  **no** branch of `mainColumn`. `ProfileBuilderView.swift:613` calls it on successful
  completion — so making the builder reachable exposes a second dead end at the moment of
  success. Fixing §5.8 without this ships a wizard that vanishes when you finish it.

So the audit is: **every `show*()` method on `AppStore`** — does it reach a rendering
branch, *and* does it select the right destination once there? `MoreView` needs a
`selectedDestination` it can be driven to (a binding or an `AppStore` field), because
several of these actions mean "open the hub *at* X" and today none of them can say X.

Fix the exact instances of this bug. Anything else the audit turns up gets reported, not
improvised.

## 6. Tests

Codex is right that the previous list promised more than it supplied, and right that
**"every test must fail before the change" was wrong** — preserving already-correct
behaviour is worth asserting. Tests are therefore split by role.

### Regression — must fail before, pass after

**`StudioTodoTests.swift`**
1. `derive` with no `worktreeDirt` → `coverage.dirt == .none`.
2. Two repos, one measured clean → `coverage.dirt == .partial(missing: ["Y"])`. **The
   counterexample.** Not `.complete`, not `.none`.
3. `StudioTodo.unread()` → `items.isEmpty && !coverage.snapshotRead`.
4. `init(items:)` → `coverage.dirt == .none`, `snapshotRead == false`. The default is
   unknown.
5. `.readNoStep` suppresses the snapshot's `nextStep` fallback; `.unreadable` does not.
6. `.readNoStep` counts toward `coverage.nextSteps`; `.unreadable` does not.

**Presentation — the decision, not the field.** Codex's point that asserting fields exist
proves nothing. Extract the empty-state choice into a pure Core function
(`TodoEmptyState.for(coverage:) -> Case`) and test it, so both the Mac and the phone assert
the same rule:
7. `!snapshotRead` → `.unread`. **Never `.nothingOutstanding`.**
8. `snapshotRead && repositories.isEmpty` → `.emptySnapshot`.
9. `.partial` dirt → `.qualified`, and the rendered string names the unmeasured count.
10. `.complete` on both → `.nothingOutstanding`, and only here.

**`UnwrittenClientsTests.swift` (new)**
11. Only tool call is `search_notes`, name in no event source → **reported**. Finding 2.
12. Write, then search *on a newer client-version record* → **not** reported. The
    version-collapsing case; fails today.
13. Write → failed write → still not reported (evidence is not revoked by a later failure).
14. Reopening: a fresh record for an existing client name inherits nothing, but the union
    across records still finds the earlier write.
15. Alias table: `Claude Code` ↔ `claude-code` ↔ `claude` all match.

**`ConnectionActivityTests.swift`**
16. `recordToolCall("search_notes")` → `lastWriteAt == nil`.
17. `recordToolCall("create_note", succeeded: true)` → set; `succeeded: false` → nil.

**`NoteServiceTests.swift`**
18. `transactionLog(limit: -1)` throws.

### Compatibility — must pass before *and* after

19. Activity JSON written before this change decodes, `lastWriteAt == nil`.
20. `transactionLog(limit: 0)` returns `[]`. Correct today; must stay correct.
21. Envelope stays `version == 1`; a file written by the Python hook is readable by Swift
    and vice versa, round-tripped both ways with `lastWriteAt` present.

### Exhaustiveness

22. `MCPTool.allCases` covers every case the dispatcher switches on, driven from
    `MCPTool` itself rather than a second list — the dispatcher no longer *has* a list.

### Process-level — a unit test cannot show these

23. Against the real `unlirice-mcp` stdio process, in one session: `transaction_log`
    `{"limit": -1}` → `ping` → `transaction_log` `{"limit": 0}`. Assert the first is a
    result with `isError: true`, the **server is still alive**, response `id`s match their
    requests, and the third returns `[]`. Sequencing in one process is the assertion.
24. The failed call above appears in `connections.json` with `succeeded == false`.

### By hand — this is the class of bug that only shows up here

25. Launch → **Start Profile** → the builder appears; and from its second entry point.
26. Leave the builder without creating anything; state is clean.
27. Complete the builder successfully → `showGetStarted()` lands somewhere real.
28. Force a save failure in the builder → the failure is visible, not swallowed.
29. Home with routines **off** and no Claude folder → the no-write warning is reachable,
    not hidden behind the `else if` chain.
30. Warning → **Review Rules** → actual House Rules, not the Setup pane.
31. Change destination while `MoreView` is already open.
32. **To do** with no `repos.json` → never "Nothing outstanding".
33. Same on the phone (§5.2c).
34. `swift run UnliRiceApp` launches the GUI.

## 7. Order of work

1. §5.3 catalog + dispatcher switch, §5.7 limit guard. Pure Core, no dependencies.
2. §5.1 coverage → §5.2 Mac pane → §5.2b tri-state → §5.2c phone. Core first.
3. §5.4 evidence + hook lock → §5.5 predicate → `AppStore`.
4. §5.8 routing, then the action audit.
5. §5.6 copy. Last, so nobody edits prose while the mechanism moves underneath it.

## 8. Verification

`swift test` — **343 passing before, 0 failures, 2 skipped.** Expect 343 + the new cases.
A test count that goes *down* means something was removed; say so rather than reporting a
pass. Per the guardrails, a `SUCCESS` report is not evidence: check `git diff` and a real
test run.

## 9. Explicitly not in this plan

Named so the swarm does not helpfully add them. Codex's exclusions are kept.

- **The Codex roadmap** — positioning, README rewrite, origin-story wording, CI,
  `CONTRIBUTING.md`, `SECURITY.md`, five-user studies. Founder's calls.
- **`resolve_review` unattended.** Real, but a design question about what an external
  client may do without a human — not a mislabelled unknown.
- **Purge vs. appender concurrency on the event log.** Unreproduced; needs a multiprocess
  test first. The `connections.json` lock in §5.4 is a different file and is in scope only
  because this change adds evidence to it.
- **Search pagination and pairwise duplicate detection.** Publish measurements first.
- **Extending the snapshot schema to carry real dirt counts.** The producer is
  `check-repos.sh`, which lives in `~/Documents/Unli Rice Vault/scripts/`, not this repo.
  Until then unknown stays unknown — which is not a worse product than a fabricated zero.
- **Publishing `check-repos.sh`.** The To do pane tells outside users to run a script they
  cannot obtain. Surfaced, not actioned.
- **Redesigning `WhyNotTextFileView`.** Card 1 only; the other findings are reported.
- **Anything that authenticates a client.** §5.5 states the limit; it does not fix it.
