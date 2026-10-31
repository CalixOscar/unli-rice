# INTENT-009 — Studio redesign: three big pictures, and nothing gets built without its paperwork

**Date:** 2026-10-30
**Author:** founder, via Claude
**Status:** approved 2026-10-30 — the founder chose "approve with drafts": keep macOS 13 with
the glass fallback, and call the main tab "Studio"
**Intent read:** passed 2026-10-30 — Codex attacked the intent first in its pre-mortem (`docs/dialogue/studio-redesign.md`, finding 1)
**Spec:** docs/SPEC-studio-redesign.md (2026-10-30)
**Plan:** docs/PLAN-studio-redesign.md (stage 2, waiting for Codex's pre-mortem)

## The problem

The founder's words: "Let's rebuild Unli Rice. I want a sleeker, simpler, easier look. Right now
I barely understand my own app. I want a look in Unli Rice similar to the djay Pro app. Simple,
easy to understand, a few big graphics that are understandable. One could be all the tracked
repos in the garden, the other could be the different branches and a third the notes."

Then: "We need to make sure whenever an app is built there is intent, spec and agent markdowns
before building, as well as a pre-mortem sent back and forth through the bridges. Not much change
to today's instructions, but some of them might be outdated. Also add in the Idea Clinic from
calmdownoscar.com."

So there are three asks:

1. **A new look.** Three big pictures instead of a list of screens.
2. **A build gate.** No app gets built until its intent, spec and agent files exist, and the
   other planner's pre-mortem has gone through the bridge.
3. **The Idea Clinic inside Unli Rice**, as the step before an intent.

## What the evidence says about today's app

Checked against `8d2189c` (`main`, the 1.4 (9) build now in App Review).

- **The sidebar is a list of text rows under jargon headings.** It has GROUNDING, GUARDRAILS and
  EXTRAS headings, 7 core rows and up to 4 extra rows, plus Setup (`ContentView.swift:152-232`).
  Row names like "The folder your AI can read" and "What your AI should always do" are full
  sentences. You have to read them to find anything.
- **Navigation has 17 destinations** (`AppStore.swift:72-76`). Most are screens of cards or text.
- **The pictures the founder wants already exist, but they are buried.**
  - The Garden (`ProjectGardenView.swift`, `ProjectGarden.swift`) lists tracked repos with their
    status, next step, to-dos and branch counts. It sits behind Setup › Extras › Projects, which
    is **off for new installs** (INTENT-007).
  - The branch train-line graph (`BranchGraphView.swift`) draws forks and merges to scale. It is
    one tab inside Projects.
  - The notes are a scrolling list (`ContentView.swift`) and an optional Map (`NoteGraphView.swift`,
    also an Extra, off by default).
- **All three are read-only already.** Repos are read by parsing `.git` directly, because the
  sandbox forbids running `git` (`GitRepoScanner.swift`; PROJECT_NOTES "The studio cockpit").
  Nothing in this redesign needs a new write path.
- **The pipeline already has most of the gate, but only on paper.** Intent docs (`docs/intent/`),
  plans (`docs/PLAN-*.md`), the bridge (`docs/dialogue/<slug>.md`) and the builder contract
  (`AGENTS.md`) all exist. What is missing:
  - there is no **spec** stage between intent and plan;
  - nothing checks that the target repo has **agent files** (`AGENTS.md`, `CLAUDE.md`) before a
    build;
  - the pre-mortem has been **skipped** three times on record: shipped-guardrails, the AI to-do
    feature and the widget (`memory.md` § Active constraints; PROJECT_NOTES 2026-10-16).
    Each skip was a founder decision, but nothing showed it at the time.
- **The Idea Clinic** (`CalmdownOscar/idea-clinic/app.js`) is a branching tree of about ten
  questions. It ends in one of three copy-paste prompts: decision brief, build check, launch plan.
  It uses no AI and stores the draft only in the browser. Nothing links it to a repo or to an
  intent doc.

## What "solved" looks like

**Amended 2026-10-30 after Codex's pre-mortem** (`docs/dialogue/studio-redesign.md`). The founder's
rule ("nothing gets built without its paperwork") is a rule that agents are asked to follow. The
lights report which files exist for one feature. They don't prove that anyone followed the rule,
and nothing in this intent blocks a build mechanically. The native Idea Clinic is Phase B. It
waits for a shared clinic data file on the website, so the app and the site can be tested
against each other. Until then, "Plant your first idea" opens the website clinic. Orca
integration is out of scope. Read §2 and §3 below in this light.

### 1. The look: three decks

Inspired by djay Pro's layout, but using none of its branding: a dark stage, a few large visuals
with one accent colour each, very few words, and detail only when you ask for it.

- **One main screen, the Studio, with three big pictures ("decks"):**
  - **Garden:** every tracked repo as an album sleeve in a record-store crate. You flip
    through them one at a time, and the sleeves behind peek out over the front one. A sticker
    on each sleeve shows its state: fine, needs you, can't read, or seed. Under the crate are
    the front project's seven lights and its next step. (Founder, 2026-10-30: "make the cards
    flip like albums in a record store", replacing the round platter in the first mockup.)
  - **Branches:** the train-line graph for the repo you picked, drawn wide like a waveform.
    Main is the thick line, and each branch is a siding that leaves and rejoins it.
  - **Notes:** one big dial showing how many notes there are, how many need you, and which AI
    wrote last. The newest few titles sit underneath.
- **Click a deck to make it fill the window.** Esc, or the same click, brings back all three.
- **A thin strip across the top shows the project you are working on** and its build-gate
  lights (§2).
- **Two tabs at the top: Studio and Guardrails & Grounding** (founder, 2026-10-30). Studio holds
  the three decks. Guardrails & Grounding holds INTENT-007's two jobs as two big decks:
  - Grounding: what your AI knows, meaning your notes, the folder it reads and, later, each
    tool's memory files.
  - Guardrails: what your AI must do, meaning House Rules, Needs you, the safety checks and
    Archived. Later it also shows whether the AI followed the rules.
- **Setup and Extras move behind one gear button.** Nothing is deleted.
- Words are plain. No row on the main screen needs reading to be understood.
- **Apple's fluid design** (founder, 2026-10-30: "make things in the app Apple design fluid"):
  - Liquid Glass goes on the controls layer only: the tab bar, the toolbar and the buttons.
    The decks and their content stay solid underneath, as Apple's Human Interface Guidelines
    describe.
  - Text uses the system font.
  - Motion uses springs that can be interrupted, so a flip can be reversed mid-flight.
  - Reduce Motion and Reduce Transparency are respected.
  - Glass goes through the existing `LiquidGlass.swift` helper. It gives the real
    `.glassEffect` on macOS 26 and a material fallback below that.

### 2. The build gate: seven lights per project

Every project in the Garden carries a row of lights, read from files in its repo:

| Light | Green when | Read from |
|---|---|---|
| Idea | An Idea Clinic brief exists | `docs/idea/IDEA-*.md` |
| Intent | An intent doc exists and says `approved` | `docs/intent/INTENT-*.md` |
| Spec | A spec exists for that intent | `docs/SPEC-*.md` |
| Agents | `AGENTS.md` exists at the repo root. `CLAUDE.md` is optional | repo root |
| Pre-mortem | The plan's dialogue file has a pre-mortem turn and a `settled` turn | `docs/dialogue/<slug>.md` |
| Build | The plan's stage says built | `docs/PLAN-*.md` header |
| Post-mortem | The dialogue file has a post-mortem turn | `docs/dialogue/<slug>.md` |

- **Grey means unknown, never missing.** An unreadable folder, or a repo the user hasn't granted,
  shows grey with the reason. This is the "unknown stays unknown" rule
  (`INTENT-002-unknown-stays-unknown.md`).
- **A skip is shown as a skip.** If a plan's header records that a stage was skipped at the
  founder's direction, that light shows a skip mark rather than green.
- **The app only shows the gate. It enforces nothing**, because it is sandboxed and only
  reads. The gate is enforced where builds actually start, in the instructions: `CLAUDE.md`,
  `AGENTS.md` and `docs/dialogue/README.md` all say a planner may not hand over a build step
  until lights 2 to 5 (Intent, Spec, Agents, Pre-mortem) would be green.

### 3. The Idea Clinic, inside the app

- In the Garden, **"Plant an idea"** opens the Idea Clinic's questions, natively. These are the
  same questions, branches and three prompt endings as calmdownoscar.com/idea-clinic.
- The result is the prompt, as on the website, plus a **brief** in Markdown. The brief is the
  answers read back. The user copies it or saves it to a folder they choose.
- Saved into a repo as `docs/idea/IDEA-<slug>.md`, the brief turns the Idea light green, and it
  becomes the "founder's words" section of the intent that follows.
- An idea with no repo yet shows in the Garden as a **seed**, once its brief is saved somewhere
  the app can read.

## Scope boundaries: explicitly NOT this

- **No change to the locked architecture.** The append-only event log, the `Note` projection,
  no destructive delete and propose-only structural changes all stay (`PROJECT_NOTES.md`
  § Locked-in architecture decisions).
- **No new write path, and no running `git`.** The app reads repos and docs. Anything it suggests
  doing is copied text, as today.
- **No change to the MCP server's tools.**
- **Nothing deleted.** Screens that leave the main stage stay reachable behind the gear.
- **Not part of the 1.4 release.** 1.4 (9) is in App Review. This work happens on
  `claude/studio-redesign` and ships no earlier than 1.5.
- **No AI in the Idea Clinic**, on the website or in the app.
- No copying of djay Pro's artwork, name, icons or exact layout. The redesign borrows the
  principles: dark, big, few words.

## Answered (founder, 2026-10-30)

1. **INTENT-007's sidebar:** replaced by two tabs, Studio and Guardrails & Grounding. INTENT-007's
   Phases B and C land in the second tab, and they are still redrafted before any build.
2. **A new user:** sees the drafted state, a seed reading "Plant your first idea". Approved.
3. **Agent files:** the founder asked whether `CLAUDE.md` is still needed. Mostly not. Claude
   Code reads a repo's `AGENTS.md` by itself when there is no `CLAUDE.md`. When both exist, it
   reads only `CLAUDE.md`, unless `CLAUDE.md` imports `AGENTS.md` (code.claude.com/docs/en/memory,
   § AGENTS.md, read 2026-10-30). So `AGENTS.md` is required and `CLAUDE.md` is optional. Use it
   only for Claude-specific instructions, and make it import or point at `AGENTS.md`.
4. **The website's brief download:** approved. It is a CalmdownOscar change with its own plan.
5. **INTENT-008:** the founder asked for a prompt that gets Codex to push `codex/shared-spec`
   and reconcile it with this intent.

## Still open

6. **Raise the Mac app to macOS 26?** Real Liquid Glass (`.glassEffect`) needs macOS 26.
   `project.yml:6` deploys to macOS 13, and `LiquidGlass.swift` already falls back to materials.
   **Draft:** keep 13 and the fallback for now. Decide when 1.5 is planned.
7. **The name of the main tab:** "Studio" is used in the mockup.

## Superseded questions, kept for the record

1. **Does this replace INTENT-007's sidebar?** INTENT-007 made Grounding and Guardrails the
   app's jobs and turned Projects into an Extra that is off by default. That was only yesterday.
   This intent puts Garden and Branches on the main stage. **Draft:** yes for the main stage.
   Grounding and Guardrails move behind the gear, and INTENT-007's Phases B and C (memory files,
   evals) are redrafted to fit the decks before anything is built.
