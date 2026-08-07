# Battleplan: iOS capture companion + the context-acknowledgment handshake

**Audience:** Google Antigravity.
**Authored by:** Claude Code, 2026-08-04, at the founder's request.
**Branch:** all work on a feature branch (suggested: `feature/ios-capture`) off `main`.
**Authorization note:** `_AI Context/04_Guardrails.md` scopes Antigravity to first-look
ideation. The previous battleplan needed a one-time exemption for that reason; **this one
needs the same grant from the founder before implementation starts.** Section 1 is the
part most worth doing under that exemption — it is small, self-contained, and Mac-only.
**Status of this doc:** a plan, not a spec. Section 1 is non-negotiable in *intent*;
every UI decision is disposable.

> **Shipping rule — no exceptions.** Do not upload, submit, archive for distribution, or
> bump any version of any app. Unli Disk is with App Review. `UnliDisk/PROJECT_NOTES.md:23-28`
> records a session that read handoff wording as a work order and uploaded an unauthorised
> build. Nothing in this document is a work order for App Store Connect.

---

## 0. Read these first, in order

1. `PROJECT_NOTES.md` — authoritative technical record. **The locked-in architecture
   decisions are non-negotiable:** append-only event log, no destructive delete reachable
   by any agent, structural changes proposed never applied, every write attributed via `source`.
2. `AGENTS.md` — how to behave on the `unlirice` MCP server. Identify as
   `source: "antigravity"`. Never write as `janitor` or `ingest`.
3. `Sources/UnliRiceCore/Event.swift`, `EventStore.swift`, `Projector.swift`,
   `LinkIndex.swift` — the whole of Section 2 is about these four files.
4. `Sources/UnliRiceCore/VaultSnapshot.swift:193-248` — **the working prototype of the
   importer you are being asked to generalize.** Read it before designing anything.

---

## 1. NON-NEGOTIABLE: the user must be told, every session, that their notes are in play

**The requirement.** When a user starts a chat with an LLM connected to Unli Rice, they
must get confirmation that their notes are under consideration. The founder's example:

> *"No project folder exists, applying Unli Rice AI context notes."*

### Read this before you design it

**No MCP server can force an LLM to say anything.** Model output is the model's. Worse:
a model can emit *"applying Unli Rice AI context notes"* having called **zero tools** —
that sentence is exactly the shape of thing that hallucinates well. So the self-reported
banner is the one component here that can lie.

This repo has already been burned by precisely that failure. Commit `bfb330e` is
*"Fix dead note-link clicks and **misleading connection status**."*

**Therefore the requirement is satisfied by two things, not one:**

- **The claim** — what the model says. Influenced, never guaranteed.
- **The receipt** — what the app can prove. Authoritative.

Where they disagree, the receipt wins and the UI must say so. That is the Trust Center's
existing job, and this feature belongs to it.

### The primary mechanism is NOT MCP — it is a folder

MCP requires a running process, per-client config JSON, and a client that speaks the
protocol. If the server fails to start, the user gets **silence** — no notes, no warning.
That is the wrong default for "did my notes get used?"

**The alternative: point the agent at the vault folder.** Every serious coding agent
auto-reads a convention file from its working directory at session start — Claude Code
reads `CLAUDE.md`, Codex and Antigravity read `AGENTS.md`, Cursor reads `.cursor/rules/`.
No server, no protocol, no config, no credential. It works in tools that have never heard
of MCP.

**Both halves of this already exist in the repo.**

1. `Sources/UnliRiceCore/Export/MirrorExporter.swift` **already writes the folder** —
   derived Markdown into `<Profile Name> Export/`, with `RAW/` mirroring at `:107`. The
   corpus an agent would read is already being generated.
2. `.claude/settings.json` **already runs a `SessionStart` hook** that injects text into
   every session (the eval gate). The mechanism the founder is asking for is not
   hypothetical — it is running in this repo today.

So this is two small additions to shipping code, not a new subsystem.

#### Idea 0 — "Vault Mode": `MirrorExporter` writes the convention files *(build this first)*

Have `MirrorExporter.exportMirror` additionally emit, at the export root:

- **`CLAUDE.md`** and **`AGENTS.md`** — same content, two filenames, covering every agent.
- Content states live facts and asks for the acknowledgment:

```markdown
# Unli Rice vault — 1,247 notes, profile "Master", updated 2h ago

You are connected to Unli Rice. These notes are the user's memory.

Start here: `Wiki: index.md`, then grep this folder for the topic at hand.

Open your first reply with exactly:
✅ Unli Rice vault connected — 1,247 notes, profile "Master".
If you found no relevant notes, say so instead. Never claim otherwise.
```

Regenerate on export so the counts stay true. Branch the text on whether the folder is
inside a project (`Autopilot.swift` already does package-root detection): *"notes supplement
`CLAUDE.md` for this project"* vs the founder's exact case, *"No project folder here —
Unli Rice notes are your only context."*

**Searching without `search_notes` is fine.** Agents have ripgrep and glob natively and are
good with them; a few thousand markdown files is well within that. Arguably better than the
MCP tool, since the agent sees real structure instead of a flat result list.

**Writes are where MCP still earns its place.** Files written into the mirror by an agent
have no `source` attribution and bypass the append-only log. Two options: keep the mirror
**read-only** and route writes through MCP (hybrid — recommended), or add a watched
`_inbox/` that `LocalFileImporter` (which already scans arbitrary folders) converts into
attributed events. The second closes the loop with no MCP at all; the first ships sooner.

#### Idea 0b — Per-prompt, not just per-session: a `UserPromptSubmit` hook

Convention files load **once per session**. The founder asked for *every prompt*. The
`UserPromptSubmit` hook fires on every submission and can inject text — that is exactly
the mechanism, and `SessionStart` is already proven in this repo.

Ship a tiny script the app can install into the user's settings. Keep the injected line
short — it rides on every prompt and consumes context.

**Be honest about the limit:** hooks are Claude Code-specific. Codex, Cursor, and
Antigravity have no per-prompt equivalent, so they get session-level acknowledgment via the
convention files and nothing finer. Do not describe per-prompt behavior as universal.

#### The receipt in Vault Mode

`MCPConnectionActivity` cannot see a folder read — there is no server in the loop. But the
**hook** is code that runs, so have it record the session (client name, timestamp) into the
same activity store. That yields evidence MCP cannot produce: it fires even when the model
reads nothing, which is precisely the case worth catching.

---

### The MCP path (keep, but secondary)

For users who do connect over MCP, the same requirement needs the same treatment.

#### Idea 1 — Populate the MCP `instructions` field *(~20 lines, currently unused)*

`Sources/unlirice-mcp/main.swift:65-67` returns `protocolVersion`, `capabilities`, and
`serverInfo` on `initialize`. **It does not return `instructions`.** That field is in the
MCP spec, and clients inject it into the model's context at session start. It is the
single highest-leverage unused slot in the codebase for this requirement.

Generate it **dynamically at initialize**, so it states live facts rather than boilerplate:

```
This workspace has an Unli Rice vault: 1,247 notes, profile "Master", last
updated 2 hours ago. Before answering, call `search_notes` for the user's topic
and read `Wiki: index`. Then open your first reply by telling the user which
Unli Rice context you applied — or that you found none.
```

Note this also fixes a real gap: `AGENTS.md` already says *"Read the note titled `Wiki: index`
first"*, but that instruction only works if the agent was told to read `AGENTS.md`.
The `instructions` field delivers it automatically to every client, every session.

**Also handle the founder's exact case.** `Autopilot.swift` already does package-root
detection, so the server knows whether it launched inside a project folder. Branch the
generated text:
- *Project folder found* → "…notes supplement `CLAUDE.md` for this project."
- *No project folder* → "No project folder here — Unli Rice notes are your only context for this session."

#### Idea 2 — Banner on every tool result *(server-controlled, cannot be skipped)*

Tool *results* are text the server writes in full. Prepend a compact banner in
`ToolDispatcher.swift`:

```
[Unli Rice · 1,247 notes · profile "Master" · you are source:"antigravity"]
```

Stronger than Idea 1 because it does not depend on the client honoring `instructions` —
if the model calls a tool at all, it sees this. Keep it to one line; it rides on every
response and eats context. Consider full banner on first call per session, short form after.

#### Idea 3 — A `session_start` handshake tool *(makes silence detectable)*

A tool whose whole job is the handshake: returns note count, active profile, top wiki
hubs, and whether a project root was found — and **records that it was called**.

Its real value is the negative case. If the model never calls it, the app knows. That
enables Idea 4, which is the only part of this feature that cannot be faked.

#### Idea 4 — The receipt, in the Mac UI *(the honest half — build this)*

