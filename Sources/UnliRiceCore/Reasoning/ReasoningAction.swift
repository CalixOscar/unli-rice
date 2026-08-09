import Foundation

/// The three tiers of §4 of docs/BYO_LLM.md, in order of how much a wrong
/// answer costs.
public enum ReasoningTier: String, Sendable, CaseIterable {
    /// `flag_for_review` only. Every structural judgement — merge, dedupe,
    /// "these two conflict" — is *always* this tier and always waits for a
    /// human. Locked-in decision #3.
    case propose
    /// Create and rewrite notes the model authored, scoped by title prefix so
    /// ownership is mechanical rather than a judgement call.
    case own
    /// Add and remove tags on any note. Additive and reversible; `untag_note`
    /// already exists and is the established correction channel.
    case tag
}

/// Which notes a reasoning provider may write into.
///
/// Ownership is a title prefix and nothing else, on purpose: any rule that
/// asked "did a model really write this?" would be a judgement, and a judgement
/// is exactly what must not sit on a capability boundary. The cost of the
/// mechanical rule is that a human who titles a note `Memory: …` by hand has
/// opted that note into the Own tier. That is the trade the design takes, and
/// it is worth it because a person can *see* the rule from the title alone.
public enum ReasoningAuthority {
    /// `Memory: capsule` is the established one (see `MirrorExporter`);
    /// `Summary: ` is the family the design names for derived notes.
    public static let ownedTitlePrefixes = ["Memory: ", "Summary: "]

    public static func owns(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ownedTitlePrefixes.contains { trimmed.lowercased().hasPrefix($0.lowercased()) }
    }

    /// The sentence shown to a user, and written into the prompt, describing
    /// what the ladder permits. Kept in one place so the prompt cannot drift
    /// away from what the dispatcher actually enforces.
    public static var ladderDescription: String {
        """
        - flag_for_review — the only way to raise anything structural. Merges, \
        duplicates, contradictions, "this is stale": all of them are this, and all \
        of them wait for the human.
        - create_note / append_to_note — only for notes titled \
        \(ownedTitlePrefixes.map { "\"\($0)…\"" }.joined(separator: " or ")). Anything else is refused.
        - tag_note / untag_note — any note.
        """
    }
}

/// Everything a model's answer is allowed to become.
///
/// The absences are the point, exactly as with `JanitorProposalKind`. There is
/// no case for archiving, unarchiving, resolving a flag, retitling, or
/// consolidating — so "the model I plugged in archived my note" is not a bug a
/// careless prompt can introduce later, it is a sentence this type cannot
/// express. A request for one of those does not become a `ReasoningAction` at
/// all; it becomes a `RefusedAction`.
public enum ReasoningAction: Sendable, Equatable {
    case flagForReview(noteID: UUID, reason: String)
    case createOwnedNote(title: String, body: String)
    case appendToOwnedNote(noteID: UUID, text: String)
    case tagNote(noteID: UUID, tag: String)
    case untagNote(noteID: UUID, tag: String)

    public var tier: ReasoningTier {
        switch self {
        case .flagForReview: return .propose
        case .createOwnedNote, .appendToOwnedNote: return .own
        case .tagNote, .untagNote: return .tag
        }
    }

    /// The wire name this action is requested by.
    public var name: String {
        switch self {
        case .flagForReview: return "flag_for_review"
        case .createOwnedNote: return "create_note"
        case .appendToOwnedNote: return "append_to_note"
        case .tagNote: return "tag_note"
        case .untagNote: return "untag_note"
        }
    }

    /// Stable identity for "this exact conclusion about this exact note", used
    /// to stamp a flag so a later run doesn't raise it again — the same
    /// bookkeeping `JanitorProposal.fingerprint` does for the rule-based janitor,
    /// and it shares the `[janitor:…]` marker so one reader strips both.
    var fingerprint: String? {
        switch self {
        case .flagForReview(let noteID, let reason):
            // Keyed on the note plus the shape of the concern, not the exact
            // wording — two runs of the same model rarely phrase it identically.
            let words = TokenOverlapSimilarity.tokens(reason).sorted().prefix(8).joined(separator: "-")
            return "llm/\(noteID.uuidString)/\(words)"
        case .tagNote(let noteID, let tag):
            return "llm-tag/\(noteID.uuidString)/\(tag.lowercased())"
        case .createOwnedNote, .appendToOwnedNote, .untagNote:
            return nil
        }
    }
}

/// Something the model asked for that this app will not do.
///
/// Refusals are kept and reported rather than discarded. A model that keeps
/// reaching for `archive_note` is telling its user something — either that the
/// prompt is wrong or that the model is — and silently dropping the request
/// would hide both.
public struct RefusedAction: Sendable, Equatable, Error {
    public enum Reason: Sendable, Equatable {
        /// Not one of the five actions on the ladder. Archiving, resolving a
        /// review, consolidating, retitling, trashing — all land here.
        case notOnTheLadder
        /// An Own-tier write aimed at a note the model does not own.
        case notOwned
        /// The target note doesn't exist in this vault.
        case unknownNote
        /// Required arguments missing, empty, or the wrong type.
        case malformed(String)
    }

