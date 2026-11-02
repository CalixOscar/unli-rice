<!-- MEMORY CONTRACT — this file, not the vault, is what binds you.
     memory.md holds CURRENT WORKING STATE ONLY, capped at 32,000 characters
     (~8,000 tokens) and enforced by Scripts/lint-memory.sh in pre-commit.

     * The six fields below are atomic: Status, Task, Files touched, Next step,
       Gotchas, Left by — in that order, no repeats, **Left by:** carries a
       YYYY-MM-DD date. They describe ONE moment in time. Update all six or none;
       changing one in isolation produces a file that contradicts itself in
       adjacent lines, which reads as current and is worse than a stale file.
     * No dated headings. Nothing here is a log. Finished work moves to
       PROJECT_NOTES.md; design detail goes to docs/ and is referenced by path.
     * A claim carries its own evidence or is marked unverified:
       "296 tests, zero failures (verified: swift test 2026-09-02)" or "(unverified)".
     * Checkpoint as you go. Commit and update these fields at every
       meaningfully-complete sub-step, not at the end of the session — a
       usage-limit cutoff ends a session with no warning.
     * If this file and the repo disagree, the repo wins. Check against
       `git log -10` and `git status` before building on anything here.
     * Using the `unlirice` MCP tools rather than reading about them? Read
       AGENTS.md as well — title discipline, tagging, flag-vs-resolve.
-->

# Unli Rice — Working Memory

**Status:** Production Studio source checkpoint on `CalixOscar/Unli-rice-Capture`; coreb0df79b, Macconsentc088ee9. Capture hinge workspace, draft-preserving covers, exclusive deck gestures and consent hosts implemented and reviewed. Root Mac/iOS builds pass; core633tests2skip0fail. Three strict concealed editor accessibility queries remain unresolved; no upload/live migration/release acceptance.
**Task:** Founder says keep going on both apps live, iOS Mac project flipping and Duo folded voice-only/open Studio+To Do. Original Nuptia purple-lantern capture remains absent from installed-store MCP targeted search. Preserve current installed runtime until ready. Source review with Claude authorized and performed for migration/hosts. Finish independent editor AX check, signed updates, real capture receipt/context and release gate.
**Files touched:** CaptureProjectDeck.swift exclusive drag/tap and one semantic button; CaptureStore.swift consent/errors/work serialization; CaptureView.swift presentation/workspace/covers/consent; CaptureStudioStyle.swift private cover; TodoView.swift cover; new CapturePresentation.swift, CaptureVoiceControls.swift, CapturePrivateContentHost.swift. Docs production-studio plan/dialogue, PROJECT_NOTES and memory updated. Terra medium implementation, Astra architecture/read-only, root diff review and own builds. No builder commits/docs or live store access.
**Next step:** Founder async requests pending: sign back into AppStoreConnect Chrome session and close/reopen DeviceHub (CUA capture backend fails). Reconnect Inspector, select synthetic QA app and navigate actual hidden editor projection/VoiceOver. DO NOT change more production privacy code or weaken strict assertions until independent evidence; matched proxy/concrete experiment disproved proxy-only fix. Then final UI/post-mortem/counters/signed builds and actual saved capture→Mac receipt→fresh project_context. Prelaunch founder gate before public review. Both installed apps remain unchanged.
**Gotchas:** Root final Capture build /tmp/unlirice-production-capture-root-final-local.log passed; Mac /tmp/unlirice-production-mac-root-b4d.log passed. Latest Q5 strict6/9pass: deck2direction+tap/selection, closedvoice/lockedclosed/ordinaryphone/largetype/syntheticstates;3 editor.exists failures. Separate3 native/draft diagnostics pass2folds/Cancel/Save; iPadordinary1/1pass. Native identity/sentinel retained, actual ancestor hidden+AXhidden/interactionsfalse, firstResponderfalse/keyboardabsent; no actual VoiceOver verdict. ABproxy/concrete identicalqueryfail; ordinarySwiftUI hiddenTextEditor alsoqueryable/hittabletrue, plainUIKitvanishes; hiddenflag is @Published, no missing observation bug. Artifacts /tmp/unlirice-production-ui-qa/{attachments-b2e,native-b2e,attachments-ab,native-ab,result-ab.xcresult,ab.log}. Root real public-init DeviceHub callbacks coldclosedvoice, actualOpen Studio+Todo, presentedemptyeditor closed→voice/keyboardhidden then reopened restored, partialopenworkspace, finalclosedvoice. No physicalmicproof. Later Inspector setup synthetic draft Inspector draft sentinel, CaptureKeyboardon, WindowFill attempted; DeviceHub now ScreenCaptureKit -3812 invalid parameter even reset/rebind; no pointer traversal achieved. Inspector otherapp accessible, CUA runtime reset bindings. ASCauthFAILED; Capture latest1.3(9) read just before expiry, Maclatest1.5(12) prioronly so recheck. Installed MacProduction vs v2Dev binding, cableCaptureDevownlink unchanged. Never alternate store/data override, no account clipboard/fullphonecorpus exports (auto-review denied, no bypass). Migration explicit GUI-only, sameown-token +freshProduction identity, retainedprivateverified/fsynced snapshots, oldevents/cursors/cloudfiles preserved. Macunconfirmedpaneclose cancels; confirmedworkcanfinish. Never ship pre-B7archives.
**To-dos:** none filed/closed this checkpoint. Existing physical acceptance BBC01BEE-FE38-4D53-9999-59422F498AD8 remains open; other todos out of scope. Installed MCP connected, Wiki context read, latestpurplelanternsearch empty. Open work stays in this current memory, no handoff note without a deferred item.
**Left by:** codex 2026-11-02 (Capture source checkpoint; AX and realcapture/release gates remain open, external reconnects pending)

