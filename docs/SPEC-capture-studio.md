# SPEC — Capture Studio

**Intent:** docs/intent/INTENT-010-capture-studio.md
**Status:** approved 2026-11-01 with intent; pre-mortem waived by founder
**Baseline:** 6e25c9a, branch CalixOscar/Unli-rice-Capture

| ID | Required behavior | Verification |
|---|---|---|
| UI1 | iOS uses StudioPalette for background, surfaces, type colors and project/branch/note accents; project sleeves mirror the Mac's visual hierarchy. Glass belongs to controls, content stays solid. | Simulator visual review in light/dark modes against Mac Studio. |
| UI2 | Studio exposes Projects, Branches and Notes, with one-tap recording available and a visible active-recording control. Narrow phones stack decks; iPad uses available width. | Record, navigate, return, pause, resume and stop; check no second recorder or lost recording. |
| UI3 | Project detail presents status, next step, to-dos, captures, branch evidence and available build-stage evidence. Missing stage evidence reads unknown. | Fixtures for complete, partial, stale and unreadable data. |
| UI4 | Existing app lock covers every new screen and app-switcher snapshot. Controls support VoiceOver, Dynamic Type and Reduce Motion/Transparency; no swipe-only operation. | Locked foreground/background and accessibility walkthrough. |
| SY1 | Mac writes a versioned, atomic project overview into the explicitly configured shared folder. Existing repos.json remains compatible and untouched by the new producer. | Round-trip, interrupted write, unsupported version and legacy repos.json tests. |
| SY2 | Overview names its producer and publication time; source observation times remain distinct. Missing data cannot appear as zero or success. Phone refresh only rereads shared files. | Stale/missing/unreadable fixtures and offline device walkthrough. |
| SY3 | Saved locally, published to the shared folder and received by the Mac are distinct claims. Only receipt evidence can establish Mac receipt. Failed sync remains visible and retryable without creating a second capture. | Fault-injection tests and airplane-mode recovery walkthrough. |
| CP1 | New voice and typed captures carry stable capture identity and pending state through ordinary note events. Legacy phone notes stay readable; no automatic retagging of the corpus. | Create/import/replay tests; old capture fixtures. |
| CP2 | Project assignment uses the exact project tag convention. Unassigned and ambiguous captures stay visible without an inferred association. | Case, spaces, unknown tab and duplicate-name tests. |
| CP3 | Reading, sharing or requesting AI help never clears pending state. An explicit handled/set-aside action is reversible and retains the transcript. | Replay/import and action tests. |
| CP4 | Add to to-dos uses the existing todo namespace, preserves the original capture and is idempotent for repeated taps. It does not invent a completed task or duplicate note. | Repeated tap, partial write, sync/replay tests. |
| CP5 | Act with AI produces a handoff containing capture ID, transcript, project and source freshness; available through native share/copy on iOS. No automatic code execution. | Payload tests and manual share/copy. |
| AI1 | A shared read-only context service returns project status, next step, to-dos, pending captures and repository evidence; an all-project overview also includes unassigned captures. | Pure-service tests with project and all-project requests. |
| AI2 | MCP initialization directs both Codex and Claude to pending captures and the context tool. A tool call refreshes context during an existing session. Delivery is distinguished from model compliance. | JSON-RPC transcript tests plus real new and existing Codex/Claude sessions. |
| AI3 | The Claude prompt hook uses the same association/state rules. It surfaces bounded relevant capture pointers as well as to-dos, without clearing state. Other projects' captures are not attributed to the current repo. | Hook/Swift fixture agreement tests. |
| AI4 | Transcript text is presented as user content, never promoted into connector instructions; context and handoff sizes are bounded with explicit truncation and retrieval by ID. | Instruction-like transcript and oversized-input tests. |
| GT1 | iOS shows local branch count/current branch and separate recorded-remote matching/different-tip evidence with text labels, not color alone. | Same fixture rendered on Mac and phone. |
| GT2 | “Remote live: not checked” and source age are visible; no fetch or GitHub login is implied. A branch tip absent from recorded remote refs is described exactly that way. Ahead/behind versus trunk is never labeled ahead/behind GitHub. | No-remote, stale, matching, differing and unknown fixtures; copy review. |
| QA1 | Core tests, MCP build, Mac build and iOS Simulator build pass after Xcode regeneration. Both platforms' cross-device journey and compatibility limits are recorded separately from compilation. | Commands and manual acceptance record in plan. |

No release numbers or entitlements change. New storage formats and context behavior
require the repository's tier-2 review before implementation.
