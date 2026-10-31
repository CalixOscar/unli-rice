# Brief — post-mortem for release 1.5 (review only)

**Role:** reviewer (post-mortem). You did the pre-mortem on this plan; Claude planned and built it.
**Do not edit any file except** `docs/dialogue/release-1.5.md`, where you append exactly one turn headed
`## codex — post-mortem — 2026-10-31`. Do not change the `State:` line or anything above your turn. No commits,
no builds of archives, no network writes, no App Store Connect actions.

## What to review

- Plan: `docs/PLAN-release-1.5.md` (settled, Stage 4); your pre-mortem and Claude's response are in the dialogue file.
- App commits on this branch since the plan settled (`1a8a038..HEAD`):
  - `db0eb52` R2 version bump (`project.yml`: Mac app + widget 1.5/10; Capture stays 1.3/8)
  - `13b2264` R5 release text (`docs/release/1.5-whats-new.md`, `APP_STORE_SUBMISSION.md` 1.5 sections, `docs/APPLE_REVIEW_GUIDE.md`)
  - `1a971b4` fix found while taking screenshots: `HouseRulesPresetGalleryView.swift` called `dismiss()` while embedded in the main window, closing the whole window; it now takes an `onDone` closure (`MoreView.swift` passes it) and only dismisses when shown as a sheet. Subtitle text changed.
  - `e086bcb` R4 screenshots in `Screenshots/AppStore-Mac-2026-10-31/` (2560x1600, not the planned 2880x1800 — README explains) and corrected review steps 3 and 4.
- Site (read only, a separate repo): `/Users/calmdownoscar/Documents/Projects/CalmdownOscar-unlirice-1.5`, branch `claude/unlirice-1.5`, commits `f52a593` (1.5 text) and `6e174a0` (images) on top of the two cherry-picked 1.4 commits `e8f5876`, `ef29cb1`. Files: `unlirice/index.html`, `unlirice/user_guide.html`, `apps/assets/unli-rice-*`. If you cannot read it from your sandbox, say so and mark it unverified.

## Claims to check against the code (cite file:line, or say unverified)

1. Every step in the 1.5 App Review Notes (`APP_STORE_SUBMISSION.md`, "App Review Notes Copy-Paste Text … (1.5)") and in `docs/APPLE_REVIEW_GUIDE.md` names a control that exists with that visible label, in that order, from a fresh install with no notes and no project folder.
- The 1.5 What's New and description promise nothing the code does not do (your pre-mortem findings 2 and 6 in particular).
- The `1a971b4` fix: is the sheet path (gallery shown as a sheet elsewhere, if any) still dismissed correctly? Does any other embedded view call `dismiss()` the same way?
- The site §7 text and figure captions match the app (lights, Branches, Notes, gear menu, Extras).
- 2560x1600 PNG with no alpha is an accepted Mac screenshot size.

Then: what diverged from the plan, what broke, what the plan should have said. Keep it to findings with evidence.

## Verification you may run

`swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build` with `CLANG_MODULE_CACHE_PATH=/tmp/unlirice-clang-cache`. Report the executed/skipped/failed counts exactly as printed.
