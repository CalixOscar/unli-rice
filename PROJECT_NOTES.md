# Second Brain — Project Notes

Living status doc. **Read this first** if you're picking this project up in a
new session, on a different machine, or with a different tool (Claude, Codex,
whatever). Keep it current as you work — don't let it drift from what's
actually in the repo.

## What this is

A persistent memory layer whose primary users are autonomous LLM agents
(Claude, coding assistants, local daemons), not humans directly. Multiple
different LLMs (Claude, Gemini, ChatGPT, Kimi, etc.) may all read and write
into the same project's notes concurrently via a local MCP server.

Full original design discussion (CloudKit/SwiftData sync, local MLX janitor
model, storage footprint targets, etc.) is summarized in this repo's git
history / the chat that produced it — the durable architectural decisions
that came out of it are captured below.

## Locked-in architecture decisions (do not violate these)

1. **The event log is append-only and is the source of truth.** Notes are
   never edited or deleted in place. Every change from any agent is a new
   `Event` appended to a JSON-Lines file. Current note state (`Note`) is
   always a *projection* rebuilt from the full event history — throwaway and
   deterministic, not authoritative itself.

2. **No destructive delete exists anywhere in the codebase, on purpose.**
   `NoteService` has no delete method, and no MCP tool maps to one. The
   closest thing is `archive_note`, which is soft and fully reversible via
   `unarchive_note`. This was a direct response to the risk that a local
   janitor model (MLX, or a careless agent) could otherwise silently destroy
   a note that mattered. If a future feature needs real deletion (e.g. a
   time-based purge of old archives), it must be a human-triggered action,
   never something an agent or the janitor can invoke autonomously.

3. **Structural changes (merge, dedupe, "these two notes conflict") are only
   ever proposed, never applied by an agent.** The `flag_for_review` /
   `resolve_review` / `pending_reviews` tools exist specifically so an agent
   can raise a concern without acting on it. Resolving a flag is meant to
   happen after a human decides — there's no UI for that yet (see Deferred).

4. **Every write records which agent made it** (`source` field, e.g.
   `"claude"`, `"gemini"`). This is how multi-LLM concurrent writes stay
   attributable and how future conflict-detection (a janitor comparing what
   different agents wrote) will work.

## What's actually built (MVP, this session)

Swift Package (`swift build` / `swift test`, macOS 13+, Swift 5.10 tools).