`MCPConnectionActivity` (`Sources/UnliRiceCore/MCP/ConnectionActivity.swift`) **already
records** `clientName`, `clientVersion`, `firstSeenAt`, `lastSeenAt`, `lastToolName`,
`lastToolCallAt`, `lastToolSucceeded` — deliberately content-free operational evidence.
The infrastructure exists. It is not yet turned into an answer to *"is my stuff being used?"*

Surface, in Trust Center:

> ✅ **Claude Code** read your notes 2 minutes ago — `search_notes`, `get_note`

and the inverse, which is the genuinely valuable alarm:

> ⚠️ **Claude Code** has been connected 40 minutes and has never read a note.

That second line is the thing no banner can fake and no model can hallucinate away.

#### Idea 5 — Menu bar indicator *(ambient, no app switch)*

A status item that is green while a client has read notes this session, grey when
connected-but-silent. Fits the project's "invisible by default" rail: it tells you
without asking you to show up. Verify against `04_Guardrails.md` before building.

#### Idea 6 — Make it self-verifying *(cheap, high trust)*

Have the instruction text ask the model to name **a specific note title** it applied.
A model that read nothing cannot produce a real title, and the app can check the claimed
title against the transaction log. This converts an unfalsifiable claim into a checkable one.

### What to build, in order

1. **Idea 0 — Vault Mode convention files.** The primary path. Smallest change (an
   addition to `MirrorExporter`), works in every agent, no server to fail.
2. **Idea 4 — the receipt in Trust Center.** Ship with Idea 0, never after. A claim with
   no receipt is the `bfb330e` misleading-status bug again with better copy.
3. **Idea 0b — the per-prompt hook.** Delivers the founder's literal "every prompt"
   requirement for Claude Code.
4. **Idea 1 — MCP `instructions`.** Same requirement, MCP path, ~20 lines.
5. Ideas 2, 3, 5, 6 as follow-ons.

**Do not ship any claim without its receipt.** That coupling is the non-negotiable inside
the non-negotiable.

---

## 2. The iOS capture companion

### Context

There is no mobile capture path. The friction case is real: a thought while walking is
lost because opening a chat app, picking a model, and waiting for a connection takes
5–10 seconds, and legacy iOS dictation cuts you off after a few seconds of silence.

The naive design — iOS writes `.md` files with frontmatter into an iCloud `/raw` folder,
Mac watches and merges — builds a **second ingestion system** permanently parallel to the
event log. Phone captures would have no provenance, no `note_history`, no janitor
visibility. Avoid this.

**Thesis: the payload is the architectural decision; the transport is secondary.** If iOS
emits `Event` records rather than markdown files, every transport becomes an
interchangeable way to move the same bytes and `Projector` needs no changes.
`PROJECT_NOTES.md:1442-1447` already committed to this — append-only was chosen so sync
conflict resolution stays "new records only."

### Mechanism: per-device log shards

iOS **never** writes the Mac's `events.jsonl`. Each device owns an append-only shard
(`events-<deviceUUID>.jsonl`) in a shared folder; the Mac imports foreign shards,
appending unseen events through the normal `EventStore` path.

No two devices write the same file, so the cross-device concurrent-write problem `flock`
cannot solve never arises, and the single-log invariant is preserved. **This is already
shipping code** — `VaultSnapshot.swift:193-216` reads a foreign event file, dedups against
`Set(store.readAll().map(\.id))`, and appends. Generalize it; don't invent.

### Transports (all three considered)

| Transport | Verdict |
|---|---|
| **iCloud Drive shards** | **Ship this.** Reuses existing security-scoped bookmark machinery; Path A needs zero new entitlements. Polling latency, plaintext at rest. |
| **CloudKit** | **Keep behind the abstraction; don't build.** Same payload; `CKServerChangeToken` is exactly the watermark being hand-rolled. Buys push latency and a private-DB privacy surface. |
| **Local network / MCP** | **Ruled out on principle, not effort.** Needs `network.server` in a sandboxed app plus a pairing secret — i.e. a credential. `PROJECT_NOTES.md:934-936`: *"nothing here stores an API key or a credential, and nothing should."* Also dead whenever the Mac sleeps — the exact case this is for. |

### Three verified problems the naive version gets wrong

