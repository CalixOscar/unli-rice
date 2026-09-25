# BUILD — four app strings that promise more than the code does

**You are stage 5. Build this.** The full reasoning lives in
`docs/PLAN-copy-that-overstates.md` in this repo — read it if you want the why.
This file is the settled spec.

**Branch:** you are already on `feature/copy-that-overstates`, created off `main` at
`1c906a9`. Stay on it. Do not create another branch, do not touch `main`.

**Process note, so you are not misled:** stages 3 and 4 of the studio pipeline (Codex's
pre-mortem, then a Claude revision) were skipped by explicit founder instruction on
2026-09-07. Three questions a pre-mortem would normally have settled are therefore still
open. They are listed at the bottom under "Open decisions". Two are yours to make; one has
already been resolved and folded into the spec below.

**Scope:** copy and doc comments only. **No logic changes anywhere.** If a fix appears to
need a behaviour change, stop and report it rather than making it.

## Why these four are wrong

The public user guide was audited against `1f49c0f` on 2026-09-05 and fourteen claims did
not survive. The guide has been corrected. Four of those claims turned out to originate in
the app, not the guide — the guide was repeating them faithfully. The app and the docs now
disagree, and the app is the copy a user believes.

The To Do one has a dated cause. "Nothing here can be ticked off" was **true** when
`StudioTodo` was written, and `PROJECT_NOTES.md:2016` records it as a deliberate decision.
Then `docs/PLAN-ai-todo-actions.md` shipped a second kind of item — a stored note tagged
`todo`, with a **Done** button, on Mac and phone both — and no string was updated. The
docstrings asserting the old invariant were not updated either, which is how the claim
escaped into the pane header, the guide, and the App Store screenshots.

Every line number below was read from source at `ddae139`. All still current.

## Fix 1 — the To Do list can be partly ticked off

Four sites. All four move together or this recurs.

### 1a. `Sources/UnliRice/TodoPaneView.swift:52` — the pane header (user-visible)

Current:

```swift
Text("Derived from your repositories, each project's memory.md, and notes tagged `todo`. Nothing "
     + "here is ticked off — an item disappears when the work is actually "
     + "done, so the list cannot drift from what is true.")
```

Replace with exactly:

```swift
Text("Derived from your repositories, each project's memory.md, and notes tagged `todo`. "
     + "Repo and memory.md items are not ticked off — they disappear when the work is "
     + "actually done, so the list cannot drift from what is true. A flagged note is a "
     + "note: Done archives it.")
```

The distinction must be in the sentence, because a **Done** button renders a few pixels
below it (`TodoPaneView.swift:161`) and a reader who takes the header literally concludes
that button is a bug.

### 1b. `Sources/UnliRice/TodoPaneView.swift:6` — type docstring

Currently opens `**Nothing here can be ticked off**, by design.` Rewrite the opening to
state the two kinds. **Keep** the existing "a checklist you tick is a second source of
truth" argument and the "this codebase has already paid for notes that disagree with the
repo" line — both are still true and still worth a new reader seeing. Scope them to the
derived items rather than to the whole pane.

### 1c. `Sources/UnliRiceCore/StudioTodo.swift:5` — type docstring

Currently `**Nothing here is stored, and nothing can be ticked off.**` Half of this is
still exactly true and must survive: `StudioTodo` itself stores nothing, adds no
`EventKind`, and writes nothing. What is false is the blanket "nothing is stored" — an
`aiFlagged` item's content **is** a stored note, and `Item.noteID` is the handle to it.
Say it that way: the derivation stores nothing; one of the things it derives *from* is a
note. Leave the "Locked decision #3 — propose, never apply" line intact.

This one is optional — see Open decisions.

### 1d. `Sources/UnliRice/AppStore.swift:89` — one-line comment

Currently `Derived from repos and notes; nothing is stored and nothing is ticked off.`
Same correction, one line.

## Fix 2 — the folder card names a location that is wrong

`Sources/UnliRice/ConnectView.swift:74`

Current:

```swift
subtitle: "Zero-config workspace folder (`~/Documents/Unli Rice/`) for AI tools that read local files.",
```

The App Store build is sandboxed, so `~/Documents` resolves inside the container. The path
the card actually displays one line below (`ConnectView.swift:79`) is
`/Users/<user>/Library/Containers/com.calmdownoscar.unlirice/Data/Documents/Unli Rice`.
The subtitle sends the user somewhere the folder is not, while the right answer sits
directly beneath it.

**This is the decision that was already resolved for you.** An earlier draft said "inside
the app's sandbox", which would be wrong for `swift run UnliRiceApp` and for
`Scripts/make-app.sh` bundles, where `~/Documents` may be the user's real Documents. So
the string asserts no location at all and points at the path already on screen.

Replace with exactly:

```swift
subtitle: "A plain-Markdown folder for AI tools that read local files rather than speaking MCP. The full path is shown below; use Choose Folder… to move it.",
```

**Do not touch `ConnectView.swift:79`.** The displayed path is already correct, and
`expandingTildeInPath` inside the sandbox is *why* it is correct.

## Fix 3 — House Rules is found, not injected

`Sources/UnliRice/ConnectView.swift:213`, plus the docstring at `:204`.

Current subtitle:

```swift
subtitle: "Conventions your connected assistant reads at the start of a session.",
```

