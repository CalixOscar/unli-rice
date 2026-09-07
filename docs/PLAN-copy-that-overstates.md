# PLAN — four strings that promise more than the code does

**Intent:** no new intent. This is remediation of drift left behind by
`docs/intent/INTENT-004-ai-todo-actions.md` → `docs/PLAN-ai-todo-actions.md`, plus two
older strings that were written before the features they describe existed. Writing an
INTENT for a copy fix would be ceremony; if the pre-mortem disagrees, the intent to
write is "the app should not claim guarantees it does not enforce".
**Stage:** 2 (Claude's plan). **Not built.** Next stop is Codex's pre-mortem, then a
stage-4 revision, then the swarm.
**Date:** 2026-09-07
**Branch:** fresh off `main` — `feature/copy-that-overstates`. `main` is currently at
`ddae139`. Nothing else is in flight in `Sources/`; the only dirty file in the tree is
`Scripts/lint-project-notes.sh`, which is unrelated and must not be swept into this.

## Why

On 2026-09-05 the public user guide at `calmdownoscar.com/unlirice/user_guide.html` was
audited against `1f49c0f`. Fourteen claims did not survive. Six were flatly wrong, and
the guide has since been corrected (`CalmdownOscar@92a6870`, `d6f02d5`, `40e4a53`).

Four of those wrong claims did not originate in the guide. **They are in the app, and
the guide was repeating them faithfully.** Correcting the docs and leaving the app alone
means the two now disagree, and the app is the copy a user believes — it is right there
next to the button.

The most instructive one has a clear provenance. "Nothing here can be ticked off" was
**true** when `StudioTodo` was written, and `PROJECT_NOTES.md:2016` records the reasoning
for it as a deliberate design decision. Then `PLAN-ai-todo-actions.md` shipped, and it
deliberately added a second kind of item — a stored note tagged `todo`, with a **Done**
button, on the Mac and the phone both (that plan's own §2.4, and its lines 151 and 176).
The invariant became half-true and no string was updated. The docstrings that asserted it
were not updated either, which is how the claim then propagated outward into the pane
header, the guide, and the App Store screenshot set.

So this is not a writing nit. It is a stale invariant that has already escaped the
codebase twice, and the docstrings are the reason it kept escaping: the next agent reads
the doc comment, believes the guarantee, and repeats it.

**Verification status.** Every string and line number below was read from source on
2026-09-07 at `ddae139`. The two user-visible ones are additionally corroborated by
screenshots of the running 1.2 (6) build (`Screenshots/AppStore-Mac-2026-09-03/08-todo.png`
and `Screenshots/connect-screen.png`). No claim here is inferred.

**The eval gate does not apply.** The `evals/fixtures/` requirement covers code written
against a *predicted* agent failure mode. These are confirmed string/behaviour mismatches
read directly out of source, so there is nothing to hypothesise and no transcript to
record. Do not let the gate block this.

## Fix 1 — the To Do list can be partly ticked off

Four places assert the old invariant. The user-facing one is the only one a user sees,
but the three docstrings are what caused the leak, so all four move together or this
recurs.

**1a. `Sources/UnliRice/TodoPaneView.swift:52`** — the pane header.

Current:

```swift
Text("Derived from your repositories, each project's memory.md, and notes tagged `todo`. Nothing "
     + "here is ticked off — an item disappears when the work is actually "
     + "done, so the list cannot drift from what is true.")
```

Replace with:

```swift
Text("Derived from your repositories, each project's memory.md, and notes tagged `todo`. "
     + "Repo and memory.md items are not ticked off — they disappear when the work is "
     + "actually done, so the list cannot drift from what is true. A flagged note is a "
     + "note: Done archives it.")
```

The distinction has to be *in* the sentence, because a **Done** button is rendered a few
pixels below it (`TodoPaneView.swift:161`) and a reader who takes the header literally
concludes the button is a bug.

**1b. `Sources/UnliRice/TodoPaneView.swift:6`** — the type docstring. Currently
`**Nothing here can be ticked off**, by design.` Rewrite the opening so it states the
two kinds and keeps the *reason* for the derived half, which is still good and still
worth a new agent reading. Keep the existing "second source of truth" argument; scope it
to derived items.

**1c. `Sources/UnliRiceCore/StudioTodo.swift:5`** — currently
`**Nothing here is stored, and nothing can be ticked off.**` This one needs care, because
half of it is still exactly true and worth defending: `StudioTodo` itself stores nothing
and adds no `EventKind`. What is false is the blanket "nothing is stored" — an
`aiFlagged` item's content *is* a stored note, and `Item.noteID` is the handle to it.
State it that way: the derivation stores nothing; one of the things it derives *from* is
a note.

**1d. `Sources/UnliRice/AppStore.swift:89`** — currently
`Derived from repos and notes; nothing is stored and nothing is ticked off.` Same
correction, one line.

## Fix 2 — the folder is not in the user's Documents

**`Sources/UnliRice/ConnectView.swift:74`**

Current:

```swift
subtitle: "Zero-config workspace folder (`~/Documents/Unli Rice/`) for AI tools that read local files.",
```

The App Store build is sandboxed, so `~/Documents` resolves inside the container. The
path the card actually displays, one line below at `ConnectView.swift:79`, is
`/Users/<user>/Library/Containers/com.calmdownoscar.unlirice/Data/Documents/Unli Rice`.
The subtitle therefore tells the user to look somewhere the folder is not, while the
correct answer sits directly beneath it.

Replace with:

```swift
subtitle: "A plain-Markdown folder for AI tools that read local files rather than speaking MCP. The real path is below — it is inside the app's sandbox, not your own Documents folder.",
```

**Do not touch the path logic at `ConnectView.swift:79`.** The displayed path is already
correct, and `expandingTildeInPath` inside the sandbox is the reason it is correct. This
is a copy fix only.

Note for the pre-mortem: `PROJECT_NOTES.md:1779` records
`openMirrorFolderInFinder()` being changed *to* `~/Documents/Unli Rice/` and away from
"hidden `Group Containers`". Whether that change and this card now disagree about where
the folder is needs one launch to settle. If they do disagree, that is a second, real
bug and belongs in its own plan — not this one.

## Fix 3 — House Rules is found, not injected

**`Sources/UnliRice/ConnectView.swift:213`** (and the docstring at `:204`)

Current:

```swift
subtitle: "Conventions your connected assistant reads at the start of a session.",
```

The MCP handshake serves only a generic instruction to search or list notes and read
`Wiki: index` (`Sources/unlirice-mcp/main.swift:83`). House Rules is saved as an ordinary
note (`AppStore+Autopilot.swift:234`). An assistant that searches finds it; one that does
not, never sees it. "Reads at the start of a session" describes the good case as though
it were the mechanism.

Replace with:

```swift
subtitle: "Conventions saved as a note for connected assistants to find. One that searches your notes at the start of a session picks them up.",
```

And at `:204`, replace `/// The instructions a connected assistant reads at the start of a
session.` with a docstring that says it is a note an assistant may find, and points at
`main.swift:83` for what the handshake actually promises. That cross-reference is the part
that stops the claim being reinvented.

## Fix 4 — the merge hint omits the trap

**`Sources/UnliRice/ConnectView.swift:399`**

Current:

```swift
Text("Unli Rice never opens or edits this file. Merge the copied block manually, keeping any servers already there.")
```

True, and it still leaves the user in the hole. What the app copies is a *complete* file
including the `mcpServers` wrapper (`MCPConfigRenderer.swift:26`). "Merge it, keeping any
servers already there" reads as *paste this inside the existing `mcpServers` object*,
which yields `mcpServers` nested inside `mcpServers` — a shape no client understands, and
most fail silently rather than complain. This was the single most damaging line in the
old guide and it is still live in the app.

This is the one fix with a wrinkle: **the hint is rendered for every row, including the
TOML one**, so JSON-specific advice would be wrong for Codex. `target` is in scope in this
view and `target.format` is available (`MCPTarget.swift:9`), so branch on it:

```swift
switch target.format {
case .mcpServersJSON:
    Text("Unli Rice never opens or edits this file. If it is empty, paste the block as copied. If it already has an mcpServers object, paste only the \"unlirice\" entry inside it — pasting the whole block there nests mcpServers inside mcpServers, and most tools fail silently.")
case .codexTOML:
    Text("Unli Rice never opens or edits this file. Add the copied block at the end, as its own [mcp_servers.unlirice] table, leaving any tables already there alone.")
}
```

Keep the existing modifiers (`.font(.system(size: 10.5))`, secondary style, the two
paddings) on both branches — extract them once after the `switch` rather than duplicating,
or the two rows will drift apart later.

If the JSON string proves too long for 10.5pt at the card width, the fallback is to keep
the short sentence and put the two cases in the `snippetBlock` that appears after
**Copy Configuration** is pressed — which is arguably the better place anyway, since that
is the moment the user is holding the block. Prefer that if it looks cramped; do not
solve it by shortening the string back into ambiguity.

## What not to touch

- **`PROJECT_NOTES.md:2016`** ("A to-do list that cannot be ticked off"). That file is the
  append-only historical record and the entry was accurate when written. Do not rewrite
  it. If anything is added, it is a *new* dated entry noting that
  `PLAN-ai-todo-actions.md` later introduced a second kind of item — history gains an
  entry, it does not get edited.
- **`docs/USER_GUIDE.md`.** Checked on 2026-09-07: it does not carry any of these four
  claims. Leave it alone.
- **The web guide.** Already corrected and live. If a string below is changed to different
  wording than this plan specifies, say so in the handoff so the guide can be brought back
  into line — the two agreeing is the whole point.
- **App Store screenshots.** `08-todo.png` shows the old header text and is in the current
  submission set. Re-shooting it is a release task, not part of this branch. Flag it.

## Acceptance

1. Build both targets. `swift build && swift test` clean.
2. To Do pane: header names both kinds. An AI-flagged item still shows **Done**, and
   pressing it still archives the note and drops the row (`TodoPaneView.swift:161`
   behaviour unchanged — this plan changes no logic).
3. Connect screen: the folder card's subtitle no longer contains the string
   `~/Documents/Unli Rice/`, and the path displayed below it is unchanged.
4. Connect screen: the JSON rows and the Codex row show *different* merge hints, and the
   JSON one names the nesting failure. Codex's does not mention `mcpServers`.
5. House Rules card no longer claims the assistant reads it at the start of a session.
6. `grep -rn "ticked off" Sources` returns only the corrected, two-kind wording — no
   surviving absolute.
7. Diff review: nothing outside `Sources/UnliRice/` and `Sources/UnliRiceCore/StudioTodo.swift`
   is modified. In particular `Scripts/lint-project-notes.sh` is untouched.

## For the pre-mortem (stage 3)

**The weakest assumption is that fix 4 belongs in a 10.5pt caption at all.** Three
sentences of JSON-merge instruction under every one of five rows is a wall of small grey
text that people stop reading, which is how the original one-liner got written. Attack
that first. The alternative shapes are: put it in the `snippetBlock` at copy time; make it
a disclosure ("Where does this go?"); or accept that the guide's worked example is where
this belongs and the app should link out to it. If the answer is "link out", fixes 1–3
still stand on their own.

**Second: whether fix 2's wording is actually true of every build.** The sandbox claim is
correct for the App Store target. `Scripts/make-app.sh` produces a local bundle, and
`swift run UnliRiceApp` runs unsandboxed — where `~/Documents` may be the user's real
Documents. A subtitle that says "inside the app's sandbox" would then be wrong for
developers. Check whether the string needs to be conditional, or whether it should
describe the displayed path rather than assert a location at all. The second option is
probably right and is cheaper.

**Third, and worth someone disagreeing with me:** fix 1c may be over-reach. `StudioTodo`'s
docstring is describing `StudioTodo`, and `StudioTodo` genuinely stores nothing. The case
for changing it is that the sentence was copied verbatim into the public guide by a reader
who took it as describing the *feature*. That is a real cost, but "a docstring should be
written for people who will quote it out of context" is a claim, not an obvious truth.
