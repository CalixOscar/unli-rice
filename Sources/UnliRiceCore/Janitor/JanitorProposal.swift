import Foundation

/// How much damage a proposal could do if the janitor were wrong about it.
///
/// This is the whole basis of what the janitor is allowed to do on its own.
/// Cosmetic conclusions can auto-apply because a human can undo them with one
/// existing, non-destructive tool. Structural conclusions can only ever be
/// queued — see `JanitorRunner` and decision #3 in PROJECT_NOTES.md.
public enum JanitorRisk: Sendable, Equatable {
    /// Reversible with an existing tool, affects one note, changes no meaning.
    case cosmetic
    /// Implies a merge, a split, a rewrite, or a judgement about what a note
    /// *means*. Always a human's call.
    case structural
}

/// Everything the janitor is capable of concluding.
///
/// The absences here are the point. There is no case for archiving, untagging,
/// resolving a flag, retitling, or rewriting a body — so "the janitor archived
/// my note" is not a bug that can be introduced later by a careless rule, it is
/// a sentence that cannot be expressed in this type. Adding a case that implies
/// destruction or an unattended structural edit would violate decisions #2 and
/// #3 in PROJECT_NOTES.md.
public enum JanitorProposalKind: Sendable, Equatable {
    /// A tag already established elsewhere in the corpus that this note plainly
    /// earns from its own text.
    case addTag(String)

    /// Two notes whose permanent titles are close enough that one is probably a
    /// duplicate of the other.
    case possibleDuplicate(other: UUID, otherTitle: String, similarity: Double)

    /// A `[[link]]` that resolves to nothing but is one or two characters away
    /// from a real note's title — i.e. a typo, not a forward reference.
    case likelyMistypedLink(target: String, suggestion: String, suggestionID: UUID)

    /// No tags, nothing links to it, it links to nothing. Reachable only by
    /// scrolling, which at corpus scale means unreachable.
    case orphaned

    public var risk: JanitorRisk {
        switch self {
        case .addTag: return .cosmetic
        case .possibleDuplicate, .likelyMistypedLink, .orphaned: return .structural
        }
    }
}

/// One conclusion about one note. Inert by construction: producing a proposal
/// touches nothing. `JanitorRunner` is the only thing that acts on these, and
/// what it may do is decided entirely by `risk`.
public struct JanitorProposal: Sendable, Equatable, Identifiable {
    public let noteID: UUID
    public let noteTitle: String
    public let kind: JanitorProposalKind

    public var id: String { fingerprint }
    public var risk: JanitorRisk { kind.risk }

    public init(noteID: UUID, noteTitle: String, kind: JanitorProposalKind) {
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.kind = kind
    }

    /// Stable identity for "this exact conclusion about this exact note".
    ///
    /// The runner stamps this into the flag reason so a later scan can tell that
    /// it already raised this and stay quiet — including when the human looked
    /// at it and said no. A janitor that re-proposes a rejected merge every scan
    /// trains its user to ignore the review queue, which is worse than a janitor
    /// that never ran.
    public var fingerprint: String {
        switch kind {
        case .addTag(let tag):
            return "tag/\(noteID.uuidString)/\(tag.lowercased())"
        case .possibleDuplicate(let other, _, _):
            // Symmetric: the same pair fingerprints identically whichever note
            // the proposal ends up attached to.
            let pair = [noteID.uuidString, other.uuidString].sorted()
            return "dup/\(pair[0])/\(pair[1])"
        case .likelyMistypedLink(let target, _, _):
            return "link/\(noteID.uuidString)/\(target.lowercased())"
        case .orphaned:
            return "orphan/\(noteID.uuidString)"
        }
    }

    /// How strongly the janitor believes this, used to spend a limited per-run
    /// budget on the best proposals rather than whatever the rules happened to
    /// emit first. Higher is raised sooner.
    public var confidence: Double {
        switch kind {
        case .addTag: return 1.0
        // A near-miss title is a cheap, obviously-checkable fix, so it outranks
        // a merge proposal unless that merge is near-certain.
        case .likelyMistypedLink: return 0.9
        case .possibleDuplicate(_, _, let similarity): return 0.5 + similarity / 2
        // True but rarely urgent — the thing most worth dropping when the
        // budget is tight.
        case .orphaned: return 0.2
        }
    }

    /// The sentence a human reads in the review queue. Written to explain the
    /// evidence and hand back the decision, never to instruct.
    public var rationale: String {
        switch kind {
        case .addTag(let tag):
            return "Tagged \"\(tag)\" — that term is already an established tag elsewhere and appears in this note's own text."

        case .possibleDuplicate(_, let otherTitle, let similarity):
            let pct = Int((similarity * 100).rounded())
            return """
            Possible duplicate of \"\(otherTitle)\" (\(pct)% title overlap). \
            Titles are permanent here, so if these are the same idea the fix is \
            usually to append this note's content onto the older one rather than \
            keep two near-identical titles. Not doing that — your call.
            """

        case .likelyMistypedLink(let target, let suggestion, _):
            return """
            This note has a link to \"\(target)\", but no note has exactly that \
            name — it's very close to \"\(suggestion)\", though. If that's a typo, \
            open the note and fix the link. If you meant to link to something \
            that doesn't exist yet on purpose, there's nothing to do.
            """

        case .orphaned:
            return """
            This note has no tags and nothing links to it, so the only way \
            anyone will find it again is by scrolling past it. Adding a tag, or \
            a link from a related note, would help it turn up later.
            """
        }
    }
}

/// Formats and recognises the marker the runner appends to a flag reason.
enum JanitorMarker {
    static func stamp(_ fingerprint: String) -> String { "[janitor:\(fingerprint)]" }

    static func isStamped(_ reason: String, with fingerprint: String) -> Bool {
        reason.contains(stamp(fingerprint))
    }
}