2. **What should a brand-new user with no repos see?** **Draft:** the Garden shows one seed,
   "Plant your first idea" (the Idea Clinic). The Notes deck works as it does today. The
   Branches deck says "Pick a folder with a project in it" and links to the folder grant.
3. **What should "agent files" require?** **Draft:** both `AGENTS.md` and `CLAUDE.md` at the repo
   root. `CLAUDE.md` may be just the line `@AGENTS.md`. Should a third tool's file, or a
   per-folder one, also count?
4. **Where do the Idea Clinic questions live?** The website and the app would each have a
   copy. **Draft:** the website's `app.js` stays the source. The app ships a copy of the question
   tree as data, and a test pins the copy's version, so a change to one is visible in the other.
   The alternative is a JSON file both of them read.
5. **Should the website's Idea Clinic also offer the brief download**, so a brief made in a
   browser turns the Idea light green when saved into a repo? **Draft:** yes, as a fourth output
   next to the three prompts. That part is a CalmdownOscar change with its own small plan.
6. **INTENT-008 (shared spec)** exists only on Codex's local branch `codex/shared-spec`, on the
   Mac. It is not pushed, so this session couldn't read it. Both intents cover the spec stage.
   **Draft:** this one owns the app's lights and the Idea Clinic inside the app. INTENT-008 owns
   the spec template and the website changes. The founder or Codex should check that split
   before either plan is written.
7. **The name of the main screen:** "Studio", "Home" or no name at all? (Now open question 7
   above.)

## Sources

- djay Pro by Algoriddim. Used only as a style reference for "a few big, clear visuals". The
  App Store and product pages were not re-checked in this session (unverified).
- calmdownoscar.com/idea-clinic, read 2026-10-30, and its source
  `CalmdownOscar/idea-clinic/app.js`.