**1. Backdated imports break `LinkIndex`, not `Projector`.** `LinkIndex.swift:32-35` claims
titles in **arrival order** — its comment says this "is the same thing for a log written
in real time." `Projector.resolveLinks` (`Projector.swift:132`) sorts by
`(createdAt, id.uuidString)`. A capture made offline at 09:00 and imported at 17:00 is
exactly where those diverge, and `ProjectionCacheTests.swift:32,123` assert they are equal.
(`Projector.swift:24`'s claim that nothing backdates is **already stale** — snapshot
restore does. iOS makes an existing hazard routine.)

**2. ID-scan dedup would resurrect purged notes.** `Trash.purge` rewrites `events.jsonl`
(`Trash.swift:163`) — the only true delete in the codebase. An importer that dedups by
"is this id in the local log?" finds purged ids absent and re-imports them, silently
defeating the app's only delete. **A persisted per-shard byte cursor is mandatory for
correctness, not speed.** Keep an ID scan as a belt for first run.

**3. `source: "ios"` would corrupt provenance permanently.** `source` is agent identity,
feeding `Note.creator`/`sources`/`editors`, `Retrospective`'s contributor leaderboard
(`:284-323`), `machineSources` (`:420-423`), and `AppStore.hasUserAuthoredNotes:410`. A
note *you dictated* would be credited to a device, splitting your own stats across two
identities forever. Use `source: "human"` plus a **new optional `device: String?`** on
`Event` — optional fields are bidirectionally compatible.

### Phase 0 — Harden the log for a second writer

Mac only. No iOS, no device, no certificate. Fully `swift test`-able. **Ship first.**

| File | Change |
|---|---|
| `Event.swift` | Add `device: String?`. Tolerant `EventKind` decode → `.unrecognized` instead of throwing. |
| `EventStore.swift` | Add `appendRaw(_ line: Data)` — same queue, same `flock`, no re-encode. |
| `LinkIndex.swift` | Claim titles by `(createdAt, id.uuidString)` with displacement, not arrival order. ~25 lines. The only projection change in the plan. |
| `Projector.swift` | Skip `.unrecognized`. Fix the stale doc comment at `:20-25`. |
| `NoteService.swift` | Add `rebuild()` — no escape hatch exists today. |

**Why `appendRaw`:** `EventKind` has no unknown case and `EventStore.read:154` uses
`compactMap { try? decode }`. If a newer iOS build emits an unknown kind, the event is
swallowed and the cursor moves past it — **gone, unfixable retroactively.** Decoding only
`{id}` and appending original bytes verbatim means an old Mac preserves what it cannot parse.

New `Tests/UnliRiceCoreTests/ShardImportTests.swift`:
- `testImportingABackdatedCreatedStillMatchesAColdProjection` — **must fail before the LinkIndex fix.** This is the proof the thesis needs.
- `testAppendRawPreservesUnknownEventKinds`
- `testDuplicateCreatedWipesTheNote` — documents why dedup is load-bearing (`Projector.swift:40` unconditionally overwrites, so a re-applied `.created` destroys every tag and append since).

### Phase 1 — The importer (still Mac-only)

New under `Sources/UnliRiceCore/Sync/`:
- `EventFeed.swift` — `protocol EventFeed`, plus `FeedCursor` wrapping an **opaque** string (byte offset for shards; base64 `CKServerChangeToken` for CloudKit later). ~30 lines, and it is the entire transport-migration insurance policy.
- `ShardFeed.swift` — byte cursor; stop at last complete newline; **stop at first undecodable line** (do not `try?`-skip — with a byte cursor that silently loses everything after); **refuse a shrunk shard** and notify rather than resetting to 0.
- `ShardImporter.swift` — model on `VaultSnapshot.swift:193-216`. Returns `ImportReceipt`.
- `SyncState.swift` — persisted `[shardID: FeedCursor]`. Copy `Agent/RoutineState.swift`'s shape.
- `DeviceIdentity.swift` — stable per-install UUID + label.

Changed: `DataLocation.swift` (add `shardDirectory`/`shardURL`, so nothing can disagree
about filenames — this file already owns that job); `AppStore.swift` (import on launch and
foreground; on `eventsAppended > 0` rebuild then `reload()` — ~0.47s at 4000 notes, only
when a capture actually arrived); `NoticeFactory.swift` (a "captures arrived" notice).

Tests: purge-then-reimport must **not** resurrect; double-import is a no-op; shrink is refused.

### Phase 2 — iOS app, capture-only