- `Sources/SecondBrainCore/` — the engine, has no I/O dependencies beyond the
  filesystem:
  - `Event.swift` — the event model (see decision #1). No `.deleted` kind.
  - `Note.swift` — the read-side projection + `ReviewFlag`.
  - `EventStore.swift` — append-only JSON-Lines file store. `append()` and
    `readAll()` are the only operations.
  - `Projector.swift` — pure function: `[Event] -> [UUID: Note]`.
  - `NoteService.swift` — the only API anything should use to touch notes
    (create/append/tag/untag/archive/unarchive/flag/resolve/search/list/
    transaction log). This is the safety boundary — if you're tempted to
    write directly to `EventStore` from outside this file, don't.

- `Sources/secondbrain-mcp/` — an executable exposing `NoteService` over MCP:
  - Hand-rolled JSON-RPC 2.0 over stdio (one JSON object per line, both
    directions) — **not** using the official Swift MCP SDK yet, see Deferred.
  - Implements `initialize`, `notifications/initialized`, `tools/list`,
    `tools/call`, `ping`.
  - `ToolCatalog.swift` — the 13 tools exposed, 1:1 with `NoteService`
    methods. If you add a `NoteService` method, add a matching tool here and
    in `ToolDispatcher.swift` or it won't be reachable by agents.
  - Data file location: `~/Library/Application Support/SecondBrain/events.jsonl`
    by default, overridable via `SECONDBRAIN_DATA_PATH` env var (used for
    tests/smoke runs so they don't touch real data).

- `Tests/SecondBrainCoreTests/NoteServiceTests.swift` — 9 tests, all passing.
  Covers: create/get, multi-agent append history preservation, tag/untag,
  archive is soft+reversible, archiving never removes underlying history,
  flag/resolve review, search, not-found error, and event log survives
  reopen + reprojects identically (this is the "new device replays the log"
  scenario in miniature).

- Manually smoke-tested the actual `secondbrain-mcp` binary over stdio
  end-to-end (initialize → tools/list → tools/call create_note) — worked.

**Status: builds clean, tests pass, MVP is functionally real** — not a stub.
It's a working local memory store with a real MCP surface. What it is *not*
yet: synced, backed by a real LLM, or reachable from any actual MCP client
config (see Deferred).

## How to build / run / test

```sh
cd "Second brain"
swift build
swift test
swift run secondbrain-mcp   # starts the MCP stdio server, logs to stderr
```

To point a real MCP client (Claude Code, Claude Desktop, etc.) at it, add an
entry to that client's MCP server config pointing at the built binary, e.g.
`.build/debug/secondbrain-mcp` (or `swift run secondbrain-mcp` as the
command). **Not yet done in this session** — nothing is registered with any
client config.

## MCP client registration (done)

- **Claude Code**: project-scoped `.mcp.json` at the repo root points at
  `swift run --package-path <this dir> --quiet secondbrain-mcp`. Takes effect
  next time a Claude Code session starts in this project folder — this
  session couldn't hot-load it into itself.
- **Claude Desktop**: added a `secondbrain` entry to `mcpServers` in
  `~/Library/Application Support/Claude/claude_desktop_config.json` (same
  command). Verified via `jq diff` that no other keys in that file changed —
  the existing `Roblox_Studio` server entry and all app preferences are
  untouched. Takes effect after restarting Claude Desktop.
- Both configs were smoke-tested by running the exact configured command
  and sending a raw `initialize` request — responded correctly.
- Data file is still the shared default (`~/Library/Application
  Support/SecondBrain/events.jsonl` unless `SECONDBRAIN_DATA_PATH` is set),
  so both clients read/write the same underlying notes.

## Deferred / explicitly not done yet, in rough priority order

1. ~~Register the server with an actual MCP client~~ — done, see above.
   Still TODO: actually drive it from within a live Claude Code/Desktop
   session (ask it to create/search notes in conversation) to confirm the
   full loop works, not just the raw protocol handshake.
2. **Swap the hand-rolled JSON-RPC layer for the official MCP Swift SDK**,
   once dependency resolution is confirmed reliable — hand-rolled was chosen
   for this MVP to avoid dependency-resolution risk while getting something
   real and testable quickly.
3. **Review-queue UI** — currently `pending_reviews` / `resolve_review` exist
   as MCP tools only. There's no human-facing surface to see and act on
   flags. This was called out as an eventual must-have ("even just a log
   window"). Until it exists, resolving reviews requires calling
   `resolve_review` manually (e.g. via an agent, at the human's direction).
4. **CloudKit + SwiftData sync layer.** Needs Xcode + an Apple Developer
   account + iCloud container entitlement — can't be scaffolded headlessly.
   When picked up, the event log format here (`Event`, JSON-Lines) is meant
   to map directly onto SwiftData records; the append-only design was chosen
   specifically so CloudKit sync conflict resolution stays simple (new
   records only, no in-place record mutation to reconcile).
5. **Local MLX janitor.** Also needs Xcode/on-device model setup. Per the
   design discussion: use a *separate* small embedding model for
   similarity/retrieval (not the generative model — 1–3B generative models
   were assessed as unreliable for nuanced cross-time concept-matching).
   The generative model's job should stay limited to cosmetic, low-stakes
   actions (bullet TL;DRs) that can auto-apply; anything structural must go
   through `flag_for_review`, never a direct write.
6. **Battery/aggressiveness settings** (Eco vs Aggressive) for how eagerly
   the janitor runs and proposes actions — not started, blocked on #5.
7. **Real search.** `search_notes` is currently plain case-insensitive
   substring matching over title/body/tags. No embeddings/vector search yet
   — intentionally deferred until the embedding model (#5) exists.
8. **Performance**: `NoteService` reprojects the *entire* event log on every
   read call. Fine at current/expected MVP scale (small file, single user's
   projects); will need an in-memory cache + incremental projection before
   this could handle years of heavy multi-agent use. Not a problem yet, flag
   it if the event log grows large and things get slow.

## Repo/environment notes

- Git repo is scoped to this project folder only (`Documents/Projects/Second
  brain`). The user's home directory (`~`) separately has an unrelated, empty
  git repo at `~/.git` — not connected to this project, left untouched,
  don't let the two get confused.
- No remote configured yet. No commits pushed anywhere.
