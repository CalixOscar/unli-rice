# PLAN — Mac 1.5 (10): Studio release, public guide, screenshots, App Store text

**Intent:** the founder's request, 2026-10-31, in their words: "update the public guide on
calmdownoscar.com add new screenshots and archive build 1.5 in xcode then add the text needed in
app store. I have logged in". No separate intent doc: this is release prep for work already built
under `docs/intent/INTENT-009-studio-redesign.md` (merged to `main` as `f6f70e4`).
**Tier:** 2 (App Store submission prep). Planner: Claude (Opus). Pre-mortem: Codex, in
`docs/dialogue/release-1.5.md`.
**Spec:** none (founder skip by scope: release prep for built work; each step's acceptance check is in §2).
**Stage:** draft, awaiting pre-mortem.
**Verified against:** `f6f70e4` (app repo `main`), `15bf5aa` (site repo `origin/main`), and App
Store Connect read on 2026-10-31: Mac 1.4 is Ready for Distribution, the newest Mac build is 1.4 (9),
and no 1.5 version exists.

## 0. Hard limits (unchanged from the guardrails)

- **No build upload, no Submit for Review, no TestFlight change.** Archiving locally is allowed.
  Upload and submit need the founder's own words in this session; ask at the end.
- Creating the 1.5 macOS version in App Store Connect and typing its text is inside the request
  ("add the text needed in app store"). Click **Save** only; never "Add for Review".
- Pricing, availability, release options (currently "Automatically release") stay as they are.
- Screenshots come from a throwaway demo vault and demo project folder, never the founder's notes
  or projects. No other studio app's icon on a demo card (the QA garden's recipe-box carries
  Nuptia's icon; do not reuse that garden).
- Capture (iOS) is not part of this release; its 1.3 (8) numbers do not move.
- Never toggle "Keep working with the window closed" in a debug build.
- ASC banner, 2026-10-31: the Apple Developer Program License Agreement was updated and must be
  accepted by the Account Holder before apps can be updated. If it blocks creating 1.5, stop and
  tell the founder; do not accept terms on their behalf.

## 1. What 1.5 contains (checked)

`git log 8d2189c..f6f70e4 --no-merges` holds only the Studio redesign (S1–S11) plus docs. User-
facing changes, from `docs/USER_GUIDE.md` §6 and the QA walk (plan-studio-redesign §4a):

- The sidebar is gone. Two tabs: **Studio** (⌘1) and **Guardrails & Grounding** (⌘2), and a gear at
  the top right. The app opens on Studio.
- Studio: a stack of project cards (folders under Setup › Folders with `.git`, `memory.md` or
  `PROJECT_NOTES.md`), flipped with ‹ ›, arrow keys, two-finger swipe, drag or click; project icon
  centred on the card; sticker FINE / NEEDS YOU / NO NOTES YET / CAN'T READ.
- Seven lights (Idea, Intent, Spec, Agents, Pre-mortem, Build, Post-mortem) from the files in the
  front project's `docs/`; "Next:" names the next step.
- Branches and Notes decks follow the front project; **This project / All projects** switch.
- Expanded Projects view: Refresh, list view, step details, **Copy prompt**.
- Guardrails & Grounding tab: Grounding (Open notes, Open the folder, Details) and Guardrails (Edit
  House Rules; Need you, Safety checks, Archived tiles).
- Gear menu: Setup, Trust Center, Archived notes, enabled extras (To do, Map, Your year so far,
  iPhone Capture), Rate Unli Rice.
- An unreadable project folder or scan root shows CAN'T READ instead of vanishing.
- VoiceOver names for the tabs, gear, cards, counter, lights and switches.

## 2. Steps

| # | Step | Label | Where |
|---|---|---|---|
| R1 | This plan; Codex pre-mortem; settle | planner | `claude/release-1.5` |
| R2 | Version bump to 1.5 (10), app + widget | build-light | `claude/release-1.5` |
| R3 | Demo vault + demo project folder | planner | scratchpad |
| R4 | Capture 7 screenshots, fit to 2880x1800, README | planner | `Screenshots/AppStore-Mac-2026-10-31/` |
| R5 | Release text: `docs/release/1.5-whats-new.md`, `APP_STORE_SUBMISSION.md` description + review notes, `docs/APPLE_REVIEW_GUIDE.md` | build | `claude/release-1.5` |
| R6 | Public guide + product page, new images | build | site repo, `claude/unlirice-1.5` |
| R7 | Merge R2/R5 to `main`; archive 1.5 (10) Release in Xcode's archive folder | planner | app `main` |
| R8 | ASC: create macOS 1.5, paste What's New, description, review notes; Save | planner | browser |
| R9 | Codex post-mortem; memory.md, PROJECT_NOTES; push; ask founder about upload, submit, guide go-live | planner | — |

### R2 — version bump (build-light)

`project.yml`: the two `MARKETING_VERSION: "1.4"` lines become `"1.5"` and the two
`CURRENT_PROJECT_VERSION: "9"` lines become `"10"` (the app target and the To Do widget extension,
which must match). The `1.3` / `8` lines (Capture targets) stay. Run `xcodegen generate`. Verify
with `grep -n -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' project.yml` and a Debug
`xcodebuild … build`. Commit `release: Mac 1.5 (10)`.

### R3 — demo data (planner)

Fresh folders under the session scratchpad, removed after R4:
- `demo-vault/` — about a dozen invented notes across the demo projects, written by `claude`,
  `codex` and `human` sources; House Rules saved from the Engineering Guardrails preset; one
  suspected-duplicate flag pending; one Claude Code check-in recorded by running the freshly built
  `unlirice-mcp` (from `swift build`) against `demo-vault` with an MCP initialize + one tool call.
- `demo-projects/` — five invented projects (Recipe Box, Garden Planner, Tide Clock, Trail Log,
  Budget Buddy), each a git repo with a few commits and one or two branches, a `memory.md`, and
  `docs/` files staged so the front cards show different lights and stickers. Each has a simple
  generated icon (plain shape + letter, drawn by script; no existing app art).
- The demo app is a copy of the QA wrapper with its own bundle id
  (`com.calmdownoscar.unlirice.demo-shots`), `LSEnvironment` pointing at `demo-vault/`, its scan
  root set to `demo-projects/` with `defaults write … unliRice.scanRoots`, and the binary rebuilt
  from the R2 commit (so About shows 1.5).

### R4 — screenshots (planner)

Window filling the screen, app in front (Stage Manager skews side-strip windows), Light
appearance. Trim the title bar and rounded corners and pad by repeating one plain pixel row to reach
16:10, then scale to 2880x1800; strip alpha (`sips -s format png` via JPEG round-trip or
`sips --deleteColorManagementProperties` + check `hasAlpha: no`). Set:

1. `01-studio.png` — Studio, This project, Recipe Box in front: icon, sticker, lights, Next, Branches, Notes.
2. `02-projects-expanded.png` — expanded Projects, step details with Copy prompt.
3. `03-all-projects.png` — All projects: every repo and every note.
4. `04-guardrails-grounding.png` — the second tab.
5. `05-house-rules.png` — House Rules editor with Engineering Guardrails.
6. `06-need-you.png` — a suspected duplicate with "Keep this one".
7. `07-ai-tools.png` — Setup › AI Tools, Claude Code connected.

README in the folder, same shape as `Screenshots/AppStore-Mac-2026-10-29/README.md`. Website
copies (R6) are made from these: 1400x875 WebP for the gallery, the hero as PNG.

### R5 — release text (build)

`docs/release/1.5-whats-new.md`, with this What's New (≤4000 characters, plain words):

```text
A new look for Unli Rice: it now opens on Studio, a picture of where your projects stand. What your AI knows and the rules it follows are one tab away.

• Studio shows your projects as a stack of cards. Flip through them with the arrows, the keyboard or a two-finger swipe. Each card shows the project's icon and whether it needs you. Choose the folders that hold your projects in Setup › Folders.
• Seven lights show how far the front project has come, from Idea to Post-mortem. Expand the deck and Copy prompt gives your AI tool a ready-made instruction for the next step.
• Branches and Notes follow the project in front. Switch to All projects to see every repo and every note.
• Guardrails & Grounding puts your notes, the folder your AI reads, your House Rules, what needs your decision, the safety checks and archived notes on one page.
• Setup, the Trust Center, archived notes and the extras you turned on are in the gear menu at the top right.
• A project folder Unli Rice can't open now says CAN'T READ instead of disappearing.
• VoiceOver now names the tabs, the gear menu, the project cards and the lights.
```

`APP_STORE_SUBMISSION.md`: a new "App Store description (2026-10-31, for 1.5)" section replacing
the 1.4 one (the 1.4 text stays in git history), identical except these three blocks:

```text
STUDIO: WHERE YOUR PROJECTS STAND
Point Unli Rice at the folders that hold your projects and Studio shows them as a stack of cards: which ones need you, their branches, the notes that belong to each, and how far each has come from idea to post-mortem. Copy prompt hands your AI tool the next step.

GROUNDING: WHAT YOUR AI KNOWS
Notes holds everything your assistants and you have written, each change attributed and dated. The folder your AI can read keeps a plain-Markdown copy for tools that can't use MCP. Details shows whether memory is working and which assistant last checked in.

EXTRAS, WHEN YOU WANT THEM
The gear menu holds Setup, the Trust Center and archived notes. Setup › Extras turns on To do, the note Map, Your year so far, separate memories, PDF and ZIP export and more. Each is off until you turn it on, and turning one off never deletes anything.
```

(STUDIO goes first, before GROUNDING; the GUARDRAILS block keeps its text with "Needs You" changed
to "Need you".) Review notes, "(1.5)" section replacing the 1.4 copy-paste block:

```text
Unli Rice 1.5 replaces the sidebar with two tabs, Studio and Guardrails & Grounding, and a gear menu at the top right. Studio shows the project folders the user chooses in Setup → Folders; with none chosen it explains how to add one. Nothing is removed from the app.

Unli Rice works on its own without any AI tool or account. To try it without an MCP client:
1. Open Unli Rice.app. Click the gear, then Setup → Folders, and choose any folder that contains a git repository. Studio shows it as a card; expand the deck to see its steps and Copy prompt.
2. Click the Guardrails & Grounding tab, then Open notes. Click New Note, add a title and text, save, then search for it.
3. On the same tab click Edit House Rules, pick a template such as Engineering Guardrails, click Use as Draft, then Save to notes.
4. Click the gear, then Trust Center, then Run checks.
5. Open the gear → Setup → Extras and turn on Map; Map appears in the gear menu.
```

followed by the unchanged MCP block, reviewer-guide link and closing paragraph. Builder checks
every click path in steps 1–5 against the source (`StudioView.swift`, `GuardrailsGroundingView.swift`,
the gear menu, `SetupView`/Extras) and reports any that do not exist as written; it does not
reword them itself. `docs/APPLE_REVIEW_GUIDE.md`: its "Names below are the buttons in Unli Rice
1.4…" walkthrough is rewritten to the same five steps for 1.5.

### R6 — public guide (build, site repo)

New worktree off `origin/main` (`15bf5aa`) on branch `claude/unlirice-1.5`. Do not touch the main
checkout (it is on `docs/norsksti-guided-flow` with uncommitted work). Cherry-pick the unpushed 1.4
commits `5e40de3` and `cea1223` from `claude/unlirice-1.4` first (they were never published, so the
live guide still describes 1.3), then apply the 1.5 changes on top:

- `unlirice/user_guide.html`
  - §2: "Setup → AI Tools (Setup is the last row in the sidebar)" → "Setup → AI Tools (Setup is in
    the gear menu at the top right)". Figure caption unchanged apart from that.
  - §3: House Rules location → "**Edit House Rules**, on the Guardrails & Grounding tab". Profile
    Builder note: "turn on **Separate memories** in **Setup → Extras**, then use **Setup →
    Separate memories**" (drop "Start Profile on Home"; Home is gone — builder verifies the
    button still exists anywhere and reports if it does).
  - §7 retitled "The window": replaced with the text of `docs/USER_GUIDE.md` §6 (app repo, `main`)
    turned into this page's HTML conventions (`<h3>` per tab, `<p><strong>Name.</strong> …</p>`
    per item), followed by the 1.4 branch's Setup and Extras paragraphs with "the sidebar" changed
    to "the gear menu". The To do paragraph (derived vs AI-flagged) and the branch-graph caveat
    paragraph are kept word for word: To do under Extras, the caveat under Studio's Branches.
  - A new figure in §7 with `unli-rice-shot-studio.webp` and a caption naming the deck, the
    lights and Branches/Notes.
  - Contents list: "The panes" → "The window".
