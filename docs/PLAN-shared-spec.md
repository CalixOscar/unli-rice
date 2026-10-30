# PLAN — Carry a draft specification between tools

**Intent:** `docs/intent/INTENT-008-shared-spec.md`
**Planner:** codex. **Reviewer:** claude.
**Stage:** 2 draft. **Pre-mortem:** not run.
**Branch:** `codex/shared-spec` in the managed `shared-spec` worktree.
**Verified against:** `8d2189c` in Unli Rice; website state must be rechecked before any website build.

## Scope and order

The founder wants Idea Clinic and Unli Rice connected by a reusable specification,
and the planned LearnPy agent lesson last. First make a useful manual handoff:
the Clinic's existing AI prompt can ask for a draft after a decision to proceed;
the person reviews it, then saves and retrieves it as an ordinary Unli Rice note.
This is a copy/paste handoff, not an automatic integration or synchronized state.
Then try an Orca planner/reviewer workflow. Do not change the active LearnPy demo.

The website has existing uncommitted and untracked work. Do not overwrite, move,
stage, stash or commit it. The website part needs its own clean branch and worktree
from an explicitly checked base, and a separate repository-local plan and review.
No deployment is authorized by this plan.

## What exists

- Idea Clinic builds prompts in `idea-clinic/app.js`; `assets/webmcp.js` has a
  separate Clinic prompt. The web page does not itself generate a specification.
- Unli Rice creates, searches and appends ordinary notes. Titles are permanent;
  appended text is history, not an in-place replacement. The MCP server is not
  connected to this Codex session.
- The founder's current planning process already uses intent as the specification,
  bounded tasks, one planner and the other tool as reviewer. Keep that process.
- Orca 1.4.244 was installed in the user's Applications folder. Its UI shows
  Ask for approval, automatic folder trust off, and both Claude and Codex
  detected. Actual launches and vault access remain unverified. Claude reports
  the server pending approval, and the checked Codex CLI has no `unlirice`
  server registered.

## Design decisions

1. The AI's output is called a **draft specification** and leaves unknowns
   explicitly open. It never says an idea has been approved or implemented.
2. Suggest a specific permanent title `Draft specification: <idea>`. “Draft”
   describes the original document, not a live approval status. Record later
   decisions as clearly dated append-only additions. A copied note is a snapshot.
3. Use existing note creation and search; add explanatory guidance and copying
   only if the independent review confirms this is necessary and safe. Do not
   parse text, change note schema, overwrite a user's House Rules, or auto-tag.
4. One planner owns integration and working state; the other tool reviews via
   the append-only dialogue. A worktree does not expose another worktree's
   uncommitted files. Do not auto-dispatch cross-provider builders.

## Journey and acceptance

1. The person completes the Clinic, copies its prompt and discusses the idea
   with their AI. Only after they choose to proceed and request a spec does the
   AI produce a draft with goals, exclusions, acceptance scenarios, suggested
   verification and unresolved questions.
2. They review and amend the draft and can paste it into a new Unli Rice note.
   They can search and copy the full note, including later append-only additions.
3. If an MCP-connected assistant saves it, that is a separate explicit request;
   it searches first, uses the proper source and flags suspected conflicts.
   If MCP is unavailable, the manual handoff still works.
4. A future LearnPy lesson may use the reviewed spec only after its own runtime
   and lesson design are settled. This plan makes no claim that today's demo
   runs Python or builds agents.

Partial input stays an explicitly incomplete draft. The page's existing local
draft survives its established resume flow. A missing MCP connection is reported
as unavailable; no claim of automatic save or live synchronization is shown.
Verification must include long text, unknowns, amendments, an empty note,
copy/download, and first run and return visits. Unchecked visual or device states
are recorded as unverified.

## Candidate implementation steps — not settled

These steps are a reviewable proposal, not builder handoffs. Resolve all open
questions and receive Claude's pre-mortem before specifying exact edits and
dispatching builders.

- [ ] `planner` Prepare a website-only intent/plan and clean worktree, aligned
  with the approved shared outcome; identify current website base and existing
  changes without moving the in-progress LearnPy work.
- [ ] `build` Website: add conditional draft-spec instructions to all Clinic
  routes and the equivalent WebMCP path, plus accurate handoff guidance and
  meaningful tests. Files and exact copy must be settled in that repo's plan.
- [ ] `build` Unli Rice: add discoverable manual save guidance and a full-note
  copy action using existing note behavior; update the user guide and verify
  ordinary notes, append history, long content, search and copy in a running app.
  Exact files and copy require pre-mortem and a bounded handoff.
- [ ] `planner` Verify Claude/Codex connectivity to the actual vault from Orca
  read-only before any note write; preserve current permission boundaries and
  ask the founder to complete any needed trust/approval prompt.
- [ ] `planner` Trial one bounded task with explicit owner, base commit, branch,
  worktree, transferred review artifact, elapsed time and usage where available.
  Record what was observed, not an assumed improvement.
- [ ] `planner` Address the LearnPy agent lesson only after the preceding pieces;
  write and review a separate plan against the actual course and runtime.

### Orca trial protocol to refine in review

Choose a small feature with a clean base and record its repository, base commit,
planner, reviewer and branch before either tool edits. The planner's own builder
does the bounded change; the other tool reviews the same identified revision and
writes only its dialogue turn. If a separate worktree is used for review, transfer
the uncommitted dialogue deliberately and inspect it before the planner appends a
response. Only the planner integrates changes and updates the working-state file.
Check each worktree for uncommitted work before and after; never remove one as
cleanup without inspecting it. Record actual elapsed time, handoffs, conflicts,
test evidence and provider usage if available. A single trial is not enough to
prove a speed or token saving.

## Verification required before completion

Run the relevant website tests and syntax checks, Swift tests and a running-app
manual walkthrough; independently inspect both diffs. Review all user-facing
copy for the difference between prompt, draft, reviewed specification and saved
snapshot. Record actual checks, limitations, and the Claude post-mortem.

## Open pre-mortem questions

- Is a full-note copy control needed, or does the existing detail view already
  provide an adequate way to transfer the complete projected note?
- What prevents a draft prompt or stale snapshot from being mistaken for an
  approved spec? How are amendments clearly represented without new structure?
- How will a website worktree and review access the correct tracked base while
  the current checkout contains unrelated uncommitted work?
- What exactly is the least-permission vault connection for each Orca agent,
  and how will we prove it points to the correct store without writing?
- Can the desired savings be measured fairly, with missing usage marked unknown?

## Review attempt

On 2026-10-30 a Claude Opus review was requested with read access and the
dialogue file as its sole permitted output. Claude exited before reviewing:
its CLI reported the weekly usage limit was reached and a 9 p.m. Asia/Manila
reset. No pre-mortem has been written; do not treat this plan as settled or
dispatch its build steps on the strength of this attempt.
