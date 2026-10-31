# PLAN — Mac 1.5 (10): Studio release, public guide, screenshots, App Store text

**Intent:** the founder's request, 2026-10-31, in their words: "update the public guide on
calmdownoscar.com add new screenshots and archive build 1.5 in xcode then add the text needed in
app store. I have logged in". No separate intent doc: this is release prep for work already built
under `docs/intent/INTENT-009-studio-redesign.md` (merged to `main` as `f6f70e4`).
**Tier:** 2 (App Store submission prep). Planner: Claude (Opus). Pre-mortem: Codex, in
`docs/dialogue/release-1.5.md`.
**Spec:** none. Planner's call, not a founder waiver: release prep adds no behaviour; each step's acceptance check is in §2. Reported to the founder in R9.
**Stage:** 4 (settled against the pre-mortem; §4 answers it).
**Verified against:** `f6f70e4` (app repo `main`), `15bf5aa` (site repo `origin/main`), and App
Store Connect read on 2026-10-31: Mac 1.4 is Ready for Distribution, the newest Mac build is 1.4 (9),
and no 1.5 version exists.

## 0. Hard limits (unchanged from the guardrails)

- **No build upload, no Submit for Review, no TestFlight change.** Archiving locally is allowed.
  Upload and submit need the founder's own words in this session; ask at the end.