## Earlier branch follow-ups

The previous session's handoff (not revalidated in this session) left: restart Claude sessions for bridge changes; the older shipped-guardrails post-mortem; founder decision on pushing/merging chore/plan-high-build-low and its relationship with local main; committing vault changes; first two builder-model observations; and watching the sidebar before a release. These are separate from Garden and remain deferred.

## Build and release reference

**Every bridge run is told to run the project's build/tests**, even a
one-line brief; a cheap model will try. Keep briefs explicit about what *not* to do.
**The bridge prompt says "implement all tasks" in the file it writes**, so a review
brief must say "write one file, change nothing else". The bridge now refuses a missing
`planFileName` or one outside `docs/`. **A builder's pasted test output is not evidence:** `builder-light` misnamed a case in
its pasted smoke output on 2026-10-17. Rerun it yourself. **The bridge smoke test takes about a minute** (four 2 s timeouts run to
their 10 s / 15 s cleanup deadlines), and it reads the real `~/.codex/build*.config.toml`. **Codex 0.163 reads a profile only from `~/.codex/<name>.config.toml`**;
`[profiles.*]` in `config.toml` is ignored, and `-p` works only on runtime commands
(`exec`, not `doctor`). **Build with `--scratch-path /tmp/unlirice-spm-build`.** The in-tree
`.build` fails codesign ("resource fork, Finder information, or similar detritus") in
this iCloud folder; `Scripts/make-app.sh` (release) still works.
**A development-signed build cannot open the App Store build's app group container**,
so the `dist/` app shows "The House Rules state file is unavailable" and cannot see the
real vault, and the `unlirice` MCP reads the App Store copy's data, not the build under
test. To test UI that writes, run the unsigned debug binary against a throwaway vault:
`UNLIRICE_DATA_PATH=<scratch>/events.jsonl /tmp/unlirice-spm-build/debug/UnliRiceApp`.
The House Rules gallery is the sidebar row "What your AI should always do". The editable
draft is Setup › AI Tools → House Rules → Edit (`ConnectView.swift`); the gallery preview is read-only.
Built-in presets cannot be edited, so edits live in `draftText`, never in
`customPresets`. The app is sandboxed: `Process`/`NSTask` is unavailable, so git
state is read by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/`
directly, and every "fix" the UI offers is copied text, never an action. Do
NOT pass `.skipsHiddenFiles` to an enumerator under `.git` — it is itself
hidden and yields nothing. Security-scoped bookmarks are bound to the signing
identity, so re-signing invalidates every folder grant. **Adding a file under
`Sources/` requires `xcodegen generate`** — `swift test` globs sources and
passes while Xcode fails; `.xcodeproj` is gitignored so the regeneration is
local-only and never arrives via `git pull`. **App Store Connect can be ahead
of `project.yml`:** before this session's bump, ASC's TestFlight already had
Capture build **5** validated (uploaded 2026-08-13) while `project.yml` still
said `CURRENT_PROJECT_VERSION "4"` for both targets — something incremented
and uploaded a Capture build without committing the number back. Check ASC's
actual last-uploaded build per target before ever setting
`CURRENT_PROJECT_VERSION`; don't trust `project.yml` alone. `/Applications/Unli
Rice.app` is the **App Store install** (`_MASReceipt`, was v1.1) — the shipped
product, not a stale build; `dist/` is the local one. The eight Xcode schemes
are distinct targets from `project.yml`, not duplicate apps. `deleteCapture`
purges `events.jsonl` via `TrashService`, so "no destructive delete" is true of
the Mac's note tools but **not** of the phone. `Sources/UnliRiceCapture/
Resources/Assets 2.xcassets` is still a stray duplicate, left for the founder
to delete. **This file's Next step went stale and cost real time:** it still
said "commit the `project.yml` bump" after `92be76e` had committed it, and a
session was spent re-deriving that. Check `git log -10` before acting on
anything here. macOS screenshot filenames contain a narrow no-break space
(U+202F) before `AM`/`PM`, so a normal space in a shell path silently fails as
"No such file" — glob them (`*10.32.22*`) rather than typing the name. Plans dated before
2026-10-16 say "the swarm builds it": read that as the planner's builder models.
The `builder` subagents load only when Claude Code starts in the repo root.

## Open hypotheses

<!-- Live guesses about a current problem, and what would confirm or kill each one.
     Delete an entry the moment it is settled — the answer belongs in
     PROJECT_NOTES.md's Decisions Log, not here. -->

- Sidebar pane-switching lag ("click it four times"): hypothesized cause is the
  three blurred `GeometryReader` circles re-rendering on every `@Published`
  write from `closeAllPanes()`. The fix for exactly that is now **applied**
  (`51ffb83`, `BackgroundBlobs` + `.drawingGroup()`), so the hypothesis is
  testable but **still untested** — nobody has watched the running app. Confirms
  if single clicks now land reliably; kills if the lag persists, which points at
  the 17 `@Published` writes themselves rather than the cost of each redraw.
  Delete this entry once someone has actually clicked the sidebar.

## Active constraints

<!-- Things that would change today's design decisions and are not obvious from
     the code. Not project background — that is PROJECT_NOTES.md. -->

- **Locked architecture decisions are not up for revisiting** without an explicit founder
  decision: the append-only JSON-Lines event log is the source of truth, `Note` is a rebuilt
  projection, there is no destructive delete (only reversible `archive_note`), and
  structural changes are propose-only — the janitor may tag and flag but never apply. See
  `PROJECT_NOTES.md` § "Locked-in architecture decisions".
- The app is shipped on the Mac App Store, so anything on this branch is a submission
  candidate and the pre-launch gate (`_AI Context/07_Prelaunch_Post_Mortem.md`) applies
  before it goes out.
- **The public guide and the app's own copy are now expected to agree.** The guide at
  `calmdownoscar.com/unlirice/user_guide.html` was audited against the code, so a string
  changed in the app without changing the guide re-opens the divergence that
  `docs/PLAN-copy-that-overstates.md` exists to close. Changing either means checking the
  other.
- **The Mirror folder is bidirectional, in one narrow way.** Exported files are
  regenerated copies and edits to them are lost, but `Notes for Unli Rice/` is a drop box
  that `RoutineDriver` ingests on every tick (`RoutineDriver.swift:164`). "The folder is
  read-only" is wrong; "a tool can add a note but not edit one" is right.
- **The widget build (B1–B6) had no swarm and no Codex review of the code**, by founder
  instruction on 2026-09-25 ("just build it"). The plan itself was pre-mortemed; the
  implementation was checked only by its author's tests and builds.
- `docs/PLAN-note-contract.md` is a settled stage-2 plan that has not been built yet.
- `docs/IOS_CAPTURE_RELEASE.md` §1.6 ("Decide iPad, deliberately") is **resolved**:
  keep `TARGETED_DEVICE_FAMILY: "1,2"`. The doc itself still poses it as an open
  question with a "drop to 1" recommendation — that text is now stale and should be
  updated to match, but hasn't been edited yet.
- The AI-todo feature (`docs/PLAN-ai-todo-actions.md`) is built and independently
  verified, but it still went to the swarm without a Codex pre-mortem. Verification
  caught no bugs, but it did not re-litigate the design calls in the plan's §5 — those
  are still unreviewed judgement, not settled fact, even though the code behind them
  works. The hook's Python fold of `events.jsonl` duplicates `Projector.swift` in a
  second language; the agreement test (`StudioTodoTests.swift`) is real and passes, but
  it will not catch a *new* `EventKind` added later without someone remembering to
  extend `KNOWN_EVENT_KINDS` in the Python file too.
