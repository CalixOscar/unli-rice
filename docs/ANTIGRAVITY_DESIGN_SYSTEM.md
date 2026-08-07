# Battleplan: Bring Unli Disk's design system to Unli Rice

**Audience:** Google Antigravity, doing a first exploration/UI pass on this.
**Authored by:** Claude Code, 2026-08-07, at the founder's request.
**Branch:** all work on a feature branch (suggested: `feature/design-system`) off
`main`. Unli Rice is mid-feature on `feature/sync-and-capture` right now — don't
build on top of that branch's uncommitted state; branch from `main`.
**Authorization note:** `_AI Context/04_Guardrails.md` scopes Antigravity to
first-look ideation. This doc needs the same one-time exemption the two prior
battleplans (`ANTIGRAVITY_BATTLEPLAN.md`, `ANTIGRAVITY_IOS_CAPTURE.md`) needed,
for the same reason — get it from the founder before implementation starts.
**Status of this doc:** a plan, not a spec. The token *values* in section 3 are
a recommendation, not a lock — the mechanics in section 4 are the part that
should survive contact with reality.

---

## 0. Read these first, in order

1. `PROJECT_NOTES.md` — architecture record. Nothing in this doc touches the
   event log, sync, or capture pipeline. This is a styling-layer-only change.
2. `AGENTS.md` — identify as `source: "antigravity"` if you touch the
   `unlirice` MCP server (you shouldn't need to for this).
3. `Sources/UnliRice/Theme.swift` (Unli Rice, 28 lines) and
   `../UnliDisk/Packages/UnliDiskPhotos/Sources/UnliDiskPhotos/Theme.swift`
   (Unli Disk, ~285 lines) — read both in full before writing anything. The
   second file *is* the spec; this doc just explains how to land it here.
4. `../UnliDisk/Sources/UnliDisk/Views/LiquidGlass.swift` — the glass modifier
   Unli Disk uses everywhere. Self-contained, ~80 lines, no dependencies on
   the rest of UnliDisk. Portable as-is.

---

## 1. What "same design style" concretely means

The founder asked for Unli Rice to look like Unli Disk. Today they don't share
a design system at all — they were built independently and it shows:

| | Unli Disk | Unli Rice |
|---|---|---|
| Color scheme | Adaptive light/dark, real `NSColor`/`UIColor` dynamic providers | Dark-only. `Theme.swift:5` claims "adapted for light/dark via NSColor's dynamic provider" but every token is a flat `Color(red:green:blue:)` literal — **the comment is stale, the app has never actually followed the system appearance.** |
| Material | Real Liquid Glass on macOS 26 (`.glassEffect`), honest `.ultraThinMaterial` + hairline fallback below it, one `liquidGlass()`/`liquidGlassCapsule()` call site everywhere | `Theme.panel = Color.black.opacity(0.35)` — a flat translucent fill, no blur, no macOS 26 path, no fallback logic |
| Token model | Semantic tokens (`bgMain`, `bgCard`, `textPrimary`/`Secondary`/`Light`, `accentColor`, `borderLight`, `solidFill`/`onSolidFill`/`solidStroke`, `bgField`, `controlDisabledFill`) plus two reusable `View` extensions (`solidControl`, `selectedControl`) that every button/row goes through | Nine flat tokens (`background`, `panel`, `border`, `ink`, `inkDim`, `accent`, `accentSoft`, `onAccent`, `brass`, `crit`, `violet`, `emerald`), no shared control helpers — each of the 14 view files rolls its own button/card chrome by hand |
| Contrast discipline | Every "on-X" pairing has a measured-ratio comment (`Theme.swift:15-23` in UnliRice is actually the one place this *is* already done well — keep it) | Same good pattern exists for `onAccent`; extend it to the new tokens |
| Category/semantic separation | Explicit split: category colors (*what a thing is*) vs semantic colors (*what is true about it*), documented so nobody recolors one and silently drags the other | Not applicable yet — Unli Rice has no category-colored data, only status colors (`crit`, `emerald`, `violet`, `brass`) |

The gap isn't "different colors," it's that Unli Disk has an actual *system*
(adaptive tokens + a glass material + shared control helpers) and Unli Rice
has a flat palette that every view file consumes by hand. Porting the palette
alone would leave the mechanical gap; porting the system is the real ask.

## 2. Scope

**In scope:** `Sources/UnliRice/Theme.swift`, a new `LiquidGlass.swift` (same
file, ported near-verbatim), and every call site across the ~14 files below
that currently reference the old flat tokens.

**Out of scope:** `Sources/UnliRiceCapture/` (iOS — different `View` helpers,
different constraints, do it as a follow-on once the Mac side is settled and
approved) and anything in `UnliRiceCore` (no SwiftUI there today; keep it that
way).

Call-site volume, so the size of this is not a surprise mid-task:

```
Sources/UnliRice/ContentView.swift               129 uses of Theme.
Sources/UnliRice/ProfileBuilderView.swift          58
Sources/UnliRice/AutomationView.swift              46
Sources/UnliRice/HomeView.swift                    42
Sources/UnliRice/ConnectView.swift                 42
Sources/UnliRice/RetrospectiveView.swift           38
Sources/UnliRice/TrustCenterView.swift             33
Sources/UnliRice/NoteGraphView.swift               33
Sources/UnliRice/ProfileManagerView.swift          30
Sources/UnliRice/HouseRulesPresetGalleryView.swift 23
Sources/UnliRice/NeedsYouView.swift                22
Sources/UnliRice/MirrorExportView.swift            17
Sources/UnliRice/NoticeCenterView.swift            15
Sources/UnliRice/SetupView.swift                    9
```

~537 call sites total. This is exactly the kind of long mechanical pass this
doc exists to hand off rather than have a human grind through by hand.

## 3. The one decision the founder should confirm before the mechanical pass

**Keep Unli Rice's teal/indigo-space identity, ported onto Unli Disk's
adaptive/glass *mechanics* — do not adopt Unli Disk's indigo/cyan palette
values wholesale.** Recommended default; flag it, don't silently decide it:

- The two apps are sold as an App Store Bundle (`ANTIGRAVITY_IOS_CAPTURE.md`
  §4) — same relationship as, say, Apple's own apps, which share materials
  and chrome but keep distinct accent identities per app. A shared *system*
  reads as "same family"; a shared *palette* reads as "the same app twice."
- Unli Rice's "invisible by default" positioning (security-camera, not a pet
  — see product memory) has leaned dark-only and moody on purpose. Adding
  real light-mode support is still correct (it's what "adaptive" means and
  what fixes the stale-comment bug in §1), but the dark variant should stay
  recognizably *this* app's dark, not Unli Disk's Cosmic Obsidian.