New under `Sources/UnliRiceCapture/`: `CaptureApp.swift`, `CaptureView.swift` (one screen:
record button, live partial transcript, pending/sent list — that is the whole UI),
`CaptureStore.swift`, `Recorder.swift` (`AVAudioEngine` → `.m4a` on disk **always, before
transcription**), `Transcriber.swift` (a protocol, same shape as the existing
`SimilarityProvider` seam), `SpeechAnalyzerTranscriber.swift`, `ShardWriter.swift`.

**Title derivation is a hard requirement, not polish.** `Janitor.duplicateProposals`
(`Janitor.swift:167`) compares titles only at ≥0.85 token overlap. Fixed titles like
`"Voice note"` score 1.0 against each other and flood the review queue; empty titles all
become `"Untitled"` (`Projector.swift:42`) and fight over `idsByTitle`. Use the existing
`ImporterText.sanitizeTitle(ImporterText.condense(transcript, limit: 60))`.

**Dictation — `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26), not WhisperKit.** The
30-second cutoff is an `SFSpeechRecognizer` artifact `SpeechAnalyzer` was designed to fix;
`Package.swift`'s zero-dependency stance is deliberate; and `PROJECT_NOTES.md:903-955` is a
measured regret about bundling a model — WhisperKit is the same bet. Cost: iOS 26 floor,
per-locale assets download on demand. **The hedge is recording to file first** — audio
survives a transcription failure, and the protocol lets WhisperKit slot in later.

### Phase 3 — Connect them

- **Path A (first, no portal round trip):** iOS writes its shard to a folder picked via `UIDocumentPickerViewController` in iCloud Drive; the Mac points at the same folder using bookmark machinery it **already has**. Zero new entitlements.
- **Path B (proper):** register `iCloud.com.calmdownoscar.unlirice`, add container entitlements, `NSMetadataQuery` + `startDownloadingUbiquitousItem`. **Do not declare `NSUbiquitousContainers`** — keep shards out of the Files browser.

Two rules to encode: **`events.jsonl` must never live in iCloud** (if the log itself syncs,
`flock` is meaningless and iCloud makes conflict copies of the source of truth — warn in
`SetupView` when the chosen folder is under `~/Library/Mobile Documents/`); and **App
Groups are irrelevant here** — they share between processes on one device, not between Mac
and phone.

### Build config

**`Package.swift` is not the gate** — `UnliRice.xcodeproj` has zero SPM package references;
XcodeGen compiles `Sources/` directly. Update `platforms:` for consistency (additive; does
not move the macOS floor). `project.yml` is what matters: add `deploymentTarget.iOS`, a
duplicated `UnliRiceCoreiOS` static library, and a `UnliRiceCapture` app target
(`TARGETED_DEVICE_FAMILY: "1,2"`, mic + speech usage strings, `DEVELOPMENT_TEAM: 22SNGN5JYD`).

**AppKit inside Core — `#if os(macOS)` guards, do not split the module.** Two files:
`Export/PDFExporter.swift:1` and `Agent/AgentSettings.swift:95,108,119` (`withSecurityScope`
is macOS-only), plus the call site at `Export/ExportService.swift:42`. Guards are ~6 lines;
splitting changes `ExportService`'s signature and cascades to `AppStore`, `MirrorExportView`,
and `ExportServiceTests`.

---

## 3. Deferred by design — seams, not code

**Links need no change, ever.** `outboundLinks`/`backlinks` are derived from body text and
never stored in an event. `[[Title]]` typed on a phone just works.

**Media reuses `RawStore`** with zero schema change — already content-addressed by SHA-256,
dedups by digest, never overwrites. Body carries ``**Audio:** `<digest>-memo.m4a` ``; the
importer copies blobs using `VaultSnapshot.restoreMissingRawFiles`'s shape. Raise
`RawStore.defaultByteLimit` (8MB rejects a one-hour recording) — an `init` parameter, so
config not rewrite.

Extension mechanisms by safety: body marker + blob (safest) → new **optional** `Event` field
(safe) → new `EventKind` case (**unsafe until Phase 0 lands**) → binary in the JSONL (never).

**iPad PencilKit — feasible in exactly one shape.** `PKDrawing.dataRepresentation()` → a
`RawStore` blob, like audio. The *content* must be text: rasterize via `PKDrawing.image(from:)`,
run Vision `VNRecognizeTextRequest` on-device, put recognized text in the body. PencilKit
gives no handwriting-to-text itself (Scribble is text input, not a recognizer). The shape
that does **not** work is strokes-as-content: PencilKit editing is in-place mutation, which
would be the first true mutation in the system and would demand a `.drawingReplaced` kind
and a stroke-folding `Projector`. Under the marker approach each save is a new digest and a
new `.appended` — history preserved by construction. **Phase 4+ at the earliest.**