- Creating the 1.5 macOS version in App Store Connect and typing its text is inside the request,
  made by the founder in this session ("archive build 1.5 in xcode then add the text needed in app
  store"). It authorises this session only, not a later executor. Click **Save** only; never "Add
  for Review", never attach a build.
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
  the top right. The app opens on Studio once set up; a fresh install shows the first-run screen
  (`AppStore.swift:686–692`), whose **Use Unli Rice without connecting** opens Details
  (`FirstRunView.swift:48–53`). With no projects, Studio shows **Start your first project** (an
  Idea Clinic link) and **Pick a folder** (`GardenCrateView.swift:105–119`); lights, Next and the
  scope switch appear only with a front card (`StudioView.swift:9–13`).
- Studio: a stack of project cards (folders under Setup › Folders with `.git`, `memory.md` or
  `PROJECT_NOTES.md`), flipped with ‹ ›, arrow keys, two-finger swipe, drag or click; project icon
  centred on the card; sticker FINE / NEEDS YOU / NO NOTES YET / CAN'T READ.
- Seven lights (Idea, Intent, Spec, Agents, Pre-mortem, Build, Post-mortem) read from the front
  project's open plan in `docs/`: approval headers, the AGENTS import, the dialogue's turns and
  state, the plan's stage number (`BuildGate.swift:75–104`); "Next:" names the next step.
- Branches and Notes decks follow the front project; **This project / All projects** switch.
- Expanded Projects view: Refresh, list view, step details, **Copy prompt**.
- Guardrails & Grounding tab: Grounding (Open notes, Open the folder, Details) and Guardrails (House
  Rules card with an **Edit** button; Need you, safety (caption "Not checked yet" until run) and
  Archived tiles). Projects is no longer an extra: Studio always shows it (`StudioView.swift:32–34`).
  **Start Profile** is still on Details when Separate memories is on (`HomeView.swift:158–162`).
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
| R4 | Capture 7 screenshots, fit to 2880x1800, README; walk the review-notes steps on an empty vault | planner | `Screenshots/AppStore-Mac-2026-10-31/` |
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
- The demo projects are generated by a script against the real `BuildGate` header and dialogue
  contract (approved/draft headers, `@AGENTS.md`, planner/reviewer turns), and each card's lights
  are checked on screen against what the script meant. Git author is "Demo <demo@example.com>".
- Nothing in a shot may show a real path, real name or real note: Trust Center is left out (it
  prints the log path), and every final image is looked at before it is kept.

### R4 — screenshots (planner)

Window filling the screen, app in front (Stage Manager skews side-strip windows), Light
appearance. Trim the title bar and rounded corners and pad by repeating one plain pixel row to reach
16:10 (no UI cropped), then scale to 2880x1800 and flatten onto an opaque background with PIL
(`convert("RGB")`). Accept an image only when `sips -g pixelWidth -g pixelHeight -g hasAlpha`
reads 2880, 1800, `no`. Set (Notes replaces a third Studio shot, per pre-mortem 7):

1. `01-studio.png` — Studio, This project, Recipe Box in front: icon, sticker, lights, Next, Branches, Notes.
2. `02-projects-expanded.png` — expanded Projects, step details with Copy prompt.
3. `03-guardrails-grounding.png` — the second tab.
4. `04-notes.png` — Open notes: every note, with who wrote it.
5. `05-house-rules.png` — House Rules editor with Engineering Guardrails.
6. `06-need-you.png` — a suspected duplicate with "Keep this one".
7. `07-ai-tools.png` — Setup › AI Tools, Claude Code connected.

Then a second launch of the demo app on an **empty** vault (no scan root) to walk review-notes
steps 1–6 exactly as written; any step that fails goes back into R5 before R8.

README in the folder, same shape as `Screenshots/AppStore-Mac-2026-10-29/README.md`. Website
copies (R6) are made from these: 1400x875 WebP for the gallery, the hero as PNG.

### R5 — release text (build)

`docs/release/1.5-whats-new.md`, with this What's New (≤4000 characters, plain words):

```text
A new look for Unli Rice: two tabs instead of a sidebar. Studio is a picture of where your projects stand. Guardrails & Grounding shows what your AI knows and the rules it follows.

• Studio shows your projects as a stack of cards. Pick a folder that holds your projects and each one becomes a card with its icon and whether it needs you. Flip through them with the arrows, the keyboard or a two-finger swipe.
• Seven lights show how far the front project's plan has come, from Idea to Post-mortem, read from the plan, approvals and reviews in its docs folder. Expand the deck and Copy prompt gives your AI tool a ready-made instruction for the next step.
• Branches and Notes follow the project in front. Switch to All projects to see the branches of every project and all your notes.
• Guardrails & Grounding puts your notes, the folder your AI reads, your House Rules, what needs your decision, the safety checks and archived notes on one page.
• Setup, the Trust Center, archived notes and the extras you turned on are in the gear menu at the top right.
• A project folder Unli Rice can't open now says CAN'T READ instead of disappearing.
• VoiceOver now names the tabs, the gear menu, the project cards and the lights.
```

`APP_STORE_SUBMISSION.md`: a new "App Store description (2026-10-31, for 1.5)" section replacing
the 1.4 one (the 1.4 text stays in git history), identical except these three blocks:

```text
STUDIO: WHERE YOUR PROJECTS STAND
Pick the folders that hold your projects and Studio shows them as a stack of cards: which ones need you, their branches, the notes that belong to each, and how far each plan has come from idea to post-mortem. Copy prompt hands your AI tool the next step.

GROUNDING: WHAT YOUR AI KNOWS
Notes holds everything your assistants and you have written, each change attributed and dated. The folder your AI can read keeps a plain-Markdown copy for tools that can't use MCP. Details shows whether memory is working and which assistant last checked in.

EXTRAS, WHEN YOU WANT THEM
The gear menu holds Setup, the Trust Center and archived notes. Setup › Extras turns on To do, the note Map, Your year so far, separate memories, PDF and ZIP export and more. Each is off until you turn it on, and turning one off never deletes anything.
```

and the GUARDRAILS block replaced (pre-mortem 2: House Rules are a note assistants find, not text
injected into every session):

```text
GUARDRAILS: WHAT YOUR AI SHOULD ALWAYS DO
House Rules are your standing instructions, saved as a note your assistants find when they check your notes at the start of a session: what to read first, what's worth remembering, how to attribute their work, and when to stop and ask you. Start from a built-in template, including Engineering Guardrails for coding assistants, or import your own. Need you collects only what's waiting on your decision. The Trust Center checks that your memory is readable and writable, shows which assistants have connected, and makes verified recovery points before big changes.
```

Order: intro, STUDIO, GROUNDING, GUARDRAILS, A PERMANENT, ATTRIBUTED RECORD, EXTRAS, STAYS OUT OF
YOUR WAY, closing paragraphs. Review notes, "(1.5)" section replacing the 1.4 copy-paste block:

```text
Unli Rice 1.5 replaces the sidebar with two tabs, Studio and Guardrails & Grounding, and a gear menu at the top right. Nothing is removed from the app.

Unli Rice works on its own without any AI tool or account. To try it without an MCP client:
1. Open Unli Rice.app. On the first screen, click "Use Unli Rice without connecting".
2. Click the Studio tab, then Pick a folder, and choose a folder that contains one or more git repositories. Each repository becomes a card with its branches and notes; the expand button in the deck's corner shows its steps and Copy prompt.
3. Click the Guardrails & Grounding tab, then Open notes. Click New Note, add a title and text, save, then search for it.
4. On the same tab, click Edit beside House Rules, then Choose Template…, pick Engineering Guardrails, click Use as Draft, then Save to notes.
5. Click the gear, then Trust Center, then Run checks.
6. Click the gear, then Setup, then Extras, and turn on Map; Map appears in the gear menu.
```

followed by the unchanged MCP block, reviewer-guide link and closing paragraph. Builder checks
every click path in steps 1–6 against the source (`FirstRunView.swift`, `GardenCrateView.swift`,
`GuardrailsGroundingView.swift`, `ConnectView.swift`, `StudioToolbar.swift`, `SetupView.swift`)
and reports any that do not exist as written; it does not reword them itself. The planner walks
them in the running app in R4. `docs/APPLE_REVIEW_GUIDE.md`: its "Names below are the buttons in
Unli Rice 1.4…" walkthrough is rewritten to the same six steps for 1.5.

### R6 — public guide (build, site repo)

New worktree off `origin/main` (`15bf5aa`) on branch `claude/unlirice-1.5`. Do not touch the main
checkout (it is on `docs/norsksti-guided-flow` with uncommitted work). Cherry-pick the unpushed 1.4
commits `5e40de3` and `cea1223` from `claude/unlirice-1.4` first (they were never published, so the
live guide still describes 1.3), then apply the 1.5 changes on top:

- `unlirice/user_guide.html`
  - §2: "Setup → AI Tools (Setup is the last row in the sidebar)" → "Setup → AI Tools (Setup is in
    the gear menu at the top right)". Figure caption unchanged apart from that.
  - §3: House Rules location → "the House Rules card on the Guardrails & Grounding tab (its
    **Edit** button)". Profile Builder note: "turn on **Separate memories** in **Setup → Extras**,
    then use **Setup → Separate memories**, or **Start Profile** under **Details** on the
    Guardrails & Grounding tab".
  - §7 retitled "The window", with the exact HTML given in §5 of this plan. The builder pastes it;
    it does not rewrite it.
  - A new figure in §7 with `unli-rice-shot-studio.webp` and a caption naming the deck, the
    lights and Branches/Notes.
  - Contents list: "The panes" → "The window".
