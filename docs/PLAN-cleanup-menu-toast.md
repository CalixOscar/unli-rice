# PLAN — A toast when Clean up copies a prompt

**Stage:** Claude's plan, dispatched directly to the swarm at founder direction. No
`docs/intent/` doc and no Codex pre-mortem — a deliberate skip for a change this small
and this contained, not a precedent for skipping either step on anything larger.
Recorded here rather than silently, same as the last deliberate pipeline skip
(`docs/PLAN-ai-todo-actions.md`).
**Verified against:** working tree at `1b4779a`.

## The gap

`CleanupMenu` (`Sources/UnliRice/ContentView.swift:442`) is the shared "Clean up…"
button — used on Needs You (`NeedsYouView.swift:42`), the Archived pane
(`ContentView.swift:415`), and the Notes toolbar (`ContentView.swift:533`). Every item
in it calls `store.copyPrompt(_:)` (`AppStore+Cleanup.swift:19`), which copies to the
clipboard and sets `store.statusMessage`.

`statusMessage` is only ever rendered in one place — a fixed italic caption at the
bottom of the Notes pane (`ContentView.swift:291`). **Needs You and Archived never
show it.** Click "Clear out ingested sessions" on Needs You today and the prompt lands
on the clipboard with zero visible confirmation — the screenshot that prompted this is
someone looking at that menu with no way to tell whether the click did anything.

## The fix, and why it's not a `statusMessage` fix

Route the confirmation through the app already has a working pattern for, not through
`statusMessage`, which is a persistent single-line status wired to one specific
location and used for a dozen unrelated things (navigation captions, ingest results,
trust notices). Reusing it here would mean either duplicating the render call on every
`CleanupMenu` host, or trying to make one caption line serve both "which screen am I
on" and "did my click just work," which is a fight the file already avoids
everywhere else.

`Sources/UnliRice/ProfileEditSheet.swift:107` already has the right shape: local
`@State private var feedbackMessage: String?`, `showFeedback(_:)` sets it inside
`withAnimation`, `DispatchQueue.main.asyncAfter(deadline: .now() + 3.0)` clears it the
same way, and it renders as `Text(feedback)` in `Theme.emerald` with `.transition
(.opacity)`. This plan is that pattern, moved onto `CleanupMenu`, which is the one
place all three menus already funnel through — fixing it there fixes all three call
sites, not just Needs You, for the same one change.

## File-by-file

### `Sources/UnliRice/ContentView.swift` — `CleanupMenu`

```swift
struct CleanupMenu: View {
    @EnvironmentObject var store: AppStore
    let prompts: [CleanupPrompt]
    var label: String = "Clean up…"

    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Menu {
                ForEach(prompts) { prompt in
                    Button {
                        store.copyPrompt(prompt)
                        showFeedback("Copied “\(prompt.title)” — paste it into your assistant.")
                    } label: {
                        Text(prompt.title)
                        Text(prompt.blurb)
                    }
                }
                Divider()
                Text("Each copies a prompt to paste into your assistant.")
                    .foregroundColor(Theme.textPrimary)
            } label: {
                Text(label)
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if let feedback {
                Text(feedback)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.emerald)
                    .transition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func showFeedback(_ text: String) {
        withAnimation { feedback = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { feedback = nil }
        }
    }
}
```

Two things to get right, not obvious from the diff:

- **The confirmation text is composed here, not read back from `store.statusMessage`.**
  `copyPrompt` sets `statusMessage` to `"Copied “\(prompt.title)”..."` — same wording,
  independently composed, so this view has no dependency on what `AppStore` happens to
  have written to that string. Match the wording exactly so the two don't drift into
  visibly different phrasing for the same action.
- **`copyPrompt` itself is untouched.** It still sets `statusMessage`, which still
  matters for the Notes toolbar host — that pane's fixed caption line reads it, and
  removing the write would silently break the one place that already worked.

### Layout check, not assumed

`CleanupMenu` sits inside `HStack`s at all three call sites (`ContentView.swift:415`,
`:533`, `NeedsYouView.swift:42`), each row holding two or three controls at a fixed
height. Wrapping the `Menu` in a `VStack` to stack the toast underneath changes this
view's height when the toast is showing, which can jostle whatever sits next to it in
those rows. Check all three call sites after the change — the toast may need to float
(an `.overlay(alignment: .bottom)` instead of a `VStack`) rather than push layout, if
the `HStack` rows don't tolerate the height change.

## Tests

None planned — this is `@State` + a timer in a SwiftUI view, the same shape as
`ProfileEditSheet`'s existing untested `showFeedback`. Verify by hand: click each of
the four items in Needs You's Clean up menu, confirm the toast appears and clears
after ~3 seconds, and confirm the Archived pane and Notes toolbar still work
(clipboard content correct, no layout jump).

## Explicitly not in this plan

- Touching `store.statusMessage` or any of its dozen other call sites.
- A toast for `AIReviewMenu` or `AITodoMenu` — same "copies a prompt" shape, but not
  what was asked, and each has its own wording contract worth its own look.
- A generalized toast/notification system. Three call sites sharing one component is
  not yet a case for infrastructure.
