import Foundation
import UnliRiceCore

/// Draft-time suggestions for `NewNoteRow` — the janitor's own rules, run
/// before a note exists instead of after. See `DraftAdvisor`.
extension AppStore {
    /// Pure and synchronous on purpose: this is meant to be called on every
    /// keystroke without the caller thinking about it, so it always uses
    /// `TokenOverlapSimilarity` rather than the (possibly not yet loaded, and
    /// async to load) MLX embedding model — a note-taking flow shouldn't ever
    /// wait on a model just to type a title. Same reasoning `Janitor` itself
    /// uses a crude default: missing a suggestion costs nothing, a model load
    /// stalling every keystroke would cost a lot.
    func draftSuggestions(title: String, body: String) -> DraftSuggestions {
        DraftAdvisor.suggestions(
            forTitle: title, body: body, existing: notes, config: JanitorConfig(autonomy: autonomy)
        )
    }

    /// "Add this to that note instead" — skips creating a new note entirely.
    /// Appends the draft's own text (never the existing note's) so nothing
    /// already there is touched beyond having this appended to it.
    @discardableResult
    func appendDraft(_ text: String, toExisting noteID: UUID) -> Note? {
        guard let target = note(id: noteID) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return target }
        append(to: target, text: trimmed)
        return note(id: noteID)
    }
}
