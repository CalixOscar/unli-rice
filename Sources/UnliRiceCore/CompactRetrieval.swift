import Foundation

public enum CompactRetrieval {
    public struct MatchedFields: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let title = MatchedFields(rawValue: 1 << 0)
        public static let body = MatchedFields(rawValue: 1 << 1)
        public static let tags = MatchedFields(rawValue: 1 << 2)
    }

    /// The one match predicate, shared by `searchNotes` and compact search.
    public static func matchedFields(_ note: Note, lowercasedQuery q: String) -> MatchedFields {
        var fields: MatchedFields = []
        if note.title.lowercased().contains(q) { fields.insert(.title) }
        if note.body.lowercased().contains(q) { fields.insert(.body) }
        if note.tags.contains(where: { $0.lowercased().contains(q) }) { fields.insert(.tags) }
        return fields
    }
}
