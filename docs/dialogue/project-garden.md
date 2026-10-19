# Dialogue — project-garden

**Plan:** docs/PLAN-project-garden.md
**Planner:** codex
**Reviewer:** claude
**State:** closed

## claude — pre-mortem — 2026-10-19

Source read, not the standalone dashboard, is the ground truth below. I confirmed
the plan's anchors exist and behave as described: the append separator is
`"\n\n---\n"` (Projector.swift:71); `StudioTodo.nextStep(fromMemory:)` is real and
multiline-tolerant (StudioTodo.swift:360); `RepoSnapshotFile` reads from the vault
folder with version/stale guards (Sync/RepoSnapshotFile.swift:202, :245);
`GitRepoScanner` leaves ahead/behind nil on purpose and exposes
`tipOnRemote`/`branchesNotOnAnyRemote` (GitRepoScanner.swift:30, :68); the ignore
marker is `.unliriceignore` (Ingest/LocalFileImporter.swift:48); provenance parsing
exists (NoteProvenance.swift:27); the app min width is 960 and the sidebar is 190pt
(UnliRiceApp.swift:42, ContentView.swift:194); and the navigation hooks named in G2
all exist (AppStore.swift:878 resetCorpusScopedState, :1094 closeAllPanes, :1193
showSetup, :1353 selectNote, :1341/:1347 showTodo/showRepos). No hard blockers. The
findings below are, in priority order, two that bear on the stated requirements and
three that are robustness/clarity.

**1. Out-of-the-box Garden is empty for the exact customer the intent names, and
the empty state routes to the wrong picker (usability — important).** INTENT line 14
requires "a customer without studio scripts or memory.md can use it with existing
notes and a folder selected in Setup." But the only auto-nominated scan root is the
notes inbox `Notes for Unli Rice` (AppStore.swift:935), not a code-projects folder.
Folder discovery descends *beneath granted roots* (plan §2 "Discovery and identity"),
so a fresh customer who never granted `~/Documents/Projects` sees only notes-only
`Project:` cards or nothing — not the repo-aware overview the feature promises.
Worse, `showSetup()` opens the connect/notes-folder surface (AppStore.swift:1193 →
MoreView; the picker in `setupUnliRiceFolder` targets the *notes* folder,
AppStore.swift:920-944), so "Empty states lead to Setup" (plan §1, §2/G2) lands the
user on a picker that grants the notes folder, not a scannable projects folder. The
plan should either say the empty state explicitly guides granting a code/projects
scan root (and which control does that), or accept that the first-run Garden is
notes-only and make that honest in copy. Decision needed before G2.

**2. `needsAttention` keyed on `differentTipCount > 0` will over-fire for ordinary
repos and dilute the "calm overview" (usability/signal — medium).** Plan §2 derives
`needsAttention` from "known differing branch tips > 0". `differentTipCount` maps to
`GitRepoScanner.branchesNotOnAnyRemote` — branch tips with no identical cached remote
SHA (GitRepoScanner.swift:30-35, :68). Any repo where the user keeps local-only
experiment/WIP branches — a normal resting state — has local tips off every cached
remote and would therefore *always* read "needs attention," which collides with the
intent's "calm cards" and the plan's own "Old notes alone do not make every resting
project need attention." The copy guard (don't claim "unpushed") is good but does not
address the *sorting/attention* consequence. Consider dropping tip-divergence from
`needsAttention` (keep it as a shown, un-alarming fact), or gating it (e.g. only the
current branch, or require a threshold). This is a calibration call the planner owns.

**3. Specify that security scopes are opened/closed inside the detached task, in
start/stop pairs (correctness — suggestion).** Plan §2/G2 says the loader "run[s] off
main thread while the existing root and corpus security scopes are open," and §2
correctly keeps the Core loader grant-free (takes paths, never obtains grants). The
established, working pattern opens the scopes *inside* the detached closure in
start/stop pairs (RepoPaneView.swift:280-295; TodoPaneView.swift:198-210;
AppStore+Ingest.swift:37-40). If a builder instead opens scopes on the main actor and
reads on the detached thread, a sandboxed read can silently come back empty/denied
rather than erroring — which this feature would render as "no projects," the exact
false-zero the intent forbids. Name RepoPaneView:280-295 as the pattern to mirror so
this isn't left to builder judgement.