- `unlirice/index.html`: hero image becomes Studio (`unli-rice-hero.png`, from `01-studio.png`);
  hero alt text describes Studio; the four gallery images become Guardrails & Grounding, House Rules,
  Connect, Notes with captions "Guardrails & Grounding — what your AI knows and must do",
  "House Rules — what every assistant reads first", "Connect — one config block per tool",
  "Notes — searchable, tagged, append-only". The To do image drops out of the gallery.
- Images in `apps/assets/`: replaced or added, WebP 1400x875 except the hero PNG. Old files no
  longer referenced anywhere (`grep -r` the whole site) are deleted.
- Verify: every `src=` resolves to a file; HTML opens in a local `python3 -m http.server` and the
  page renders with no missing images; no other page references a deleted image.
- Commit on the branch, push the branch. **Do not merge to the site's `main`**: that deploys
  (Vercel). Going live is the founder's call (R9) because the guide would describe 1.5 before
  it is on the App Store. Keep the 1.4 cherry-picks as their own commits so a 1.4-only guide can
  be published first if the founder chooses that (pre-mortem 8).

### R7 — archive (planner)

Merge `claude/release-1.5` into `main` (`--no-ff`) after R2 and R5 are reviewed; push. Archive
from `main` with `xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -configuration Release
-destination 'generic/platform=macOS' -archivePath "$HOME/Library/Developer/Xcode/Archives/2026-10-31/Unli Rice 1.5 (10).xcarchive" archive
-allowProvisioningUpdates` so it appears in Xcode's Organizer. Re-read ASC's newest Mac build
number just before (still 9 → 10 is free). Check: the app's `Info.plist` reads 1.5 / 10; the To Do
widget's reads 1.5 / 10; the three helpers copied in by `project.yml:271–274` are present and pass
`codesign --verify --deep --strict` (the MCP helper has no marketing version of its own; its
protocol version `0.1.0` is unrelated). No export, no upload.

### R8 — App Store Connect (planner, browser)

Unli Rice → macOS App → "+" → 1.5. Paste What's New, the 1.5 description and the review notes;
Promotional Text, keywords, URLs unchanged. Save. Read each field back after saving. Leave
screenshots to the founder (drag the folder, then check order 01–07) unless they ask me to
upload them. Do not attach a build.

