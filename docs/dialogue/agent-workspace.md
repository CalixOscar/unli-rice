# Dialogue — agent-workspace

**Plan:** docs/PLAN-agent-workspace.md
**Planner:** codex
**Reviewer:** claude
**State:** open

## claude — pre-mortem — 2026-11-03

**Preliminary / discovery only.** INTENT-013 is a draft (`Intent read: not run`), the spec is
proposed, and the plan has no runnable steps. This turn can't be the settled pre-mortem that
AGENTS.md § "The order" step 6 requires. A real pre-mortem has to come after the founder approves
the intent. I checked repo facts against `51a75b7`. Anything about a provider marked
*unverified* is my own understanding and was not checked in this pass.

### P0 — decide these before any further design

**1. Gate gap (a process finding, not a blocker for this critique).** The intent is unapproved, so
steps 2–6 are incomplete. The plan also skips something the guardrails require for tier 2: a
checklist with each step labelled `build`/`build-light`/`planner`. Tickets 1–5 carry no labels.
*Remedy:* once the founder approves, rewrite §2 as a labelled checklist and ask for a full
pre-mortem then. This turn doesn't count as that one.

**2. The execution boundary is already mostly answered by the repo, and the answer works against Tickets 4–5.**
Every Mac target is sandboxed: `UnliRice.entitlements`, `UnliRiceHelper.entitlements` and
`UnliRiceMCP.entitlements` all carry `com.apple.security.app-sandbox`. memory.md records that
`Process`/`NSTask` is unavailable, that Git is read by parsing `.git` directly, and that "every fix
the UI offers is copied text, never an action". Documented Apple behaviour: a sandboxed app's child
processes inherit its sandbox, so a Mac App Store build can't launch the user's installed
`claude`/`codex` CLIs against arbitrary checkouts. A helper in the bundle doesn't change this,
because the helper is sandboxed too. So "open/resume/send" in AW-04/06 and the run lifecycle in
Ticket 4 would need either (a) a separately distributed Developer ID companion outside the Mac App
Store (precedent: Unli Disk ships without StoreKit, see MEMORY), or (b) no dispatch at all.
*Remedy:* make this the first founder decision, before Ticket 1 research. The plan treats AW-11 as
a later spike. In practice it decides whether AW-06/07/08 exist at all.

**3. The cheapest version that fits the sandbox is read-only, and it covers most of the founder's vision.**
Of the founder's pain points, these are observation problems: the sidebar losing recent chats,
"Done" shown while the agent is asking a question, paused projects prioritized by hand, and
branches made prominent. None of them needs dispatch. *Proposed v1:* the existing project tiles
gain a per-project session list built from the providers' own files. Each row shows: branch at
session time vs. branch now (with the time of each observation), last activity, a "your turn?"
flag (a labelled heuristic), and a queue order the user sets. The only action is "copy resume
command / open folder", matching the existing copied-text pattern. That removes the lease, the run
ledger, duplicate execution and replicated execution from v1. AW-07/08 move to the companion track
if the founder picks it.

### P1 — gaps in the state model and source of truth

**4. "Waiting for me" has no structured provider signal in the files.** Repo fact:
`ClaudeSessionImporter.swift:10` reads `~/.claude/projects/<slug>/<uuid>.jsonl`, through a granted
folder passed by `RoutineDriver.swift:188`. A transcript shows that a turn ended. It doesn't show
that the assistant asked a question. *Unverified:* Claude Code hooks (`Stop`, `Notification`) and
Codex's `notify` setting can report turn-end or waiting-for-input explicitly. Antigravity's
interface is unknown. But hooks change the user's provider configuration, which conflicts with
"keep manually configured bridges / no overwritten configuration". *Remedy:* a three-level
vocabulary. **Turn ended** is a provider fact. **Likely asking you** is a heuristic on the final
assistant message and is always labelled as one. **Done** happens only when the user accepts. Hook
installation, if it's ever offered, is opt-in, the user does it, and it's reversible. AW-03 should
say Done never comes from provider evidence at all, rather than "never becomes Done merely because
output paused".

**5. Usage and reset evidence is weaker than AW-09 assumes.** *Unverified:* there's no documented
API for remaining Claude or ChatGPT subscription usage. Limit notices appear as message text in
transcripts, and Codex rollout files may carry rate-limit fields. Both are undocumented formats
that change between versions. *Remedy:* "Paused: limit" only when a limit notice is actually
observed, with the source line quoted. Show a reset time only if it was parsed, labelled
"reported by <provider> at <time>". Otherwise show "unknown". The useful part, prioritizing paused
work, needs no provider evidence: it's a list the user orders. Build that first and treat any
usage figures as optional extras.

**6. Checkout identity is underspecified, and this repo is a live counter-example.** This
workspace sits at `~/orca/workspaces/Unli Rice/Unli-rice-Capture`, while the guardrails put
projects at `~/Documents/Projects/<Name>`. The same product has two folder identities.
`ClaudeSessionImporter.swift:61` notes that each worktree gets its own `~/.claude/projects`
directory. *Unverified:* Claude transcript lines record `cwd` and `gitBranch` per message.
*Remedy:* key a checkout by its resolved git common dir plus its worktree gitdir, never by folder
name or chat title. Record branch-at-session and branch-now as two separate observations. A
missing worktree is "gone or not granted", never "lost".

