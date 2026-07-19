import Foundation

/// What the app noticed about a note *before* it's saved — the draft-time
/// counterpart to `Janitor.scan`. Same underlying rules, just triggered
/// earlier, at the moment a duplicate or a missing tag is easiest to avoid
/// instead of after it's already sitting in the review queue.
///
/// Nothing here writes anything. Applying a suggestion — tagging, linking, or
/// appending to an existing note instead of creating a new one — is still a
/// deliberate action the GUI takes only when a person clicks it, same as
/// every other structural decision in this app.
public struct DraftSuggestions: Sendable, Equatable {
    public struct RelatedNote: Sendable, Identifiable, Equatable {
        public let id: UUID
        public let title: String
    }

    /// An existing note this draft looks like a repeat of — the same signal
    /// `Janitor`'s duplicate rule uses, just caught before a duplicate is ever
    /// written rather than flagged afterward.
    public var possibleDuplicate: RelatedNote?

    /// Tags already established elsewhere in the corpus that this draft's own
    /// text would also earn. Identical rule to `Janitor.scan`'s cosmetic pass
    /// (`Janitor.establishedTags`) — never invents a tag, only reuses one the
    /// corpus already agreed on.
    public var suggestedTags: [String] = []

    /// Existing notes similar enough to be worth a `[[link]]`, but not so
    /// similar they look like the same note — a deliberately lower bar than
    /// `possibleDuplicate` (`SimilarityCalibration.relatednessThreshold`),
    /// because "these are related" and "these are the same thing" are
    /// different questions with different right answers.
    public var relatedNotes: [RelatedNote] = []

    public var isEmpty: Bool {
        possibleDuplicate == nil && suggestedTags.isEmpty && relatedNotes.isEmpty
    }

    public init(
        possibleDuplicate: RelatedNote? = nil,
        suggestedTags: [String] = [],
        relatedNotes: [RelatedNote] = []
    ) {
        self.possibleDuplicate = possibleDuplicate
        self.suggestedTags = suggestedTags
        self.relatedNotes = relatedNotes
    }
}

public enum DraftAdvisor {
    /// At most this many related-note suggestions — a short, skimmable list,
    /// not a search results page under a text field.
    static let maxRelatedNotes = 3

    /// Computes what a person deciding "is this new, or does it belong
    /// somewhere else?" would want to know, from the draft title/body alone.
    /// Pure and synchronous — safe to call on every keystroke; with
    /// `TokenOverlapSimilarity` (the default, and what the GUI uses for this
    /// specifically so it never waits on a model load) it's plain string
    /// comparison over a few dozen titles, not a model call.
    public static func suggestions(
        forTitle title: String,
        body: String,
        existing notes: [Note],
        config: JanitorConfig,
        similarity: SimilarityProvider = TokenOverlapSimilarity()
    ) -> DraftSuggestions {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return DraftSuggestions() }

        // Archived notes are out of scope for the same reason they're out of
        // scope for the janitor's own scan: a person archived it on purpose,
        // and neither a duplicate nor a link suggestion should drag it back in.
        let live = notes.filter { !$0.archived }
        let scored = live.map { (note: $0, score: similarity.similarity(trimmedTitle, $0.title)) }

        var duplicate: DraftSuggestions.RelatedNote?
        let duplicateThreshold = config.duplicateThreshold(similarity.calibration)
        if let best = scored.max(by: { $0.score < $1.score }), best.score >= duplicateThreshold {
            duplicate = .init(id: best.note.id, title: best.note.title)
        }

        let related = scored
            .filter { $0.note.id != duplicate?.id && $0.score >= similarity.calibration.relatednessThreshold }
            .sorted { $0.score > $1.score }
            .prefix(maxRelatedNotes)
            .map { DraftSuggestions.RelatedNote(id: $0.note.id, title: $0.note.title) }

        let established = Janitor.establishedTags(live, config: config)
        let words = TokenOverlapSimilarity.tokens("\(trimmedTitle) \(body)")
        let tags = established.sorted().filter { words.contains($0.lowercased()) }

        return DraftSuggestions(possibleDuplicate: duplicate, suggestedTags: tags, relatedNotes: Array(related))
    }
}