## 3. Open questions (answered in §4)

1. Is holding the site at a pushed branch (not live) right, or should the 1.4-accurate part go
   live now, since 1.4 is live and the public guide still describes 1.3?
2. Is seven screenshots, three of them Studio, the right balance for a store page whose listing
   copy leads with memory, not projects?
3. Anything in the 1.5 text that overstates what a new install with no project folders sees?

## 4. Pre-mortem answers (`docs/dialogue/release-1.5.md`)

1. Accepted. §1 and the R5 texts carry the first-run screen and the empty Studio; review steps
   start from "Use Unli Rice without connecting" and use Pick a folder. R4 walks them on an empty vault.
2. Accepted. GUARDRAILS block rewritten: House Rules are a note assistants find.
3. Accepted. `$HOME` path, ASC re-check, widget version and helper signatures in R7.
4. Accepted. Button names are Edit (House Rules card), Choose Template…, Use as Draft, Save to notes.
5. Accepted. §7 site copy is written here (§5), not assembled by the builder; Projects is not an
   extra; Start Profile is under Details.
6. Accepted. Lights described as read from the plan, approvals and reviews; demo projects built
   against `BuildGate`; "All projects" copy says every project's branches and all your notes.
7. Accepted. PIL flattening plus a `sips` check per file; Trust Center left out; Notes replaces
   All projects as shot 4 (the third Studio shot).
8. Accepted in part. The 1.4 commits stay separate so they can go live alone; when to publish is
   asked of the founder in R9 with Codex's recommendation (1.4 guide now, 1.5 at release).
9. Accepted. The founder's words for creating the version are quoted in §0; the spec skip is
   recorded as the planner's call and reported to the founder; merging stays with the planner.

## 5. Site §7 copy (R6 pastes this verbatim)

