# PLAN — Sidebar pane switches re-run the background blur every click

**Stage:** Step 1 was implemented directly by Claude at explicit founder direction
("you fix that, do it fast") — a deliberate departure from plan-only, recorded here
rather than silently, and not a precedent. No `docs/intent/` doc and no Codex
pre-mortem, same deliberate skip as `docs/PLAN-cleanup-menu-toast.md`. Step 2 remains
unstarted and swarm-shaped.

**Status:** Step 1 landed in `Sources/UnliRice/ContentView.swift` (`BackgroundBlobs`,
`.drawingGroup()`). `swift build` clean. **Not yet observed in the running app** — see
Verification. Step 2 not attempted.
**Verified against:** working tree at `06b4e5f`. The mechanism below is confirmed by
reading `ContentView.swift` and `AppStore.swift` directly. The perceived lag itself is
**still unverified against the running app** — screen access was declined earlier and
hasn't been re-requested — so treat "does it actually feel faster" as the swarm's or
the founder's job to confirm, not a foregone conclusion from the code alone.

## The gap

Founder-reported: the sidebar (To do / Repos / etc.) sometimes needs several clicks
to switch panes.

`ContentView.body` (`Sources/UnliRice/ContentView.swift:4-56`) reads `@EnvironmentObject
var store: AppStore` directly in the view that owns the whole window, so SwiftUI
re-evaluates the entire body on *every* `@Published` write to `store` — not just the
one pane that changed.

A single sidebar click writes far more than one property:

- `closeAllPanes()` (`AppStore.swift:1094-1116`) sets **17** `@Published` `Bool`s to
  `false`, unconditionally, even though at most one was `true`.
- The destination's own `show*()` (e.g. `showHome()`, `AppStore.swift:1179-1183`) adds
  its own pane `Bool = true` plus a `statusMessage` write — up to 19 `@Published`
  writes per click.

Each of those writes re-triggers `ContentView.body`, which re-runs three
`GeometryReader { … Circle().blur(radius: 80-95) … }` blocks
(`ContentView.swift:13-35`) — expensive Core Animation blur passes sized to the whole
window, sitting behind `.liquidGlass` on the sidebar, redone up to 19 times for one
click.

## The fix

Two independent moves, in order of effort:

**1. Isolate the background blob view so it stops observing `store`.**

Pull the `GeometryReader { … }` block (`ContentView.swift:13-35`) into its own view
that takes no `store` dependency:

```swift
struct BackgroundBlobs: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Theme.violet.opacity(0.18))
                    .frame(width: 450, height: 450)
                    .blur(radius: 90)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Circle()
                    .fill(Theme.accentColor.opacity(0.14))
                    .frame(width: 350, height: 350)
                    .blur(radius: 80)
                    .position(x: geo.size.width * 0.15, y: geo.size.height * 0.8)

                Circle()
                    .fill(Theme.brass.opacity(0.12))
                    .frame(width: 380, height: 380)
                    .blur(radius: 95)
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.2)
            }
            .ignoresSafeArea()
        }
        .drawingGroup()
    }
}
```

`.drawingGroup()` flattens the three blurred circles to one Metal-backed bitmap, so
even if this view *does* get asked to redraw, it's one composited layer instead of
three live blur passes. Since it has no `store` dependency, SwiftUI has no reason to
re-run it on a pane switch at all — a `Bool` flip in `AppStore` isn't a input this view
reads.

Swap the inline block in `ContentView.body` for `BackgroundBlobs()`.

**2. Collapse the pane `Bool`s into one `@Published` value — deeper cause, not part of
this fix.**

17 independent `Bool`s means `closeAllPanes()` is 17 writes (17 SwiftUI invalidations
under today's setup) to express what is really "set the current pane to X." The
correct fix is a single `@Published enum Pane { case home, todo, repos, … }` with one
`currentPane` property, and every `show*()`/`closeAllPanes()` collapses to one
assignment. That's a call-site rewrite across every `show*()` method, every
`if store.showingX` in `ContentView`, and the sidebar's own selection state — real
work, correctly flagged in the founder's note as swarm-shaped rather than a quick
fix. **Not attempted here.** Step 1 alone removes the expensive part (the blur
re-render) without touching this wider surface; step 2 is a separate, larger plan if
the lag persists after step 1.

## Verification

Screen access to the running app is needed to confirm the lag is actually gone after
step 1 — this plan diagnoses the mechanism from code, it doesn't observe the fix
working. Whoever picks this up should build, click through the sidebar panes, and
confirm the switch feels immediate before calling it done.

## Unrelated, carried over

`_AI Context/07_Prelaunch_Post_Mortem.md` still has not been run before any future
distribution action. Unrelated to the sidebar issue, predates this plan, not touched
here — carrying the note forward so it doesn't get lost.