- If the founder wants full palette parity instead (identical hex values,
  not just identical structure), that's a one-line change to §4's token table
  below — the mechanics don't change either way.

**If this is wrong, stop and ask before doing the 537-call-site pass** — it's
expensive to redo.

## 4. The mechanical work

### 4a. Rewrite `Theme.swift`

Model the shape directly on `UnliDiskPhotos/Theme.swift`, keeping Unli Rice's
current hues as the dark-mode values and designing light-mode counterparts
that hold the same relationships (teal accent, indigo-space ground) the way
Unli Disk's light mode holds its own:

- `bgMain` — dark: current `background` (`#0B0D15`-ish indigo-space). Light:
  a light counterpart in the same hue family, not Unli Disk's Cloud Sky blue.
- `bgCard` — dark: current `panel` intent, but as a real color, not
  `.black.opacity(0.35)` (glass now supplies the translucency — see 4b).
- `textPrimary`/`textSecondary`/`textLight` — replace `ink`/`inkDim` with the
  three-tier model; check every pairing against its background at
  4.5:1 minimum, same rigor as Unli Disk's `Theme.swift:15-23` comment and
  the WCAG note on `PhotoGridFilter.tint` (`onTint`, `~245-284`) — copy that
  reasoning method, not just the numbers.
- `accentColor` — dark: current `accent` (`#00F5D4` neon teal). Light: a
  deepened/saturated variant that survives on a light ground (same move Unli
  Disk made for indigo → cyan).
- `borderLight`, `solidFill`/`onSolidFill`/`solidStroke`, `bgField`,
  `controlDisabledFill` — new tokens, no direct Unli Rice equivalent today;
  needed because §4c below expects them.
- Keep `crit`/`violet`/`emerald`/`brass` (status colors) — Unli Disk has no
  equivalent because it has no note/notice domain, but Unli Rice's semantic
  vs category distinction (§1 table) applies: these are "what is true about
  it" and stay separate from any future category palette.
- Port `adaptiveColor(light:dark:)` verbatim (`Theme.swift:186-202` in Unli
  Disk) — it's the mechanism that makes every token above actually respond
  to system appearance, which is the part Unli Rice has never had.

### 4b. Port `LiquidGlass.swift`

Copy `../UnliDisk/Sources/UnliDisk/Views/LiquidGlass.swift` into
`Sources/UnliRice/LiquidGlass.swift` near-verbatim — it has zero UnliDisk-specific
dependencies. Replace every `Theme.panel` background in the 14 view files with
`.liquidGlass()` (cards) or `.liquidGlassCapsule()` (pills/buttons), tinted with
`Theme.accentColor` where the current code tints with `accent`/`accentSoft`.

### 4c. Port the two `View` extensions

`solidControl(cornerRadius:enabled:)` and
`selectedControl(cornerRadius:accent:selected:)` from `Theme.swift:205-225` in
Unli Disk. Grep the 14 files for hand-rolled button/row chrome (`RoundedRectangle`
+ `.fill` + `.overlay(...stroke...)` patterns) and replace with these — this is
where most of the 537 call sites collapse, since a lot of them are the same
fill/stroke pair restated per file today.

### 4d. Sweep

Rename old → new token at every call site (`Theme.background` → `Theme.bgMain`,
`Theme.panel` → delete in favor of `.liquidGlass()`, `Theme.ink` → `Theme.textPrimary`,
`Theme.inkDim` → `Theme.textSecondary`, `Theme.accent` → `Theme.accentColor`,
`Theme.border` → `Theme.borderLight`). Do this file-by-file from the table in
§2, smallest first (`SetupView.swift`, 9 uses) to shake out the token design
before hitting `ContentView.swift`'s 129.

## 5. Verification

- Build in both Xcode's light and dark environment overrides (Debug menu →
  Environment Overrides) — this is the first time that toggle will do anything
  in Unli Rice, since today's colors don't respond to it at all.
- Every text/background pairing spot-checked at 4.5:1 with the same method as
  the existing `onAccent` comment (state the ratio, don't just assert it).
- `swift build` clean, no `Theme.` references left unresolved (the compiler
  will catch renamed tokens; it will *not* catch a `Color.black.opacity(...)`
  literal quietly left in place where `.liquidGlass()` should be — grep for
  those by hand).
- Screenshot every one of the 14 views in both appearances before calling this
  done; UI changes here are explicitly "disposable" per the header, but
  screenshots are how the founder evaluates disposable work fast.
