import SwiftUI
import UnliRiceCore

/// What "Send to AI" actually shows before anything leaves the device.
///
/// Composition happens in `ShareToAI` — plain concatenation, no summarising —
/// and this view exists so the person can see exactly that text, edit it if
/// they want, and only then hand it to the OS share sheet. Nothing is copied
/// or shared just by opening this screen; the Share button is the only exit,
/// and it only fires on an explicit tap, same as every other "show it before
/// it happens" surface in this app.
struct AISharePreviewView: View {
    let notes: [Note]
    /// Called once the sheet is dismissed, however it was dismissed — the
    /// caller clears the note selection either way, since "I looked at this
    /// and closed it" and "I sent it" both mean the selection has been acted on.
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var showActivitySheet = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.bgMain.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("This is exactly what will be shared — titles and bodies of the \(notes.count) note\(notes.count == 1 ? "" : "s") you picked, nothing else. Edit it here if you want before sending it on.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .liquidGlass(cornerRadius: 14)
                        // Bounded, not `.infinity` — an unbounded TextEditor's
                        // tap-hittable area extends well past its visible box
                        // (confirmed on-device: it was swallowing taps meant for
                        // the Share button below it, popping up the text-selection
                        // menu instead). `Spacer()` below soaks up the rest.
                        .frame(minHeight: 160, maxHeight: 420)

                    HStack {
                        Text("~\(ShareToAI.estimatedTokens(text)) tokens (estimate)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .opacity(isEmpty ? 0.5 : 1)
                        .background(Capsule().fill(Theme.accentColor))
                        .contentShape(Capsule())
                        .onTapGesture { if !isEmpty { showActivitySheet = true } }
                    }

                    // Keeps the row above well clear of the sheet's own
                    // swipe-to-dismiss gesture zone near the bottom edge —
                    // confirmed on-device that controls pinned there could be
                    // tapped but never actually triggered.
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Send to AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showActivitySheet) {
            ActivityView(activityItems: [text])
        }
        .onAppear { text = ShareToAI.compose(notes) }
        .onDisappear { onDismiss() }
    }
}
