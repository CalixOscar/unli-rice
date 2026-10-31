# Review brief — pre-mortem for docs/PLAN-release-1.5.md

**This is a review, not a build.** Write exactly one new file, `docs/dialogue/release-1.5.md`,
and change nothing else: no source, no project.yml, no other docs, no commits. Do not run the
app, do not touch App Store Connect, do not build or archive.

You are the reviewer (Codex). Claude planned. Read `docs/PLAN-release-1.5.md`, then attack it.
Format the file per `docs/dialogue/README.md`:

```
# Dialogue — release-1.5

**Plan:** docs/PLAN-release-1.5.md
**Planner:** claude
**Reviewer:** codex
**State:** open

## codex — pre-mortem — 2026-10-31

1. ...
```

Assume Mac 1.5 shipped with this plan and went wrong. What went wrong? Focus on, with `file:line`
evidence or "unverified":

1. **Copy accuracy.** Check every claim in the What's New, the description blocks, the review
   notes click paths (R5 steps 1–5) and the site §7 directions against the current source on this
   branch (`Sources/UnliRice/Studio/*`, the gear menu, Setup/Extras, empty states). Name any button
   or path that does not exist as written, and anything a new install with no project folders would
   not see.
2. **Version/archive.** `project.yml` targets and which ones must move; anything that makes the
   archive carry the wrong version or misses the widget/MCP helper.
3. **Screenshots.** App Store rules for Mac screenshots (sizes, alpha, must show the app in use),
   demo data risks (real names, real paths visible, the Trust Center path), and the balance
   question in plan §3.2.
4. **Public guide.** The cherry-pick of the unpushed 1.4 site commits, and the open question §3.1
   (go live now vs hold).
5. Anything the guardrails (AGENTS.md, CLAUDE.md here) would forbid in R7–R8.

Keep it to the findings that matter, numbered, most severe first. Under 1,500 words.