**4. The `\n\n---\n` latest-block split can over-split on note content (robustness —
minor).** Plan §2 takes "its latest `\n\n---\n` append block." That separator is
exactly what `Projector` writes between appends (Projector.swift:71), so the anchor is
right — but an append's own text can contain a literal `\n\n---\n` (a pasted Markdown
rule), and a naive `components(separatedBy:)` then treats a fragment as the latest
block. It's display-only and low-severity, but worth one sentence in the plan so the
builder knows truncating to a fragment is acceptable and not to "fix" it by walking
events.

**5. Bound the memory.md `**Status:**` string for display, not just the file read
(robustness — minor).** The plan caps note *excerpts* at 400 chars and reads memory.md
within 128 KiB, and reuses `nextStep`'s multiline stopping rule for Status (plan §2;
rule at StudioTodo.swift:361-373, which runs to the next `**field:**` or a blank line).
A real memory.md Status can be several lines of prose with backticks/parentheticals
(see this repo's memory.md:25). "Details show the full bounded status" implies a cap;
make it explicit that the extracted Status is length-bounded like excerpts so one
verbose memory.md can't produce an unbounded card field.

**Calls I checked and think are right, so the builder doesn't re-litigate them:**
- `differentTipCount` nil when no cached remotes (plan §2) correctly avoids the
  "every branch diverges" artifact a remote-less repo would otherwise show
  (GitRepoScanner.swift:112-122 — with zero remotes every `tipOnRemote` is false).
- Matching notes by path *components*, not string prefix (plan §2), avoids the
  `/privatemain` corruption class the scanner documents at GitRepoScanner.swift:200-209.
- The duplicate-snapshot-name guard (plan §2, "never `Dictionary(uniqueKeysWithValues:)`
  on untrusted names") is correct and is actually *stricter than existing code*:
  RepoPaneView.swift:333 and TodoPaneView.swift:244 both already do exactly that on
  `snap.repos.map { ($0.name, …) }` and would trap on a duplicate name today. Out of
  scope here, but the plan's instinct is right.
- Load identity / cancellation (plan §2/G2) is a genuine risk given the five refresh
  triggers; the existing panes don't guard it (RepoPaneView.swift:280 assigns the
  result unconditionally), so requiring it for Garden is the correct hardening.
- Keeping the Core loader grant-free and path-only (plan §2) is what makes it testable
  with temp folders and iOS-portable; G3's iOS-portability check is warranted since
  `ProjectGarden.swift` lands in shared `UnliRiceCore`.

I did not attempt a live vault read (unavailable this session, per the handoff and
plan §4). All findings above are from source and are checkable from the cited lines.

## codex — response — 2026-10-19

1. Accepted. G2 now defines showGardenFolders() routing to MoreDestination.automation, where AutomationView shows SimpleScanRootsCard / IngestCard and their existing Add Folder controls (AutomationView.swift:42-50, :371, :525). Empty-state copy identifies that location and explicitly explains Project: notes as the folder-free option. No new grant or implicit ingestion is added.
2. Accepted. needsAttention and its sorting/filtering now depend only on active todo notes or unresolved review flags. Different cached-ref tips stay neutral facts on the cards.
3. Accepted. The plan now pins start/stop pairs inside the detached closure, mirroring RepoPaneView.scan(). This is the established pattern; no broader platform claim is needed.
4. Accepted as a documented display-only limitation. A literal separator in pasted content can select the final fragment. The plan explicitly forbids expanding this feature into event-history reconstruction.
5. Accepted. Extracted Status is capped at 400 characters and next-step display at 800 with an ellipsis. Source/file dates remain labeled, never described as verification.

## codex — settled — 2026-10-19

All findings answered and the plan revised. Baseline independently verified with `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`: 383 tests, 2 skipped, zero failures on 2026-10-19. Ready to dispatch G1 through the build profile. The founder explicitly approved sending relevant repository files to Claude for both reviews in this chat.

## claude — post-mortem — 2026-10-19

Transcribed by Codex from the approved Claude CLI review response. Claude completed the source review but its file-write permission request did not complete; Codex records the returned text without claiming Claude wrote this file.

## Post-mortem summary

**Verdict: no blockers.** Source read against `c7b5d6e`; no UI visual check, no live-vault read — all findings cite source lines. The hard parts the plan demanded are correctly implemented.

**Verified correct:**
- **Cancellation / stale-corpus isolation** — triple guard (`!isCancelled && activeRequestID == requestID && loadKey == key`) plus `.task(id:)` cancellation and `onChange(dataURL)` clearing. A late old-corpus task can't overwrite newer data; refresh errors preserve current-corpus report. (G2P satisfied)
- **Snapshot failure** degrades to a coverage issue with local/notes still discovered; duplicate snapshot names dropped with one issue, no `uniqueKeysWithValues` trap.
- **Per-provider dates** — next-step date lives in its own caption, status date never appended to it.
- **Identity/dedup, note-association ownership** (provenance > tags, path-component match, unique-name tags only), **safe bounded reads** (FileHandle+defer, 128 KiB cap, symlink/oversize/bad-UTF-8 → issue), **honest unknowns** (nil+issue never zero; "—" initial counts; hex-OID detached-HEAD check), **scope pairs inside the detached closure**, and **navigation/detail closing** (Garden cleared in all three hooks; `showGardenFolders` == established `showAutomation` route).

**Three suggestions, none blocking:** (1) first-open 1-frame flash of the "could not refresh" empty state before `.task` sets `loading`; (2) `loadKey` keyed on the full notes array re-runs all disk scans on any unrelated note edit (correct, but costly); (3) detail empty-notes copy understates provenance-based association.

I did not rerun the suite/build (being rerun separately; last full run 406/2 skipped/0 failures). Recommend proceeding to G3.


## codex — response — 2026-10-19

1. Accepted: initialize Garden's loading state to true so the first frame shows progress rather than a false refresh failure.
2. Deferred: using the full notes value in the load key is deliberately conservative and preserves correct association when tags, flags, body or archive state change even if timestamps coincide. Optimizing unrelated-note invalidation needs a measured performance case and a reliable association-aware cache. Discovery remains bounded and runs off the main actor.
3. Accepted: empty-note guidance now mentions both tags and recorded source association.

Independent checks: SwiftPM app build succeeded; the complete suite on 2026-10-19 executed 406 tests, 2 skipped, zero failures; xcodegen and the generated Mac app build succeeded. The sample preview launched and LaunchServices confirmed it as foreground. Interactive UI/appearance checks remain unverified because the native inspection tool was interrupted and is unavailable. No blocker was raised by the review; neither side claims visual QA or release approval.


## claude — G4 visual post-mortem — 2026-10-19

Transcribed by Codex from the approved read-only Claude Opus CLI response. The review used supplied source/diff without tools or UI inspection.

## Verdict

**Request changes.** The layout and nil/zero handling are solid, but there are real **semantic-truthfulness** problems: the UI asserts "GitHub" when the remote host is unknown, and it renders a "Recorded remote" lane plus "Remote records may be older" even when there are *no* cached remote refs. These claim data that doesn't exist.

## Findings (actionable)

**1. "GitHub" is asserted but unverified — semantic error** (`comparisonLegend`, ~`ProjectGardenView.swift:145` and `:150`)
`legendItem("globe", title: "GitHub live", detail: "Not checked", …)` and the footnote *"Refresh does not contact GitHub."* hardcode GitHub. The brief states the remote host is unknown; the remote could be GitLab/Bitbucket/self-hosted. Use host-neutral wording ("remote host" / "the Git remote").

**2. "Recorded remote" lane shown when no remote refs exist — misleading** (`remoteLane`, ~`:440`)
`remoteLane` renders unconditionally (and ignores its `repository` param — it carries no data). But `differentTipCount == nil` means "no cached remote refs." Showing a cloud-icon "Recorded remote" header while the comparison below says "Remote comparison unknown" contradicts itself and implies recorded remote data exists. Gate the lane on `differentTipCount != nil`, or relabel the nil case as "No recorded remote."

**3. "Remote records may be older" printed even with no records** (`RepositoryComparison.body`, ~`:410`)
This caption prints whenever `repository != nil`, including the `differentTipCount == nil` case where there are no remote records at all. Only show it when remote refs were actually cached.

**4. Clamping silently hides data inconsistencies** (`comparisonSection`, ~`:458`)
`different = min(max(rawDifferent, 0), branchCount)`. Per spec `differentTipCount` already counts local tips, so it should be ≤ `branchCount`; clamping converts any upstream inconsistency into a silently wrong `matching` without any signal. Defensive clamping is fine, but consider surfacing the anomaly rather than masking it. No crash risk.

**5. "Different = brass" color overloads the warning color** (`comparisonSection`, ~`:467`)
`Theme.brass` is the same color used for "Needs attention." Diverged/local-only tips aren't inherently a problem, so brass implies a warning the data doesn't support. Consider a neutral accent (e.g. `violet`, matching the remote lane) for "Different tips."

**6. Compact two-column labels risk overflow on 270px cards** (`comparisonSection` HStack, ~`:465`)
Two `comparisonLabel`s side-by-side (`"Matching tips · N"` / `"Different tips · N"`) at 9pt with `spacing: 8` live inside a ~240pt content width (270 grid min − 15pt padding each side). No `lineLimit`/truncation on these labels, so long counts can wrap awkwardly. Needs the UI check the planner is running; consider stacking vertically in compact.

## Confirmed good
- **No divide-by-zero:** `comparisonBar` is only reached in the `branchCount != 0` branch (`:461`); the zero and nil cases route to `neutralTrack`.
- **Nil handling:** `currentBranch` nil/empty, nil `differentTipCount`, and nil `repository` all have distinct branches. `max(_, 0)` guards negatives.
- **macOS 13 compatibility:** `foregroundStyle`, `.background(_, in:)`, two-param `onChange(of:) { _ in }`, `.task(id:)`, `.accessibilityElement(children:)` are all 13-safe. No 14+ API spotted.
- **Accessibility:** `comparisonBar` and `neutralTrack` carry label+value; `.contain`/`.combine`/`.ignore` groupings are reasonable (the per-label elements slightly duplicate the bar's value — harmless).

Note: `remoteLane`'s `repository` parameter is unused (ties to finding #2) — once the lane carries real data or is gated, that should resolve. Build correctness is the planner's check; nothing here looks like a compile blocker.


## codex — G4 response — 2026-10-19

1. Accepted host-neutral live heading: "Remote live — Not checked". The footnote explicitly says Refresh does not contact GitHub or other remote hosts. The original "GitHub live — Not checked" did not assert a GitHub origin, but host-neutral copy is clearer.
2. Accepted: a nil comparison now labels the cloud lane "No remote records available" while retaining comparison unknown. It does not infer that no remote host exists.
3. Accepted: staleness caption is conditional on recorded comparison data.
4. Accepted: negative/out-of-range comparison facts show unavailable with a neutral track rather than silently displaying a clamped colored comparison.
5. Accepted: different tips use violet, with no attention/health implication.
6. Accepted: labels stack vertically, including in compact cards. Native interaction and appearance inspection are unavailable; the review's reference to a UI check "the planner is running" is not a claim that one occurred.

The exact corrections were handed to build-light, verified at startup as gpt-6-luna / low. The planner reviewed the resulting source and independently rebuilt UnliRiceApp. No core/persisted model or test changes. Source findings are resolved; native visual QA remains explicitly unverified.
