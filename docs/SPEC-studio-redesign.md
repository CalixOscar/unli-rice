# SPEC — Studio redesign

**Intent:** docs/intent/INTENT-009-studio-redesign.md
**Status:** approved 2026-10-30, revised after Codex's pre-mortem (`docs/dialogue/studio-redesign.md`).
The plan is `docs/PLAN-studio-redesign.md`. §D is Phase B and is blocked (plan §6).
**Verified against:** `8d2189c` (`main`)

The intent says **why** and **what solved looks like**. This spec says **exactly what must be
true**, in checks someone can run. The plan that follows says **how**, step by step. Each
requirement below has an id, so the plan, the pre-mortem and the post-mortem can point at it.

"Check" names how the requirement is verified. `test` means an automated test in `swift test`.
`walk` means a hand check in a QA bundle against a throwaway vault, as described in
`memory.md` § Build and release reference.

## A. The Studio screen

| Id | Requirement | Check |
|---|---|---|
| A1 | The app opens on the **Studio** tab, which shows three decks: Garden, Branches and Notes. A glass tab bar switches to **Guardrails & Grounding**, which shows two decks. There is no text sidebar. | walk |
| A2 | Each collapsed deck shows one picture, one headline number and at most one short list of up to five items. | walk + screenshot |
| A3 | Clicking a deck makes it fill the window. Esc, or clicking its title, brings back all three. Keyboard: 1, 2 and 3 open each deck. | walk |
| A4 | One gear button opens everything that left the main stage: Connect, House Rules, Trust Center, Archived, Extras and Setup. Each is reached in at most two clicks. | walk; a list in the plan of every former `Pane` case and its new route |
| A5 | Every former `AppStore.Pane` case is still reachable. | test: a new `case` fails to compile until it is routed |
| A6 | Dark by default, with one accent colour per deck. Light mode still works and stays readable. Text contrast is at least 4.5:1. | walk in both modes |
| A9 | Liquid Glass is on the controls layer only: the tab bar, toolbar and buttons. It goes through `LiquidGlass.swift`, and no view calls `.glassEffect` directly. Deck content is solid. The text uses the system font. | review: grep for `.glassEffect` outside the helper |
| A10 | Motion uses interruptible springs. With Reduce Motion on, the crate flips become cross-fades. With Reduce Transparency on, the glass becomes solid. | walk with both accessibility settings on |
| A7 | The window works at 960×600 (the current minimum, `UnliRiceApp.swift:42`). Decks stack or shrink, and nothing is cut off. | walk |
| A8 | The top strip shows the current project's name and its seven lights (§C). With no project picked, it shows the most recently active one, or nothing. | walk |

## B. The decks

| Id | Requirement | Check |
|---|---|---|
| B1 | **Garden:** a crate of album sleeves, one per `ProjectGarden.Project`. The front sleeve is full size, and up to three peek out behind it. The sticker follows plan §2.5: a project with read issues is "can't read"; `needsAttention` gives "needs you"; no status and no repository gives "no notes yet"; anything else is "fine". A read failure is never "fine". (Seeds are Phase B.) | test (state mapping) + walk |
| B2 | **Garden:** flip with the arrow buttons, the left and right arrow keys (`.keyboardShortcut`, available on macOS 11+), a trackpad swipe, or a click on a sleeve behind. At 20 sleeves or fewer, a row of dots jumps straight to a sleeve; above 20, "n of N" and the List view. The order is most recently active first. With no dates a project goes last, and it is never hidden. | test (ordering) + walk |
| B3 | **Garden:** under the crate, the front sleeve's seven lights and its next step. Opening the Garden shows the back of the sleeve: the seven stages as a tracklist (Side A before building, Side B building), with the Copy prompt for the next step. | walk with a 60-repo sample |
| B4 | **Branches:** shows `BranchGraphView` for the selected Garden project. It reuses the existing drawing and claims, and adds no new git reading. | walk; diff shows `GitRepoScanner` unchanged |
| B5 | **Branches:** with no ancestry published, it says so in one sentence, as today. It never draws guessed shapes. | walk |
| B6 | **Notes:** shows the total open notes, the "needs you" count (`pending.count + unreadNoticeCount`), the source of the newest write, and the five newest titles. Clicking a title opens the existing note detail. | test (counts) + walk |
| B7 | **Notes:** when the corpus can't be read, the dial shows unknown with the `CorpusHealth` reason. It never shows "0 notes". | test |