The MCP handshake serves only a generic instruction to search or list notes and read
`Wiki: index` (`Sources/unlirice-mcp/main.swift:83`). House Rules is saved as an ordinary
note (`Sources/UnliRice/AppStore+Autopilot.swift:234`). An assistant that searches finds
it; one that does not, never sees it. The current string describes the good case as if it
were the mechanism.

Replace with exactly:

```swift
subtitle: "Conventions saved as a note for connected assistants to find. One that searches your notes at the start of a session picks them up.",
```

At `:204`, replace `/// The instructions a connected assistant reads at the start of a
session.` with a docstring saying it is a note an assistant may find, and **cite
`Sources/unlirice-mcp/main.swift:83`** for what the handshake actually promises. That
cross-reference is the part that stops the claim being reinvented.

## Fix 4 — the merge hint omits the trap

`Sources/UnliRice/ConnectView.swift:399`

Current:

```swift
Text("Unli Rice never opens or edits this file. Merge the copied block manually, keeping any servers already there.")
```

True, and it still leaves the user in the hole. What the app copies is a **complete file**
including the `mcpServers` wrapper (`Sources/UnliRiceCore/MCP/MCPConfigRenderer.swift:26`).
"Merge it, keeping any servers already there" reads as *paste this inside the existing
`mcpServers` object*, which yields `mcpServers` nested inside `mcpServers` — a shape no
client understands, and most fail silently rather than complain. This was the single most
damaging line in the old guide and it is still live in the app.

**The wrinkle:** this hint renders for every row, including the Codex row, which is TOML.
JSON-specific advice would be wrong there. `target` is in scope and `target.format` is
available (`Sources/UnliRiceCore/MCP/MCPTarget.swift:9`). Branch on it:

```swift
switch target.format {
case .mcpServersJSON:
    Text("Unli Rice never opens or edits this file. If it is empty, paste the block as copied. If it already has an mcpServers object, paste only the \"unlirice\" entry inside it — pasting the whole block there nests mcpServers inside mcpServers, and most tools fail silently.")
case .codexTOML:
    Text("Unli Rice never opens or edits this file. Add the copied block at the end, as its own [mcp_servers.unlirice] table, leaving any tables already there alone.")
}
```

Extract the shared modifiers (`.font(.system(size: 10.5))`, the secondary foreground
style, and both paddings) **once** after the `switch` rather than duplicating them on each
branch — duplicated modifiers are how the two rows drift apart later.

## Do not touch

- **`PROJECT_NOTES.md:2016`** ("A to-do list that cannot be ticked off"). Append-only
  history; the entry was accurate when written. Do not rewrite it. Adding a *new* dated
  entry noting that `PLAN-ai-todo-actions.md` later introduced a second kind of item is
  welcome; editing the old one is not.
- **`docs/USER_GUIDE.md`** — checked 2026-09-07, carries none of these four claims.
- **`Scripts/`** — these are copies. Canonical versions live in
  `~/Documents/Unli Rice Vault/scripts/`.
- **Any logic, anywhere.** This branch should contain no behavioural change.
- **App Store screenshots.** `Screenshots/AppStore-Mac-2026-09-03/08-todo.png` shows the
  old header and is in the current submission set. Re-shooting it is a release task, not
  this branch. Mention it in your report.

## Acceptance — check these yourself before reporting

1. `swift build` succeeds and `swift test` passes. Paste the real tail of both. A run
   whose tools were denied still exits 0, so an unquoted "tests passed" is not acceptable.
2. `grep -rn "ticked off" Sources` — no surviving absolute claim. Every hit reads as the
   two-kind version.
3. `grep -rn "Documents/Unli Rice" Sources/UnliRice/ConnectView.swift` — the string is
   gone from the subtitle at `:74` and still present in the path fallback at `:79`.
4. `grep -rn "reads at the start of a session" Sources` — no hits.
5. The JSON rows and the Codex row show **different** merge hints; the Codex one never
   says `mcpServers`.
6. `git diff --stat` touches only `Sources/UnliRice/TodoPaneView.swift`,
   `Sources/UnliRice/AppStore.swift`, `Sources/UnliRice/ConnectView.swift`, and
   `Sources/UnliRiceCore/StudioTodo.swift`. Anything else in that list is a defect.
7. Commit on `feature/copy-that-overstates`. Do not push.

## Open decisions — make them, then say which way you went

1. **Fix 4's placement.** Three sentences of merge instruction in 10.5pt grey under every
   one of five rows is a wall of small text people stop reading — which is how the
   original one-liner got written. If it looks cramped when you build it, move the two
   cases into the `snippetBlock` that appears after **Copy Configuration** is pressed;
   that is arguably the better home anyway, since it is the moment the user is holding the
   block. **Do not** solve a cramped layout by shortening the string back into ambiguity.
   Report which you chose.
2. **Whether 1c is worth doing at all.** `StudioTodo`'s docstring describes `StudioTodo`,
   and `StudioTodo` genuinely stores nothing. The case for changing it is that a reader
   quoted it verbatim into the public guide as a description of the *feature*. "A docstring
   should be written for people who will quote it out of context" is a claim, not an
   obvious truth. If you think it should stand, leave it and say so — that is a legitimate
   outcome, not a skipped task.

## Report

State, per fix, the file and line you changed and the final string. Name anything you
skipped and why. Include the actual `swift build` / `swift test` output and the actual
`git diff --stat`. Do not report SUCCESS without those.