---

## 4. Packaging — FOUNDER-ONLY, informational, do not implement

**"Bundled with Unli Disk when bought, but also purchasable separately" is an App Store
Bundle** — multiple paid apps sold together at a discount, each still sold on its own.

It is **not** Universal Purchase, which needs one shared bundle ID and makes the apps one
record (foreclosing separate sale) — and which `UnliDisk/PROJECT_NOTES.md:15-17` already
gave up deliberately.

**This requires zero code**, which is the point: `UnliDisk/PROJECT_NOTES.md:251-254` records
that *"paid-up-front needs no code. The Mac target has never contained StoreKit and gates
nothing, so the build already uploaded is correct as-is."* A cross-app entitlement would
require StoreKit in Unli Disk, a `PurchaseStore`, a new product, and a new build —
reintroducing exactly what the 2026-08-03 reversal removed.

Confirm in App Store Connect (rules move; do not take these from this doc): bundles require
all apps **paid**, so a bundled iOS capture app cannot be free; and confirm current rules on
mixing macOS and iOS apps in one bundle.

**Notes-in-Unli-Disk: not before approval, and not as a note editor.** A new build restarts
review, and a notes organizer inside a $14.99 disk cleaner is a Guideline 2.3 metadata-mismatch
risk — a class already flagged in the ClearSpace notes. The coherent version is
**disk analysis, not note-taking**: a read-only finder — *"4,300 markdown files across 12
folders, 340 MB, 900 duplicated"* — the same shape as the existing Applications footprint
analyzer, inherently never-delete because it is read-only, whose call to action is *"Unli
Rice can index these."* Also note that "never delete" inside an app whose purpose is
reclaiming space by deleting needs a **structural** exclusion from every sweep and treemap
surface, not a label.

**Open source alongside a paid iOS app works because Unli Rice is MIT** (`LICENSE`) — MIT is
compatible with App Store distribution and with charging for a binary built from the same
source; GPL would not be. The consequence to accept knowingly: anyone may fork
`UnliRiceCore`, add a capture app, and sell it. In practice the friction makes this unlikely,
and the value is in the Mac app plus the agent ecosystem rather than the event log.

---

## 5. Verification

Every phase is provable before the next starts. No phase depends on unbuilt hardware.

**Section 1, Vault Mode:** run a mirror export; confirm `CLAUDE.md` and `AGENTS.md` appear
at the export root with **live** note counts. Open Claude Code in that folder with the
`unlirice` MCP server **disabled** — the whole point is that it works without it — and
confirm the first reply opens with the acknowledgment. Repeat with a second agent that
reads `AGENTS.md`. Then the negative test: export an empty vault and confirm the agent says
it found no notes rather than claiming context it does not have. Finally, install the
`UserPromptSubmit` hook and confirm the line appears on the *second* and *third* prompts,
not just the first.

**Section 1, receipt:** confirm Trust Center reflects each of the above, and that a session
where the agent read nothing is reported as such.

**Phase 0:** `swift test --filter ShardImportTests`. The backdated-projection test must
**fail before** the `LinkIndex` change and pass after. Confirm all 222 tests still pass.

**Phase 1:** hand-write an `events-test.jsonl` into a scratch folder, point
`UNLIRICE_DATA_PATH` at a throwaway log, import, confirm notes appear via `list_notes` and
that `note_history` shows original timestamps and `device`. Then: re-run (zero appended);
purge one note via `unlirice-agent --purge` and re-run (it must stay gone — the `Trash.purge`
regression); truncate the shard mid-line and confirm the cursor stops before it.

**Phase 2:** in the Simulator, record a capture; confirm the `.m4a` exists on disk *before*
transcription completes and that one well-formed JSON line lands with a transcript-derived title.

**Phase 3:** capture in Airplane Mode, re-enable network, confirm the note appears with its
**capture-time** timestamp, `creator: human`, `device: iPhone`. Confirm five captures do not
trip the janitor's duplicate detector.

**Regression watch:** `ProjectionCacheTests` (the cold-vs-incremental invariant) and the
signed Xcode Release build (the iOS target touches shared `settings.base`).
