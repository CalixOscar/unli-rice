import Foundation

/// A group of review-queue items that are really one decision.
///
/// The duplicate rule compares notes *pairwise*, so a set of five near-identical
/// notes arrives as up to ten separate flags. That's an artifact of how the rule
/// computes, not how a person thinks: nobody wants to answer "is A a duplicate
/// of B?" ten times about one pile of session logs. Clustering turns the pile
/// back into one question.
///
/// This changes presentation and nothing else. Resolving a cluster still writes
/// one `resolved` event per flag through `NoteService.resolveReview`, still
/// requires a human to press it, and still merges nothing — decision #3 is
/// untouched. What it removes is repetition, not oversight.
public struct ReviewCluster: Identifiable, Sendable {
    /// Stable across reloads so SwiftUI doesn't re-animate the list every scan.
    public let id: String

    /// Every note the cluster is about. For a duplicate group this is the whole
    /// set of mutually-similar notes; for anything else it's a single note.
    public let notes: [Note]

    /// The flags that get resolved together when the user answers.
    public let items: [ReviewItem]

    public var isDuplicateGroup: Bool { notes.count > 1 }

    /// The evidence, stated once for the group instead of once per pair, in
    /// plain language — this is what a person with no technical background
    /// reads to decide whether to act, so it explains *why* the app is asking
    /// and *what happens* if they do something about it, not just the raw
    /// similarity finding.
    public var summary: String {
        guard isDuplicateGroup else { return items.first?.flag.reason.withoutJanitorMarker ?? "" }
        return """
        These \(notes.count) notes have almost the same name — you (or an \
        assistant) may have saved the same thing more than once without \
        meaning to. Open each one below to compare them, then pick "Keep this \
        one" under whichever version you want going forward — its content \
        stays, the others get folded into it and tucked away in Archived. \
        Nothing is deleted, and anything archived can be brought back anytime.
        """
    }
}

public struct ReviewItem: Sendable {
    public let note: Note
    public let flag: ReviewFlag

    public init(note: Note, flag: ReviewFlag) {
        self.note = note
        self.flag = flag
    }
}

extension String {
    /// The reason without the `[janitor:...]` bookkeeping stamp.
    ///
    /// The stamp is how a later scan knows not to re-raise something the human
    /// already answered — necessary, and meaningless to the person reading the
    /// sentence it's glued onto.
    public var withoutJanitorMarker: String {
        guard let start = range(of: " [janitor:") ?? range(of: "[janitor:") else { return self }
        return String(self[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ReviewQueue {
    /// Groups pending flags into the decisions they actually represent.
    ///
    /// Duplicate flags that share a note join the same cluster — transitively,
    /// so A~B and B~C produce one group of three rather than two groups of two.
    /// Everything else (orphans, mistyped links, anything a human or another
    /// agent flagged by hand) stays on its own: those are genuinely separate
    /// questions and merging them would hide information, not repetition.
    ///
    /// `resolveNote` is needed because a duplicate flag is written to only one
    /// side of the pair — `Janitor.duplicateProposals` always attaches it to the
    /// *newer* note (see the comment there: the proposal points back at the
    /// older one, not the reverse). The older note in a chain can end up with no
    /// flag of its own at all, so it never appears in `pending`, and the only
    /// way to render it in the group is to look it up by the id the fingerprint
    /// names — the app's full note index, not just the flagged subset.
    public static func cluster(
        _ pending: [ReviewItem],
        resolveNote: (UUID) -> Note?
    ) -> [ReviewCluster] {
        var groups = DisjointSet()
        var duplicateItems: [ReviewItem] = []
        var standalone: [ReviewItem] = []
        var pairsSeen: [(UUID, UUID)] = []

        for item in pending {
            guard let pair = duplicatePair(in: item.flag.reason) else {
                standalone.append(item)
                continue
            }
            groups.union(pair.0, pair.1)
            pairsSeen.append(pair)
            duplicateItems.append(item)
        }

        // Full membership of each cluster comes from every id that appeared on
        // either side of any pair assigned to it — not from which note happens
        // to carry a flag. That's the fix: the oldest note in a chain carries no
        // flag of its own but is still a member of the group.
        var membersByRoot: [UUID: Set<UUID>] = [:]
        for (a, b) in pairsSeen {
            let root = groups.find(a)
            membersByRoot[root, default: []].formUnion([a, b])
        }

        var itemsByRoot: [UUID: [ReviewItem]] = [:]
        for item in duplicateItems {
            itemsByRoot[groups.find(item.note.id), default: []].append(item)
        }

        var result: [ReviewCluster] = itemsByRoot.map { root, items in
            let notes = (membersByRoot[root] ?? [])
                .compactMap(resolveNote)
                .sorted { $0.createdAt < $1.createdAt }
            return ReviewCluster(
                id: "dup-group/\(root.uuidString)",
                notes: notes,
                items: items.sorted { $0.flag.id.uuidString < $1.flag.id.uuidString }
            )
        }

        result += standalone.map { item in
            ReviewCluster(id: item.flag.id.uuidString, notes: [item.note], items: [item])
        }

        // Biggest piles first — that's where the tedium was.
        return result.sorted {
            ($0.items.count, $0.id) > ($1.items.count, $1.id)
        }
    }

    /// Pulls the note pair back out of a janitor duplicate stamp
    /// (`[janitor:dup/<uuid>/<uuid>]`).
    ///
    /// Reading it off the reason string rather than storing it structurally is a
    /// deliberate trade: `ReviewFlag` is part of the append-only event log, and
    /// adding a field to it would mean every previously written flag lacks it.
    /// The stamp is already durable, already written, and already the mechanism
    /// the runner relies on for idempotence.
    static func duplicatePair(in reason: String) -> (UUID, UUID)? {
        guard let open = reason.range(of: "[janitor:dup/"),
              let close = reason.range(of: "]", range: open.upperBound ..< reason.endIndex)
        else { return nil }

        let parts = reason[open.upperBound ..< close.lowerBound].split(separator: "/")
        guard parts.count == 2,
              let first = UUID(uuidString: String(parts[0])),
              let second = UUID(uuidString: String(parts[1]))
        else { return nil }
        return (first, second)
    }
}

/// Union-find over note ids. Small enough to keep here rather than take on a
/// dependency for it.
private struct DisjointSet {
    private var parent: [UUID: UUID] = [:]

    mutating func find(_ id: UUID) -> UUID {
        guard let above = parent[id], above != id else {
            parent[id] = id
            return id
        }
        let root = find(above)
        parent[id] = root
        return root
    }

    mutating func union(_ a: UUID, _ b: UUID) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        parent[rootB] = rootA
    }
}