```html
<section id="panes">
<h2>7. The window</h2>
<p>Since 1.5 the window has two tabs at the top, <strong>Studio</strong> (&#8984;1) and <strong>Guardrails &amp; Grounding</strong> (&#8984;2), and a gear button at the top right. Once you are set up the app opens on Studio. The very first time, it opens on the connect screen instead; <strong>Use Unli Rice without connecting</strong> skips it. Names below are the ones on the buttons.</p>
<h3>Studio</h3>
<p>Your projects at a glance. A project is any folder, one level inside the folders you chose, that holds a <code>.git</code> folder, a <code>memory.md</code> or a <code>PROJECT_NOTES.md</code>. With none chosen yet, Studio offers <strong>Pick a folder</strong>.</p>
<p><strong>Projects.</strong> A stack of cards, one per project, newest activity first. Flip through it with the &lsaquo; &rsaquo; buttons, the arrow keys, a two-finger swipe, a drag, or a click on a card behind. If the project has an app icon or logo, it sits in the middle of its card. The sticker says <strong>FINE</strong>, <strong>NEEDS YOU</strong> (it has to-dos or flags waiting), <strong>NO NOTES YET</strong>, or <strong>CAN&rsquo;T READ</strong> when Unli Rice cannot open the folder; hover over the sticker to see why.</p>
<p><strong>The seven lights.</strong> Idea, Intent, Spec, Agents, Pre-mortem, Build and Post-mortem, for the front project&rsquo;s open plan. They are read from the files in its <code>docs/</code> folder: whether the intent and spec say they are approved, whether <code>AGENTS.md</code> is there, and whether the review in <code>docs/dialogue/</code> has been answered and settled. A file that exists but is not approved yet shows as a draft, not done. <strong>Next:</strong> names the next step.</p>
<p><strong>Branches and Notes.</strong> They follow the front project: its git branches, and the notes that belong to it (a note tagged with the project&rsquo;s folder name counts). Switch to <strong>All projects</strong> at the top right to see the branches of every project and all your notes; clicking a repo there brings that project to the front. The branch view shows which branch tips are not on any remote this clone has fetched. That is worth reading precisely, because it is a narrower claim than it sounds: it compares the tip of each branch against the remote refs already fetched here. It does not walk individual commits, and it cannot speak for a remote it has never fetched from. Read it as &ldquo;nothing I know about has this&rdquo;, which is still the useful warning.</p>
<p><strong>Expand.</strong> Every deck has an expand button in its corner. The enlarged Projects view adds Refresh, a list view, each step&rsquo;s details and <strong>Copy prompt</strong>, which copies a ready-made instruction for your AI tool about the next step. <strong>All decks</strong>, or Esc, goes back.</p>
<h3>Guardrails &amp; Grounding</h3>
<p><strong>Grounding</strong> is what your AI knows: your notes and the folder your AI can read, with <strong>Open notes</strong> (search, read, tag, and open any note&rsquo;s history), <strong>Open the folder</strong> (covered in <a href="#mirror">pointing a tool at the folder</a>), and <strong>Details</strong>: what your AI currently knows about you, which assistant last used the memory, and what happened recently.</p>
<p><strong>Guardrails</strong> is what it should always do. The House Rules card shows your rules, with <strong>Edit</strong> to change them (see <a href="#profile">telling your agents who you are</a>). Under it, three tiles: <strong>Need you</strong>, the flags waiting on a decision, such as a suspected duplicate with a <strong>Keep this one</strong> button; the safety tile, which opens the Trust Center; and <strong>Archived</strong>, everything hidden from the default listings, each one a click from coming back.</p>
<p><strong>Trust Center.</strong> Read-only checks: whether the log and its folder are writable, which MCP clients have checked in, whether a recovery point exists, and what the background worker is doing. Client check-ins record the client&rsquo;s name and version, timestamps, the tool name, and whether it succeeded &mdash; never tool arguments, and never note content.</p>
<h3>The gear menu</h3>
<p><strong>Setup</strong>, <strong>Trust Center</strong> and <strong>Archived notes</strong>, then any extras you have switched on (<strong>To do</strong>, <strong>Map</strong>, <strong>Your year so far</strong>, <strong>iPhone Capture</strong>), and <strong>Rate Unli Rice</strong>.</p>
<p><strong>Setup</strong> has these tabs: <strong>AI Tools</strong> (the Connect screen), <strong>Folders</strong> (the folders Studio reads), <strong>What runs on its own</strong> (one switch for background work, with the details behind it: keeping it working with the window closed, how hard the janitor looks, and what brings documents and sessions in), and <strong>Extras</strong>. <strong>Separate memories</strong> appears as a tab when that extra is on, or whenever you already have more than one.</p>
<h3>Extras</h3>
<p>Each extra is off on a new install until you turn it on in <strong>Setup &rarr; Extras</strong>, and turning one off only removes its button &mdash; nothing is deleted. If you used To do before 1.4, it stays on after the update.</p>
<p><strong>To do.</strong> Two kinds of item live here and they behave differently, which is the thing to learn about this pane. <em>Derived</em> items are computed from the state that makes them true, and they have no checkbox because there is nothing to check &mdash; the item goes away when the state does. A stored checklist drifts from reality the moment someone does the work without ticking the box; deriving is how this half stays honest. It reads each project&rsquo;s <code>memory.md</code> for a declared next step, and falls back to the last published repository snapshot when it cannot get a live read, which is why an item can be labelled &ldquo;as of the last snapshot&rdquo;. <em>AI-flagged</em> items are the other kind: an agent that spots something worth doing writes an ordinary note and tags it <code>todo</code>. Those are stored, like any note, and they carry a <strong>Done</strong> button that archives the note behind them. The To Do widget works whether or not this extra is on.</p>
<p><strong>Map.</strong> The link graph &mdash; notes as nodes, double-bracket links as edges.</p>
<p><strong>Your year so far.</strong> A retrospective read back to you from notes you already have. Its notices still open it when the extra is off.</p>
<p><strong>Separate memories.</strong> Profiles: separate note logs, each in its own folder, with one marked as the master. A way to keep unrelated bodies of work apart &mdash; not a way to change how agents behave. The Profile Builder lives here too.</p>
<p><strong>PDF and ZIP export.</strong> Adds those two formats to File &rarr; Export Notes, beside Markdown.</p>
<p><strong>iPhone Capture.</strong> Adds the free iPhone app&rsquo;s card to the gear menu.</p>
<p>Two extras run in the background rather than adding a button. <strong>Import files from your folders</strong> reads the Markdown and text files in Setup &rarr; Folders and adds them as notes; with it off, adding a folder only lets Studio read its git details. <strong>Spot duplicate notes</strong> lets the janitor suggest merging notes that look alike, and is the only thing that uses the optional local embedding server. Both obey their switch whether the work runs on a schedule or from a button, and Claude Code sessions and the Notes for Unli Rice drop box are imported either way.</p>
</section>
```
