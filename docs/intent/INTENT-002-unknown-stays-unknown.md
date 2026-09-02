<!-- INTENT — the WHY, written at stage 1, before any architecture exists.
     Template: ~/Documents/Unli Rice Vault/scripts/templates/INTENT.md
     Never edited to match what got built; superseded by a new INTENT if it turns
     out to be wrong. -->

# INTENT-002 — Unknown stays unknown

**Date:** 2026-09-02
**Author:** founder, via Claude Code (discovery was Codex's post-mortem at `8c95a8b`,
re-verified at `1a5b550`)
**Status:** draft
**Plan:** `docs/PLAN-unknown-stays-unknown.md`

## The problem

Codex reviewed the app and named the recurring failure as *finishing components without
proving the complete user experience*. That is true but too broad to act on. The five
confirmed defects underneath it share a much narrower shape:

**An unknown is silently converted into a positive claim.**

- No measurement of worktree dirt becomes *zero dirty files*.
- An unreadable snapshot becomes *"no worktree holds uncommitted work"*.
- Any MCP tool call — including a read or a search — becomes *this client has written*.
- Caller-supplied attribution becomes *"every write is signed"*.
- A flag set with no destination becomes a button that appears to work.

Every one of these makes the app more confident than the evidence it holds. That is
uniquely damaging for this product, because the entire pitch is *memory you can inspect
and verify*. A dashboard that says "nothing outstanding" when it measured nothing is
worse than no dashboard: it spends the user's trust to hide its own gap.

The same shape has been paid for before. `8c95a8b` fixed "an unreadable corpus was shown
as 'you are a new user'" — the identical bug, one pane over. `1a5b550` fixed a `memory.md`
that had gone 22 commits stale while every linter passed, because the linters validated
the shape of what was written and could never notice that nothing was written. The class
keeps recurring because nothing names it.

## Who hits it, and when

- **A stranger on first run**, pressing the most obvious button on the home screen
  ("Start Profile") and landing on the Setup pane instead of the profile builder. There
  is no error, so the reasonable conclusion is that the feature does not exist.
- **The founder**, opening the To do pane to decide whether it is safe to wipe a machine,
  and reading "no worktree holds uncommitted work" from a pane that never looked.
- **Any user whose agent reads the vault but never writes to it** — the exact case already
  recorded in `evals/cases/unli-009.yaml` — whose no-write warning is suppressed by the
  agent's first search.
- **A developer evaluating the trust claims**, who reads "Every write is signed", checks
  `Event.swift`, finds attribution strings, and correctly discounts every other claim on
  the page.
- **Any MCP client** sending `transaction_log` with a negative limit, which traps the
  server rather than returning an error.

## What "solved" looks like

From outside the app:

1. Pressing "Start Profile" shows the profile builder.
2. The To do pane never asserts a repository is clean unless something measured it. When
   dirt is unmeasured it says so, in the pane, in the same place the count would be.
3. The no-write diagnostic fires when a client has read but not written — it distinguishes
   a write from a tool call.
4. The comparison screen describes attributed history and says who is trusted, rather than
   claiming cryptographic signatures the code does not produce.
5. `transaction_log` with `{"limit": -1}` returns a JSON-RPC error over the real stdio
   server. Nothing traps.
6. `swift run` with the command the README prints actually launches the GUI.
   *(Done ahead of this plan — one stale product name, fixed directly.)*

## Explicitly out of scope

This intent is **not** the Codex roadmap. The following are founder decisions or separate
efforts and must not be pulled in:

- Repositioning, README rewrite, or the origin-story wording.
- Five-user studies, CI workflows, `CONTRIBUTING.md`, `SECURITY.md`.
- Search pagination, duplicate-detection scale, published benchmarks.
- The purge-vs-appender concurrency risk (unreproduced; needs its own multiprocess test).
- The `resolve_review` human-confirmation boundary (a real design question about what an
  external client may do unattended — not a mislabelled unknown).
- Publishing `check-repos.sh`, which currently lives only in the local vault. Real gap for
  outside users, but a scope decision the founder owns.
- Any new feature. This intent removes false confidence; it adds nothing.

## Fixed constraints

- **Derived, never stored.** `StudioTodo` computes from state and cannot be ticked off.
  A fix that caches a dirt count would reintroduce the drift the pane exists to avoid.
- **The app is sandboxed and cannot run `git`.** Worktree dirt can only arrive through the
  published snapshot. The fix is therefore *represent the absence*, not *go measure it*.
- **Locked decision #3 — propose, never apply.** Nothing here may start writing.
- **No new `EventKind`.**
- **The eval gate.** `unli-001` … `unli-008` are unconfirmed hypotheses with no recorded
  transcript. None of the five defects here is predicted — each was read directly out of
  the code at `1a5b550` — so the gate does not block this work. It does block anything
  that would speculate about agent behaviour.

## Questions discovery could not settle

- **Does the snapshot have a place to carry worktree dirt at all?** `check-repos.sh` lives
  in the vault, not this repo, so extending `RepoSnapshotFile` to carry a real count is a
  cross-boundary change. Until that is answered, dirt is *unknown*, and the plan treats it
  as unknown rather than proposing a schema change.
- **Where should the profile builder live** — a tenth `MoreDestination`, or its own
  top-level pane? The flag `showingProfileBuilder` is already routed separately from
  `showingMore` everywhere except the `mainColumn` branch, which suggests it was meant to
  be its own pane. The plan picks one; the founder may override.
