# SPEC — Studio redesign

**Intent:** docs/intent/INTENT-009-studio-redesign.md
**Status:** draft. It is revised once the intent's open questions are answered.
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
| A1 | The app opens on one screen with three decks: Garden, Branches and Notes. There is no text sidebar on it. | walk |
| A2 | Each deck shows a picture, plus at most one number and one short label, before you click it. | walk + screenshot |
| A3 | Clicking a deck makes it fill the window. Esc, or clicking its title, brings back all three. Keyboard: 1, 2 and 3 open each deck. | walk |
| A4 | One gear button opens everything that left the main stage: Connect, House Rules, Trust Center, Archived, Extras and Setup. Each is reached in at most two clicks. | walk; a list in the plan of every former `Pane` case and its new route |
| A5 | Every former `AppStore.Pane` case is still reachable. | test: a new `case` fails to compile until it is routed |
| A6 | Dark by default, with one accent colour per deck. Light mode still works and stays readable. Text contrast is at least 4.5:1. | walk in both modes |
| A7 | The window works at 960×600 (the current minimum, `UnliRiceApp.swift:42`). Decks stack or shrink, and nothing is cut off. | walk |
| A8 | The top strip shows the current project's name and its seven lights (§C). With no project picked, it shows the most recently active one, or nothing. | walk |

## B. The decks

| Id | Requirement | Check |
|---|---|---|
| B1 | **Garden:** one mark per `ProjectGarden.Project`, coloured fine, needs you or unknown. `needsAttention` decides "needs you". A project with no readable status is "unknown", never "fine". | test (state mapping) + walk |
| B2 | **Garden:** mark size follows recent activity, measured as the newest commit date or note date. With no dates the mark is the smallest size and grey, not hidden. | test |
| B3 | **Garden:** above 40 projects, labels show only on hover or selection, following the Map's label budget rule. | walk with a 60-repo sample |
| B4 | **Branches:** shows `BranchGraphView` for the selected Garden project. It reuses the existing drawing and claims, and adds no new git reading. | walk; diff shows `GitRepoScanner` unchanged |
| B5 | **Branches:** with no ancestry published, it says so in one sentence, as today. It never draws guessed shapes. | walk |
| B6 | **Notes:** shows the total open notes, the "needs you" count (`pending.count + unreadNoticeCount`), the source of the newest write, and the five newest titles. Clicking a title opens the existing note detail. | test (counts) + walk |
| B7 | **Notes:** when the corpus can't be read, the dial shows unknown with the `CorpusHealth` reason. It never shows "0 notes". | test |

## C. Build-gate lights

| Id | Requirement | Check |
|---|---|---|
| C1 | A pure core type, `BuildGate`, reads a project folder and returns seven states: Idea, Intent, Spec, Agents, Pre-mortem, Build, Post-mortem. Each state is `done`, `skipped`, `missing` or `unknown(reason)`. | test |
| C2 | `unknown` is returned when the folder or a file can't be read. `missing` is returned only when the folder was read and the file isn't there. | test, including an unreadable fixture |
| C3 | Intent is `done` only when an intent doc's `**Status:**` line starts with `approved`. A draft counts as `missing`, shown as "draft". | test |
| C4 | Spec is `done` when a `docs/SPEC-*.md` names that intent in its `**Intent:**` line. | test |
| C5 | Agents is `done` when both `AGENTS.md` and `CLAUDE.md` exist at the root. A `CLAUDE.md` that is only `@AGENTS.md` counts. | test (subject to intent open question 3) |
| C6 | Pre-mortem is `done` when `docs/dialogue/<slug>.md` has a `## <tool> — pre-mortem —` turn **and** a later `— settled —` turn. A plan header saying the pre-mortem was skipped gives `skipped`. | test, using the dialogue README's format |
| C7 | Build is `done` when the plan's `**Stage:**` line says built or post-mortem. Post-mortem is `done` when a `— post-mortem —` turn exists. | test |
| C8 | Reading is bounded: at most 200 files per project and 128 KB per file, the same bound as `ProjectGarden.maxMemoryBytes`. Symlinks out of the granted folder are not followed. | test |
| C9 | `BuildGate` writes nothing and needs no new entitlement. | review: the diff has no write calls; entitlements unchanged |
| C10 | Clicking a grey or missing light shows one plain sentence on what makes it green, plus a "Copy prompt" button that copies a prompt for the user's AI. The button changes no file. | walk |

## D. Idea Clinic in the app

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
| E2 | `CLAUDE.md` and `docs/dialogue/README.md` say a planner may not hand over a `build` or `build-light` step until intent, spec, agent files and a settled pre-mortem exist. A founder skip is allowed, but it must be written in the plan header. | review |
| E3 | The builder handoff gains `Intent:` and `Spec:` fields. | review |
| E4 | Lines found outdated on `8d2189c` are corrected, and nothing else changes. | review of the diff |

## Not in this spec

Anything listed under INTENT-009 § "Scope boundaries" is out. Changes to the website's Idea
Clinic are a separate plan in `CalmdownOscar` (intent open question 5).