- `unlirice/index.html`: hero image becomes Studio (`unli-rice-hero.png`, from `01-studio.png`);
  hero alt text describes Studio; the four gallery images become Guardrails & Grounding, House Rules,
  Connect, All projects with captions "Guardrails & Grounding — what your AI knows and must do",
  "House Rules — what every assistant reads first", "Connect — one config block per tool",
  "Studio — every project, branch and note". To do and Notes images drop out of the gallery.
- Images in `apps/assets/`: replaced or added, WebP 1400x875 except the hero PNG. Old files no
  longer referenced anywhere (`grep -r` the whole site) are deleted.
- Verify: every `src=` resolves to a file; HTML opens in a local `python3 -m http.server` and the
  page renders with no missing images; no other page references a deleted image.
- Commit on the branch, push the branch. **Do not merge to the site's `main`**: that deploys
  (Vercel). Going live is the founder's call (R9) because the guide would describe 1.5 before
  it is on the App Store.

### R7 — archive (planner)

Merge `claude/release-1.5` into `main` (`--no-ff`) after R2 and R5 are reviewed; push. Archive
from `main` with `xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -configuration Release
-destination 'generic/platform=macOS' -archivePath "~/Library/Developer/Xcode/Archives/2026-10-31/Unli Rice 1.5 (10).xcarchive" archive`
so it appears in Xcode's Organizer. Check the archive's `Info.plist` (1.5 / 10) and the embedded
widget and `unlirice-mcp` versions. No export, no upload.

### R8 — App Store Connect (planner, browser)

Unli Rice → macOS App → "+" → 1.5. Paste What's New, the 1.5 description and the review notes;
Promotional Text, keywords, URLs unchanged. Save. Read each field back after saving. Leave
screenshots to the founder (drag the folder, then check order 01–07) unless they ask me to
upload them. Do not attach a build.

## 3. Open questions for the pre-mortem

1. Is holding the site at a pushed branch (not live) right, or should the 1.4-accurate part go
   live now, since 1.4 is live and the public guide still describes 1.3?
2. Is seven screenshots, three of them Studio, the right balance for a store page whose listing
   copy leads with memory, not projects?
3. Anything in the 1.5 text that overstates what a new install with no project folders sees?
