# Battleplan: Profiles, Profile Builder, and the "any LLM can read this folder" layer

**Audience:** Google Antigravity, doing a first exploration/UI pass on this.
**Authored by:** Claude Code, 2026-07-24, at the founder's request.
**Branch:** all work on a feature branch (suggested: `feature/profiles`) off
`main`. The app is Waiting for Review on the App Store — do not commit to
`main`, and do not touch the release inputs (`project.yml`, entitlements,
`APP_STORE_SUBMISSION.md`, icon catalog).
**Authorization note:** `_AI Context/04_Guardrails.md` scopes Antigravity to
first-look ideation. The founder granted a **one-time exemption**
(2026-07-24) for this initiative specifically — the guardrails note itself is
unchanged and still governs everything else. The founder still brings results
back to Claude for architecture review before anything merges.
**Status of this doc:** a plan, not a spec. Treat every UI decision here as
disposable (the founder's documented working pattern: early mockups never
survive contact with reality — explore fast, don't polish).

---

## 0. Read these first, in order

1. `PROJECT_NOTES.md` — the authoritative technical record. **The locked-in
   architecture decisions section is non-negotiable.** Append-only event log,
   no destructive delete reachable by any agent, structural changes are
   proposed never applied, every write attributed via `source`.
2. `AGENTS.md` — how to behave if you connect to the `unlirice` MCP server.
   Identify as `source: "antigravity"`. Never write as `janitor` or `ingest`.
3. `_AI Context/` in the vault (`~/Documents/Unli Rice Vault/_AI Context/`) —
   files `00`–`06`. These are simultaneously (a) the studio context you must
   honor and (b) **the literal product template**: the Profile Builder below
   generates a personalized version of this exact document set for a new user.

## 1. What this initiative is

Unli Rice already works as a shared memory layer for agents. What a brand-new
user *doesn't* get today is the thing the founder had to build by hand: the
`_AI Context` document set — identity, voice, principles, guardrails, overlays
— that makes any LLM instantly useful about *them*.

Three additions, one adjustment:

1. **Profile Builder** — a first-run, form-based wizard that interviews the
   user and generates their own `00`–`04` (+ optional overlays) context
   documents as notes.
2. **Profiles** — one vault = one profile. A profile picker, profile templates
   (reusing the House Rules preset-gallery pattern that already shipped), and
   a designated **master profile** whose guardrail docs are copied into new
   profiles at creation.
3. **Mirror export** — a plain-markdown folder per profile that *any* LLM can
   be pointed at with zero setup: the context docs, a ≤2,500-char
   `MEMORY.md` capsule, and the existing `raw/` store. MCP stays the write
   channel; the folder is the universal read channel.
4. **The exception guardrail** — every generated guardrails doc and every
   House Rules preset gains the standing rule: *"If the user asks for
   something that contradicts these notes, ask whether it's a one-time
   exception or whether the note should change. One-time → note the exception
   in the session; change → append the change to the relevant note."*

## 2. Hard constraints (violating any of these fails review)

- **No local/on-device LLM.** One was built (MLX, bge-micro + Qwen3-1.7B),
  measured against the real corpus, and removed. `PROJECT_NOTES.md` records
  three independent failures of 1–3B models here, including a model-driven
  onboarding interview cut after a single real run. The Profile Builder is
  **deterministic forms only** — every step instant, testable, model-free.
  The intelligence lives in whatever agent the user connects.
- **No new write capability for machines.** `IngestRunner` stays
  `{created, appended, tagged}`; `JanitorRunner` stays `{tagged, flagged}`.
  Two tests assert those sets — keep them honest.
- **No delete, anywhere, still.** Cleanup remains: janitor flags → human
  decides. Size/messiness handling is *notices and suggestions*, never action.
- **Append-only log is the source of truth.** The mirror folder is a derived
  artifact (same status as `raw/` and notices): deleting it loses nothing;
  it is regenerated from the log. Never treat mirror files as writable inputs.
- **No credentials, no network calls, no cloud service** inside the app.
- **Concierge voice** for all copy (`_AI Context/02`): calm, short,
  non-judgmental, no hype. Onboarding must be skippable and minimal —
  Nuptia's rule is 4 fields before the app is useful; stay in that spirit.
- **App Store constraints hold** (sandbox, no new entitlements without
  reason); the app is currently Waiting for Review — build on `main` in a
  branch, don't destabilize release inputs (`project.yml`, entitlements).

## 2.5 Phase 0 — Make the app explain itself (the clarity pass)

The founder's own words: "I barely understand it myself." The features are
sound; the *presentation* is organized by internal machinery (janitor, ingest,
autonomy, daemon) instead of by user questions. This phase is pure UI/copy —
no engine changes — and it's the best fit for Antigravity's strengths. Do it
first: every later phase lands on top of this structure.

**Diagnosis (verified against `ContentView.swift` / `AutomationView.swift`):**

- "Home" is a raw note list — it never answers "what is this app doing for
  me?" A user opening the app sees 170 ingested session notes, not a status.
- Three different things are named "review": **Your Review** (the
  retrospective), **Review Notes** (the approval queue), and review flags.
- The screen that genuinely needs the human — the review queue — is hidden
  behind Advanced Mode, along with Notifications. The graph, a browsing toy,
  is top-level. Attention routing is exactly inverted.
- Builder vocabulary leaks everywhere: "janitorial autonomy levels",
  "background daemon configurations", "raw previews", "MCP".

**Proposed sidebar, organized by user question:**

| Row | Answers | Contains |
|---|---|---|
| **Home** | "What is this app doing for me?" | New status screen: one line "memory is working / not connected" (distilled Trust Center evidence), what happened lately (notices digest, replaces hidden Notifications), what needs you (review count → one tap), current profile name. Empty state = the Profile Builder invitation. |
| **Needs you** *(badge)* | "What's waiting on me?" | The review queue, merged with actionable notices. **Never hidden behind Advanced Mode** — if the app queues decisions for a human, the human must be able to find them. |
| **Notes** | "What does it know?" | Today's list + search. Graph becomes a view toggle inside Notes (list ⇄ map), not a top-level destination. Archived becomes a filter here. |
| **Setup** | "How do I wire it up?" | Merges Connect + House Rules + profile + the simple automation toggles ("Who you are" / "Your AI tools" / "What runs on its own"). |
| **Looking back** | "What happened this month/year?" | The retrospective, renamed away from "Your Review". |

Advanced Mode keeps: autonomy slider detail, janitor preview/run, ingest
internals, full Trust Center, export format menu. Simple mode shows outcomes,
not mechanisms.

**Vocabulary pass (GUI copy only — internal names stay):** janitor →
"tidying"; ingest → "collecting"; autonomy levels → describe outcomes ("only
while plugged in and idle" vs "whenever there's something to do"); never say
MCP without "connection" next to it. Every pane keeps one plain-language
sentence under its title (the Automation header already does this well —
extend the pattern, don't invent a new one).

## 3. Phase 1 — Profile Builder (the new-user path)

A form wizard, launched on first run of an empty vault (and re-runnable from
Connect). Each screen maps to one generated note. Every field optional except
a display name; every screen skippable; generation works with whatever was
filled in.

| Screen | Fields (all short free text unless noted) | Generates |
|---|---|---|
| Who you are | name/handle, what you do, mission in one sentence, quirks & working patterns (chips + free text: e.g. "many ideas, weak finisher", "mockups drift") | `Profile: identity` |
| How you want AI to talk | persona (picker: concierge / coach / peer / terse tool + custom), tone rules, formatting rules (chips: "short answers", "no emoji", "no hype"…) | `Profile: voice` |
| How you work | principles (repeatable rows), stack/tool defaults, things to always/never do | `Profile: principles` |
| Guardrails | non-negotiables (repeatable rows), **the exception rule pre-checked and always included** | `Profile: guardrails` |
| Projects | repeatable: name, one-liner, status | `Profile: projects` |
| Overlays (optional) | platform-specific rules, one note per overlay | `Profile: overlay <name>` |

Generation details:

- Notes written through `NoteService` with `source: "unlirice"`, tagged
  `profile` — same authorship convention as the onboarding seed notes.
- Also generate `Profile: index` — the `00_Master_Context` analogue: plain
  list of the other titles with one-line descriptions (plain paths/titles,
  not wiki-syntax-dependent, per the vault's own `00` file).
- Finishing the wizard lands the user on **Connect** with a House Rules draft
  pre-filled that references the profile notes by title — the wizard's output
  is only useful once a tool is connected, so make that the obvious next step.
- Re-running the wizard **appends** revisions to the existing notes (House
  Rules fingerprint/supersedes pattern already does exactly this — copy it).
  Titles are permanent; never mint `Profile: identity 2`.

## 4. Phase 2 — Profiles as vaults

The mechanism exists: `AppStore.switchDataFolder(to:)` reopens the store
against any folder and already resets corpus-scoped state. Build on it, don't
rebuild it.

- **Profile = named vault folder.** A profile registry (small JSON in app
  support, GUI-owned like `agent.json`) maps display name → folder path.
  The picker lives where vault switching lives today.
- **Master profile** = one designated profile. On new-profile creation, its
  `Profile: guardrails` (and optionally other `Profile:` notes, user chooses
  via checkboxes) are **copied** into the new vault as fresh `created` events,
  attributed `source: "unlirice"`, body noting the provenance ("copied from
  master profile <name>, <date>"). **Snapshot copy, not live sync** — live
  inheritance across independent append-only logs is a complexity trap;
  drift is a human decision, surfaced later at most as a suggestion.
- **Profile templates**: reuse the `HouseRulesPreset` gallery pattern
  (two-pane, preview, token counts, import/rename/duplicate/delete of
  *templates* — never notes). Ship 2–3 built-ins, e.g. "Solo developer",
  "Writer/researcher", "Minimalist". A template pre-fills the wizard;
  it never writes notes directly.
- Remember: each vault carries its own `house-rules.json` sidecar already —
  per-profile House Rules falls out for free. Verify the background agent
  (`unlirice-agent`) story: it serves the vault in `AgentSettings`; document
  clearly that routines run against the *active* profile only for now.

## 5. Phase 3 — Mirror export (the zero-setup, any-LLM channel)

Answering "is MCP needed?": MCP stays the **write** channel (it's what makes
multi-agent writes safe and attributable). The mirror folder is the **read**
channel for tools that can't or won't do MCP — a newbie can point ChatGPT,
Gemini, or anything with file access at one folder and get the whole context.

Per profile, a derived folder (default beside the vault, path user-visible):

```
<Profile Name> Export/
  00_Index.md            ← from Profile: index
  01_Identity.md         ← from Profile: identity
  02_Voice.md            …
  03_Principles.md
  04_Guardrails.md       ← includes the exception rule
  MEMORY.md              ← the ≤2,500-char capsule (see below)
  HOUSE_RULES.md         ← current House Rules revision
  RAW/                   ← the existing raw/ store (symlink or copy — decide
                            with sandbox constraints in mind)
```

- **Derived artifact rules** (same as `raw/`, notices): regenerated from the
  log, safe to delete, never read back as input. Regenerate on note change
  (debounced) and on profile switch. Export only the *latest* revision of
  append-revisioned notes (House Rules fingerprint precedent).
- **`MEMORY.md` capsule**: a note titled `Memory: capsule`. Its newest append
  is the current capsule; export writes only that. The app never generates
  its content (no model) — the House Rules text instructs connected agents to
  maintain it: *"At session end, rewrite `Memory: capsule` as a fresh append,
  ≤2,500 characters, containing only what a cold-start LLM must know."*
  Add a deterministic janitor-style check: if the latest capsule exceeds
  2,500 chars, raise a notice (suggestion only, as always).
- A read-only "what's in my export" screen beats silent file writing —
  show the folder path, last regeneration time, and an Open in Finder button.

## 6. Phase 4 — The exception guardrail

Enforcement is necessarily on the *client* LLM — this app is an MCP server
and cannot intercept the user's chat with their agent. So the rule ships as
standing text, everywhere context leaves the app:

- Appended to all House Rules presets and the generated `Profile: guardrails`.
- Suggested convention for the "change the notes" branch: the agent appends
  the change to the relevant `Profile:` note (append-only handles this
  natively — the old rule stays in history). For "one-time exception":
  agent proceeds, optionally `flag_for_review` if it thinks the rule itself
  looks stale. No new MCP tool is required; do not add one that lets an
  agent *rewrite* a guardrail.

## 7. Phase 5 — Housekeeping reports (mostly exists — extend, don't rebuild)

Already shipped: janitor (duplicates/orphans → review queue), per-run
budgets, `NoticeStore`, monthly/yearly `Retrospective`, Clean-up prompts that
delegate judgment to the connected LLM. Genuinely new, all deterministic:

- Size notices: `raw/` total size, note count, notes-per-tag saturation,
  oversized `Memory: capsule` — thresholds crossed → one keyed notice
  (the `Notice.key` replace-don't-spam rule already handles frequency).
- A "vault health" line in the Retrospective or Trust Center: counts only,
  suggestions only, no action buttons that mutate anything.

## 8. Explicit non-goals

- No local/on-device model (measured out — see constraint above). A user who
  wants local inference uses the existing loopback-only `RemoteSimilarity`
  seam with LM Studio/Ollama; do not extend it beyond loopback.
- No delete, no auto-merge, no auto-archive, ever, from any machine path.
- No cloud sync in this initiative (CloudKit remains deferred item #4).
- No model-driven onboarding interview. It was built and cut; don't rebuild it.
- No writing other apps' config files — that capability was deliberately
  removed (2026-07-21 dead-code sweep). Clipboard paste blocks only.

## 9. Suggested working order for Antigravity

1. **Phase 0 first** — restructure the sidebar, build the Home status screen,
   do the vocabulary pass. Pure UI/copy; touches `ContentView.swift`,
   `AutomationView.swift`, and view files only.
2. Sketch the Profile Builder screens + generated-note bodies (Phase 1) —
   pure UI + `NoteService` writes, no new architecture.
3. Profile registry + picker on top of `switchDataFolder` (Phase 2).
4. Mirror export (Phase 3) — note a manual "Export Notes…" multi-format menu
   already exists; extend that machinery into a standing per-profile folder
   rather than writing a second exporter. Agree on the derived-artifact rules
   with Claude before writing file-emitting code.
5. Guardrail text (Phase 4) and size notices (Phase 5) are small; fold them in
   wherever natural.

Bring the result back to the founder → Claude for review before merge.
Update `PROJECT_NOTES.md` as things land — that file stays honest or this
whole system rots.