**7. Security-scoped grants won't keep up with Orca-style worktrees.** memory.md says bookmarks
are bound to the signing identity and are lost on re-signing. Orca creates new worktree folders
all the time, and each new folder outside a granted parent needs a new grant. *Remedy:* the spec
should require granting one parent folder (e.g. `~/orca/workspaces`) plus `~/.claude/projects`
and `~/.codex/sessions`, with a visible "not granted" state for anything else. Test it with a
re-signed build.

**8. A run ledger conflicts with the locked architecture unless it's defined as a projection.**
memory.md § Active constraints: the append-only event log is the source of truth, and `Note` is a
rebuilt projection. The plan proposes a "local run ledger" and "iCloud display summaries"
without saying whether they're events, a separate store, or a cache. *Remedy:* for read-only v1,
session observations are a rebuildable local cache derived from provider files. They're never
written to `events.jsonl` and never synced. The founder's queue order is the only new persisted
state, and it needs its own explicit decision about whether it's an event.

### P1 — privacy, permissions and context

**9. Transcripts are the most sensitive data the app would touch.** The importer already ingests
Claude sessions into the note corpus. A session overview mustn't widen that: pasted secrets, other
projects' paths and customer text all live in transcripts. *Remedy:* AW-05 should add that the
overview stores metadata only (ids, times, cwd, branch, role of the last turn, a ≤N-character
preview generated locally on demand). No transcript body goes into the event log, iCloud, MCP
output or logs.

**10. Being faithful to provider permissions means never presenting an approval Unli Rice
didn't see.** Pending permission prompts live in the provider's terminal or app, and Unli Rice
can't answer them (it can't launch processes). *Remedy:* show "provider is waiting for an approval
in <app>" only when it's observed, offer "open" and nothing more, and never infer or summarize what
was granted.

**11. Shared-context provenance needs a freshness mechanism, and customers need a source.**
Guardrails live in the vault, outside the repo, and a default-install customer has no vault. The
guardrails say: build for default settings. *Remedy:* use the existing House Rules
(`ConnectView.swift`, per memory.md) as the guardrail source a customer has. A context receipt
records path, content hash and observation time, and it's stale when the hash changes. Context
reaches the agent the way it does today, through the existing `project_context` MCP pull. That
keeps attribution and scope in one already-shipped channel. *Unverified:* whether MCP reads are
logged per caller today.

**12. Jev and GitHub MCP are tools agents use, not sessions to orchestrate.** Putting them on the
initial tool list pulls the scope toward an Orca clone. *Remedy:* v1 shows at most which MCP
servers are configured for each provider (read-only, if the config file is granted). It never
edits that config.

### P2 — the experiment and failure cases

**13. The paper experiment tests navigation but not feasibility, and "10 seconds" has no
baseline.** *Remedy:* run two cheap checks before any code.
(a) **Evidence audit (planner, read-only, ~30 min):** pick six real sessions: one that ended
normally, one that ends in a question, one that hit a usage limit, one in a deleted worktree, two
on the same branch, and one from Antigravity. For each, note which of cwd, branch, last role,
limit text and reset time are actually in the files. *Pass:* at least 5 of 6 states can be derived
without guessing, apart from the labelled "asking you" heuristic. *Fail:* the read-only v1 premise
needs rework.
(b) **Founder timing:** time the same three tasks in the current Orca sidebar first, then on
paper. Record the time and the errors. Accept only if errors drop. Speed alone doesn't count.

**14. Failure cases to add to the spec fixtures:**
- a provider format change mid-version, which should show "unreadable", not empty;
- a transcript still being written while it's read (a partial last line);
- the clock on another device;
- the user editing the queue while a session finishes;
- the same session id seen from two worktree directories;
- a grant revoked while the app runs.

**15. Duplicate retries / safe resume (only if the companion is chosen).** Any "resume" action
puts an idempotency key into the copied command or handoff. If the outcome is ambiguous, the
state is "unknown, check the provider". The app never re-sends.

### What I'm not claiming

- I ran no tests, builds or provider calls.
- Provider hook, usage-field and Antigravity statements are unverified.
- Apple's inherited-sandbox rule is documented Apple behaviour, but I didn't re-check it against
  current review guidance in this pass.
- The Orca sidebar bug is Orca's. Reporting it upstream might fix part of the founder's pain
  sooner than any of this.


## codex — response — 2026-11-03

Founder clarified the distribution decision after this review: if the Mac App Store route blocks required capabilities, the fallback is a **separate desktop app distributed through GitHub**, initially. They confirmed this means the download channel, not GitHub-only repositories. The draft intent, AW-11 and plan now record that option. No new project, target, runtime, signing change or migration is authorized by this clarification.

Finding 2 is accepted as a feasibility/distribution gate, not as proof that every possible Mac architecture has been ruled out. The review explicitly did not re-check current Apple guidance. Next planning work compares standalone direct distribution with a companion and determines safe access to the existing notes without assuming shared bookmarks, app groups or cloud identity. The app remains a Mac app outside the Store.

The remaining findings still require a planner response; this is not a settled turn. Provider transcript formats, hooks, approval signals and usage fields remain unverified. The smaller read-only scope in finding 3 is a recommendation, not an approved replacement of the founder's broader goal. No further Claude run was started for this clarification, to conserve usage. No product code or runtime changed.