    /// The action name as the model wrote it. Never a note title or body — this
    /// value reaches the outbound-call log, which is metadata-only.
    public let requested: String
    public let reason: Reason

    public init(requested: String, reason: Reason) {
        self.requested = requested
        self.reason = reason
    }

    public var explanation: String {
        switch reason {
        case .notOnTheLadder:
            return "\"\(requested)\" isn't something a model may do here. Structural changes are proposed with flag_for_review and resolved by you."
        case .notOwned:
            return "\"\(requested)\" was aimed at a note the model doesn't own. It may only write notes titled \(ReasoningAuthority.ownedTitlePrefixes.map { "\"\($0)…\"" }.joined(separator: " or "))."
        case .unknownNote:
            return "\"\(requested)\" named a note that isn't in this vault."
        case .malformed(let detail):
            return "\"\(requested)\" was missing something it needs: \(detail)."
        }
    }
}

/// The result of reading a model's answer: what survived, and what didn't.
public struct ParsedActions: Sendable, Equatable {
    public let allowed: [ReasoningAction]
    public let refused: [RefusedAction]
    /// Set when the reply as a whole could not be read. Nothing is applied in
    /// that case — a half-understood answer is not a mandate.
    public let unreadable: String?

    public init(allowed: [ReasoningAction] = [], refused: [RefusedAction] = [], unreadable: String? = nil) {
        self.allowed = allowed
        self.refused = refused
        self.unreadable = unreadable
    }
}

/// Turns a model's reply into the vocabulary above, and refuses everything else.
///
/// The parser is strict on purpose. It reads one JSON object with an `actions`
/// array and nothing else — no fence-stripping, no salvaging a JSON blob out of
/// prose, no second-guessing. A reply it can't read is reported as unreadable
/// and applied to nothing, which is honest; guessing at intent would be the app
/// inventing the judgement it exists to avoid making.
public enum ReasoningActionParser {
    public static func parse(_ text: String) -> ParsedActions {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ParsedActions() }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ParsedActions(unreadable: "the reply was not a JSON object")
        }
        guard let rows = object["actions"] as? [[String: Any]] else {
            return ParsedActions(unreadable: "the reply had no `actions` array")
        }

        var allowed: [ReasoningAction] = []
        var refused: [RefusedAction] = []
        for row in rows {
            switch action(from: row) {
            case .success(let action): allowed.append(action)
            case .failure(let refusal): refused.append(refusal)
            }
        }
        return ParsedActions(allowed: allowed, refused: refused)
    }

    private static func action(from row: [String: Any]) -> Result<ReasoningAction, RefusedAction> {
        let name = (row["action"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else {
            return .failure(RefusedAction(requested: "(unnamed)", reason: .malformed("no `action` name")))
        }

        func string(_ key: String) -> String? {
            guard let value = (row[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return nil }
            return value
        }
        func noteID() -> UUID? { string("note_id").flatMap(UUID.init(uuidString:)) }
        func missing(_ what: String) -> Result<ReasoningAction, RefusedAction> {
            .failure(RefusedAction(requested: name, reason: .malformed(what)))
        }

        switch name {
        case "flag_for_review":
            guard let id = noteID() else { return missing("a valid `note_id`") }
            guard let reason = string("reason") else { return missing("a `reason`") }
            return .success(.flagForReview(noteID: id, reason: reason))

        case "create_note":
            guard let title = string("title") else { return missing("a `title`") }
            guard let body = string("body") else { return missing("a `body`") }
            // Ownership is checked here as well as in the dispatcher, because
            // the answer to "may this happen" must not depend on which of the
            // two a future caller reaches for first.
            guard ReasoningAuthority.owns(title: title) else {
                return .failure(RefusedAction(requested: name, reason: .notOwned))
            }
            return .success(.createOwnedNote(title: title, body: body))

        case "append_to_note":
            guard let id = noteID() else { return missing("a valid `note_id`") }
            guard let text = string("text") else { return missing("a `text`") }
            return .success(.appendToOwnedNote(noteID: id, text: text))

        case "tag_note", "untag_note":
            guard let id = noteID() else { return missing("a valid `note_id`") }
            guard let tag = string("tag") else { return missing("a `tag`") }
            return .success(name == "tag_note" ? .tagNote(noteID: id, tag: tag) : .untagNote(noteID: id, tag: tag))

        default:
            // Everything else in the world, including all 14 MCP tools this
            // deliberately does not expose.
            return .failure(RefusedAction(requested: name, reason: .notOnTheLadder))
        }
    }
}
