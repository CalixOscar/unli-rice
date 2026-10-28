# BUILD 1 of 2 — to-do widget: shared core, MCP text, and the B0 spike

**You are stage 5. Build this.** The settled spec is `docs/PLAN-todo-widget.md` in this repo
(stages 2–4 complete, Codex pre-mortem answered in its §10). Read it in full before starting.
This file tells you **which parts to build in this run** and the rules for the run.

**Branch:** you are already on `feature/todo-widget`, created off `main` at `6918f2d`. Stay on
it. Do not create another branch. Do not touch `main`. Do not push.

## Build in this run

1. **Part A, all of it** — `docs/PLAN-todo-widget.md` §3, A1–A7:
   - A1 `StudioTodo.aiFlags` — behaviour-preserving extraction, lowercase keys, NO re-keying;
     replace both pane loops (`Sources/UnliRice/TodoPaneView.swift`,
     `Sources/UnliRiceCapture/TodoView.swift`) with calls to it.
   - A2 `TodoWording` (and use `subtitle` for the `.aiFlagged` evidence line in both panes).
   - A3 `TodoHandoff`, A4 `TodoLink`, A5 `TodoPrompt` (move the string building out of
     `Sources/UnliRice/AppStore+TodoPrompt.swift` into Core; the app keeps only the
     pasteboard write; apply the three text changes listed in A5).
   - A6 `WidgetCorpus`, `AgentSettings.loadStrict`, `EventStore(readingExisting:)` with
     `skippedLines`. Existing initialisers and `AgentSettings.load` must behave exactly as
     before.
   - A7 every listed test.
2. **Part C** — §5: append the two sentences, verbatim, to the `instructions` string in
   `Sources/unlirice-mcp/main.swift` (around line 83). Nothing else in that file.
3. **B0 spike, build only** — §4 B0: add a minimal `UnliRiceWidget` app-extension target
   (per B1: macOS 14.0, depends on UnliRiceCore, `UnliRiceWidget.entitlements` identical to
   `UnliRiceHelper.entitlements`, widgetkit extension point, embedded in `UnliRice`) whose
   only widget calls `WidgetCorpus.resolve()` and displays either the note count or the
   `Unreadable` case name. No list UI, no buttons, no URL scheme, no intents yet. Run
   `xcodegen generate`.

## Do NOT build in this run

B1's URL scheme, B2–B6 (the real widget, Done intent, app URL handling, Darwin
notification, prompt menu). Those are dispatch 2, and they depend on B0's hands-on result,
which needs a signed install, a restart and a custom folder chosen in the app — a human
step. **Stop after the three items above.**

## Rules

- **A previous attempt at this brief ended after six minutes with no work saved**: it
  started `swift test` as a background task, went idle waiting for it, and the run
  exited. **Run every command in the foreground and wait for it to finish.** Never
  background a build or a test run.
- **Do not symlink, move or delete `.build`.** `swift build` and `swift test` work in
  place in this folder (verified 2026-09-19 by Claude: 380 tests, 2 skipped, 0 failures
  — that is your "before" count). For `xcodebuild`, pass `-derivedDataPath /tmp/...`.
- Do not edit `AGENTS.md`, `memory.md`, `PROJECT_NOTES.md`, or anything under `docs/` except
  writing your report (below).
- `*.xcodeproj` is gitignored; do not force-add it.
- Commit in logical steps (Part A core, Part A pane changes, Part C, B0 spike). Never use
  `--no-verify`. If the pre-commit hook blocks a commit because `memory.md` is stale, set
  `STUDIO_ALLOW_STALE_MEMORY=1` for that commit only — memory.md is updated by Claude after
  verification.
- If anything in the plan turns out to be wrong against the code, stop and report it;
  do not improvise a design change.

## Done means (verify each, paste the real output in your report)

- `swift build` and `swift test`: all green, with the count of tests before and after.
- `xcodebuild -list` shows `UnliRiceWidget`.
- `xcodebuild` builds the `UnliRice` scheme (which embeds the extension) and the
  `UnliRiceCapture` scheme. Use derived data under `/tmp`, never `~/Documents`.
- `git diff --name-only 6918f2d..HEAD` lists only files named in plan §7 that belong to
  Part A, Part C, or the spike target.

## Report

Write `docs/BUILD-todo-widget-1-REPORT.md`: what you built, commit hashes, the verification
output above, anything you stopped on, and every place you departed from the plan and why.
"SUCCESS" without pasted output is not a report.
