import SwiftUI
import UnliRiceCore

/// Type a note instead of speaking it.
///
/// A note could only ever *start* as speech. The keyboard was already in the app —
/// appending to a note, noting against a to-do — so you could type into a thought you
/// had already had, but not type a new one. In a meeting, a library, or a room too loud
/// to transcribe, that means the note is simply lost.
///
/// A sheet rather than an inline composer: the capture screen has three layouts (iPad
/// regular width, and both `layoutPlacement` orders on the phone) and an inline editor
/// has to be correct in all three with the keyboard up. This is one surface that behaves
/// the same everywhere, and it matches how the app already presents settings.
///
/// It is a capture box, not a writing app — open, type, save, gone.
struct TypedNoteSheet: View {
    @ObservedObject var store: CaptureStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgMain.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    editor

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.crit)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Saved to “\(store.currentProjectTab)”, the same as a recording — "
                         + "it just has no audio.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Type a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        .onAppear { editorFocused = true }
    }

    /// Mirrors the keyboard-append editor in `NoteDetailView` — placeholder behind the
    /// editor rather than beside it, same field styling, so the two ways of typing into
    /// this app do not look like two different apps.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text("What are you thinking?")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .frame(minHeight: 160)
                .padding(8)
        }
        .background(Theme.bgField)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderLight, lineWidth: 1))
        .cardStyle(cornerRadius: 12)
    }

    /// Dismiss only on a save that actually reached the log.
    ///
    /// `saveTypedNote` throws unless every event in the batch lands in `events.jsonl`,
    /// which is what `sync()` publishes from — so a success here means the note will
    /// reach the Mac, not merely that something was written somewhere. On a throw the
    /// sheet stays open with the text intact: never dismiss a composer whose content
    /// was not saved.
    private func save() {
        do {
            try store.saveTypedNote(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
