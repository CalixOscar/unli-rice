# Unli Rice — Setup & User Guide

Unli Rice is a shared, permanent memory for your AI tools. Claude, Codex,
Cursor, Antigravity, and any other MCP-capable assistant can all read and
write the same set of notes, so what you tell one of them is known by all of
them — across sessions, across tools, forever.

It is built around four promises that hold everywhere in the app:

1. **Nothing is ever lost.** Every change is appended to a permanent history.
   There is no delete an AI can trigger; archiving is soft and reversible.
2. **AIs propose, you decide.** No agent or background job ever merges,
   archives, or rewrites your notes on its own. Anything structural lands in
   a review queue and waits for your OK.
3. **Every write is signed.** Each note records which tool wrote it — you,
   Claude, an importer — so you can always see who said what.
4. **Invisible by default.** The app is designed to work while you're not
   looking at it. Opening it should feel like checking a security camera,
   not feeding a pet.

---

## 1. Installing and launching

**From the Mac App Store**: Download directly from the [Mac App Store](https://apps.apple.com/app/unli-rice) and launch normally.

**From source** — the app is a plain Swift package with no external
dependencies (macOS 13+):

```bash
swift run UnliRice
```

Or build a double-clickable app bundle:

```bash
./Scripts/make-app.sh
```

which produces `dist/Unli Rice.app` containing the GUI, the MCP server, and
the background agent in one bundle.

On first launch the app seeds two short guide notes ("Welcome to Unli Rice"
and "How tags and the janitor work") and opens **Setup**, because a memory
store nothing is connected to isn't doing anything yet.

---

## 2. First-run setup

Everything you configure lives in one place: **Setup** in the sidebar, with
five tabs.

### 2.1 AI Tools — connect your assistants

This is the step that makes the app real. Each row is one tool (Claude Code,
Claude Desktop, Cursor, Codex/ChatGPT, Antigravity, or a custom MCP client)
and gives you the exact config block to paste into that tool's MCP settings.
The app never edits another app's config file itself — you paste, so nothing
can be silently broken.

Once a tool is connected, it can call the `unlirice` MCP tools:
`list_notes`, `search_notes`, `create_note`, `append_to_note`, tagging,
archiving (soft), and `flag_for_review`. There is deliberately no delete
tool.

### 2.2 Who You Are & Profiles — build your context

See sections 3 and 4 below. This is where you run the **Profile Builder**
and manage multiple profiles.

### 2.3 House Rules — standing instructions for every assistant

House Rules are a note every connected assistant is told to read at session
start: check memory before starting work, write back what was learned at the
end, sign every write, never resolve conflicts on its own. Pick one of the
built-in presets (Standard Memory, Codebase Memory, Minimalist / Low Token),
import your own, or edit the text directly — then **Save** explicitly.
Nothing is written to your notes until you save.

All presets now include the **Exception Guardrail**: if you ask an assistant
for something that contradicts your notes, it must ask whether this is a
one-time exception or whether the note itself should change — one-time gets
noted in the session, a real change gets appended to the note. Your written
rules and your actual behavior can't silently drift apart.

### 2.4 Mirror Export — see section 5.

### 2.5 What Runs on Its Own — automation

Two switches and a slider, all off/conservative by default:

- **Run routines on a schedule** — Tuesdays ingest (Claude session logs and
  any folders you nominate), Fridays tidy. Off until you turn it on.
- **Keep working with the window closed** — installs a background agent so
  routines run even when the app isn't open. It wakes every five minutes,
  does one check, and exits.
- **Autonomy slider** (Eco / Balanced / Aggressive) — controls how much the
  tidying pass *notices*, never what it may *do*. Eco also refuses to run
  unless the Mac is plugged in and idle. No level ever grants auto-apply of
  anything structural.

---

## 3. The Profile Builder

The Profile Builder generates the document set that makes any LLM instantly
useful about *you* — the thing you'd otherwise have to explain in every new
chat. Launch it from **Home → Build Profile** or **Setup → Who You Are &
Profiles**.

It's a six-step form:

1. **Who You Are** — name, role, mission, working quirks.
2. **Voice & Persona** — how assistants should talk to you (Concierge, Peer,
   Terse Tool, or custom), tone rules, formatting rules.
3. **Principles & Work** — core principles, tool/stack defaults, do's and
   don'ts.
4. **Guardrails** — your non-negotiables. The Exception Guardrail is
   included by default.
5. **Projects** — what you're working on, one line each, with status.
6. **Overlays** (optional) — extra rule sets for specific contexts, e.g. a
   "client work" overlay.

If you don't want to start from blank fields, **Load Template…** offers four
built-ins. **Studio Standard (Author's Setup)** is the recommended starting
point — a generalized version of the setup the app's author actually runs,
demonstrating every step including per-project notes and platform overlays.
**Solo Developer**, **Writer / Researcher**, and **Minimalist** are
alternatives. You don't have to take a template whole: "Pre-fill this step
only" copies just the step you're on, so you can mix one template's
guardrails with another's voice and your own everything else. And since
templates are plain data in the repo, you can fork it and ship your own —
see [TEMPLATES.md](TEMPLATES.md).

Finishing the wizard writes a set of ordinary notes into your vault:

| Note | Contents |
| --- | --- |
| `Profile: index` | Master sitemap linking to the rest |
| `Profile: identity` | Name, role, mission, quirks |
| `Profile: voice` | Persona, tone, formatting rules |
| `Profile: principles` | Principles, stack defaults, do's & don'ts |
| `Profile: guardrails` | Non-negotiables + the Exception Guardrail |
| `Project: <name>` | One note per project — status, overview, and a log assistants append to |
| `Profile: overlay <name>` | One per overlay |

Because they're normal notes, every connected assistant sees them
automatically, and re-running the wizard **appends a revision** rather than
overwriting — your earlier answers stay in the history, like everything
else here.

---

## 4. Profiles — separate memories for separate lives

One profile = one vault folder = one completely separate memory. Use them to
keep work and personal apart, or one memory per client, per venture, per
family member on a shared machine.

In **Setup → Who You Are & Profiles**:

- **+ New Profile** — name it, choose (or create) a folder for its vault.
- **Switch** — reopens the whole app against that profile's vault. Notes,
  house rules, review queue, and exports are all per-profile; nothing leaks
  between them.
- **Set as Master** — one profile is the **Master Profile**. When you create
  a new profile with "Snapshot copy Master Profile guardrails" checked (the
  default), the master's `Profile: guardrails` note is copied into the new
  vault, stamped with where and when it came from. Your non-negotiables
  follow you into every new context without you retyping them — as a
  snapshot, so editing one profile's guardrails never silently changes
  another's.

The profile you started with is "Default Profile," pointing at your existing
vault; nothing moves or changes when the feature arrives.

---

## 5. Mirror Export — the folder any LLM can read

MCP is the write channel, but not every tool speaks MCP. The Mirror Export
is the universal *read* channel: a plain-markdown folder, named
`<Profile Name> Export`, sitting next to your vault folder, that you can
point literally any LLM or tool at with zero setup — attach it to a chat,
add it to a project, open it in an editor.

It contains:

- `00_Index.md` … `04_Guardrails.md` — your profile document set
- `05_Overlay_<Name>.md` and up — one file per overlay
- `PROJECTS/` — one file per `Project:` note
- `MEMORY.md` — a compact memory capsule (target: ≤ 2,500 characters),
  exported from a note titled `Memory: capsule` if one exists. Ask your
  assistant to maintain that note as a running distillation of what matters.
- `HOUSE_RULES.md` — your current house rules
- `RAW/` — copies of ingested raw transcripts and documents

Open **Setup → Mirror Export** and it regenerates automatically; **Export
Now** refreshes it on demand, **Open in Finder** takes you there. The whole
folder is *derived* — it's rebuilt from your notes, so deleting it loses
nothing, and editing files inside it changes nothing (the vault is the
source of truth; make changes there or through an assistant).

If `MEMORY.md` grows past 2,500 characters you'll get a notice suggesting
you ask your assistant to condense it — a capsule that long stops being a
capsule.

---

## 6. Everyday use — the sidebar

**Home** — the answer to "what is this app doing for me?" A status banner
(green: memory is working, with note count and recorded client activity;
amber: nothing connected yet), a callout if anything needs your decision,
your profile status, and the last few notices.

**Needs you** — the one screen for everything waiting on your judgment:
tidying proposals (possible duplicates, contradictions) and actionable
notices, with a badge showing the count. Duplicate clusters show every note
with a "Keep this one" button — pick the keeper and the others' contents are
appended to it before they're archived, so nothing is lost. You can also
trigger **Preview Tidying** (shows what would happen, changes nothing) or
**Run Tidying Now** from here.

**Notes** — the corpus itself. Search, browse by date, read a note's full
body, tags, history, links and backlinks (`[[Title]]` wiki-links work in any
note body), and see exactly which tools wrote each part.

**Setup** — everything in section 2.

**Looking back** — a monthly/yearly retrospective built from your notes:
what you worked on, what got referenced most. It only ever announces a
period that has ended, once.

Turning on **advanced mode** adds: **Trust Center** (proof the connection
works — client activity log, vault health, snapshots and recovery),
**Notifications** (the full notice history), and **Archived** (everything
soft-archived, restorable with one click; permanent removal exists only
here, only for you, behind a confirmation, with an automatic backup).

---

## 7. What to expect

**In the first hour.** Connect one tool, save House Rules, run the Profile
Builder. Then open your assistant and ask it something about you — it should
check your notes and answer from them. Ask it to remember something; a new
note appears in the app, signed with that tool's name. That round trip is
the whole product working.

**In the first week.** Notes accumulate — some by you, most by your tools.
If you enabled routines, ingestion starts indexing your Claude sessions and
nominated folders (gradually — 40 notes per run, on purpose), and the
Friday tidying pass starts proposing tags and flagging lookalikes. Expect
the "Needs you" badge to show small numbers, not floods: proposals are
budgeted per run precisely so the queue stays worth reading.

**Ongoing.** Mostly, you don't open the app — that's the design. Your tools
keep reading and writing memory; routines keep it tidy; a notice appears
when something actually needs you or a month is worth looking back on. When
you do open it, Home tells you in one glance whether memory is working and
whether anything is waiting.

**What will never happen:**

- A note deleted, merged, or rewritten by an AI or a background job.
- The tidying pass arguing with you — once you say no to a proposal, it
  isn't proposed again, and a tag you removed by hand is never re-added.
- Your notes leaving your machine. There is no cloud service, no account,
  no API key, and nothing stored outside your vault folders. The one
  network feature (bring-your-own embedding server) refuses any address
  that isn't your own machine.