## C. Build-gate lights

| Id | Requirement | Check |
|---|---|---|
| C1 | A pure core type, `BuildGate`, reads **one feature** (one slug) of a project folder and returns seven lights. Every file it uses comes from paths named in that feature's plan; nothing is combined across features or chosen by modification date. Light states are exactly those in plan §2.6. The app says "Lights show which files exist in this repo": they report files and enforce nothing. | test |
| C2 | `unknown` is returned when the folder or a file can't be read. `missing` is returned only when the folder was read and the file isn't there. | test, including an unreadable fixture |
| C3 | Intent is `done` only when the plan's `**Intent:**` file has a `**Status:**` line starting with `approved`. An existing file with another status is `draft`. | test |
| C4 | Spec is `done` only when the plan's `**Spec:**` file has `**Status:**` starting with `approved` and names the same intent. Another status is `draft`; a different intent is `unknown`. A plan with no `**Spec:**` line is an older plan: `notRequired`. | test |
| C5 | Agents is `done` when `AGENTS.md` exists at the root. `CLAUDE.md` is optional. If `CLAUDE.md` exists without a line equal to `@AGENTS.md`, the light is `draft`, because Claude Code would then skip `AGENTS.md`. Merely mentioning `AGENTS.md` doesn't count. | test |
| C6 | Pre-mortem is `done` only when the dialogue header's `State` is settled, built or closed, a pre-mortem turn is by the header's Reviewer, and a settled turn by the header's Planner comes after the reviewer's last pre-mortem or rebuttal. Headings inside code fences don't count. `**Pre-mortem:** skipped — <quote>` in the plan gives `skipped`. | test, using the dialogue README's format |
| C7 | Build is `done` when the plan's `**Stage:**` line says built or post-mortem. Post-mortem is `done` when a `— post-mortem —` turn exists. | test |
| C8 | Reading is bounded: `docs/` listed at depth 1 with at most 500 entries, and 128 KB per file. Going over either gives `unknown` with the reason, never `missing`. Paths that resolve outside the folder are `unknown`. | test |
| C9 | `BuildGate` writes nothing and needs no new entitlement. | review: the diff has no write calls; entitlements unchanged |
| C10 | Clicking a grey or missing light shows one plain sentence on what makes it green, plus a "Copy prompt" button that copies a prompt for the user's AI. The button changes no file. | walk |

## D. Idea Clinic in the app (Phase B: blocked on a shared clinic data file, plan §6)

| Id | Requirement | Check |
|---|---|---|
| D1 | "Plant an idea" in the Garden opens the clinic: the same question ids, wording, branches and three endings as `CalmdownOscar/idea-clinic/app.js`, at the version pinned in the plan. | test: the bundled tree matches a checked-in copy, plus a hash |
| D2 | One question per screen, with big tap targets and keys 1–3 for the choices. Back, the read-back and "Change my answers" work as on the website. | walk |
| D3 | The output is the same three prompts as the website, plus a Markdown brief made of the answers read back, under the heading `# IDEA — <one-sentence idea>`. | test (the brief's text is a pure function of the answers) |
| D4 | The output can be copied, or saved through the system save panel to a folder the user picks. No other write. | walk; entitlements unchanged |
| D5 | The draft survives quitting the app, stored only in app preferences. It is never put in the event log unless the user saves it as a note. | test |
| D6 | No network call and no model. | review |

## E. Instructions (the gate on paper)

| Id | Requirement | Check |
|---|---|---|
| E1 | `AGENTS.md` § "How work moves" lists the order: idea (new apps only) → intent → spec → agent files → plan → pre-mortem through the bridge → build → post-mortem. | review |
| E2 | `CLAUDE.md` and `docs/dialogue/README.md` say a planner may not hand over a `build` or `build-light` step until intent, spec, `AGENTS.md` and a settled pre-mortem exist. A founder skip is allowed, but it must be written in the plan header. | review |
| E3 | The builder handoff gains `Intent:` and `Spec:` fields. | review |
| E4 | Lines found outdated on `8d2189c` are corrected, and nothing else changes. | review of the diff |

## Not in this spec

Anything listed under INTENT-009 § "Scope boundaries" is out. Changes to the website's Idea
Clinic are a separate plan in `CalmdownOscar` (intent open question 5).
