import Foundation

/// How eagerly the janitor looks and proposes. Maps 1:1 onto the autonomy
/// slider in the GUI (`AppStore.autonomyLevel`), whose raw values are persisted
/// in UserDefaults — so these raw values are load-bearing, don't renumber them.
///
/// Note what the levels *don't* vary: no level grants auto-apply of a structural
/// change. The slider changes how much the janitor notices, never what it is
/// allowed to do about it.
public enum JanitorAutonomy: Int, Sendable, CaseIterable {
    case eco = 0
    case balanced = 1
    case aggressive = 2
}

public struct JanitorConfig: Sendable {
    public let autonomy: JanitorAutonomy

    public init(autonomy: JanitorAutonomy) {
        self.autonomy = autonomy
    }

    /// Eco is cosmetic-only — it never queues merge/split proposals, matching
    /// what the slider's own description promises the user.
    public var runsStructuralRules: Bool { autonomy != .eco }

    /// Aggressive looks harder, which means more false positives in the queue.
    /// That's the trade the user opted into by moving the slider.
    ///
    /// The actual numbers come from whichever `SimilarityProvider` is in play —
    /// see `SimilarityCalibration` for why they can't be constants here.
    public func duplicateThreshold(_ calibration: SimilarityCalibration) -> Double {
        autonomy == .aggressive
            ? calibration.aggressiveDuplicateThreshold
            : calibration.duplicateThreshold
    }

    public var detectsOrphans: Bool { autonomy == .aggressive }

    /// A tag has to be established — used by at least this many other notes —
    /// before the janitor will reuse it. Stops it from inventing vocabulary.
    public var minimumTagCorpusUse: Int { autonomy == .aggressive ? 1 : 2 }

    /// The other end of the same idea: a tag already on this fraction of the
    /// corpus is not a filter, it's wallpaper. Found the hard way — dry-running
    /// the rules over the real log had the janitor wanting to tag 64 of 48
    /// notes "memory", because in a corpus *about* memory that word is
    /// everywhere. A tag matching almost everything distinguishes nothing.
    public var maximumTagSaturation: Double { 0.4 }

    /// Saturation is a proportion, and a proportion needs a denominator worth
    /// dividing by — in a three-note corpus every tag looks saturated. Below
    /// this size the cap is not applied at all.
    public var saturationAppliesAboveCorpusSize: Int { 10 }

    /// Hard caps on how much one run may do, spent on the highest-confidence
    /// proposals first. Bounds the blast radius of a rule that turns out to be
    /// wrong, and keeps a first run against an untouched corpus from burying
    /// the review queue in dozens of flags — the fastest way to teach someone
    /// to ignore it.
    public var cosmeticBudget: Int {
        switch autonomy {
        case .eco: return 3
        case .balanced: return 10
        case .aggressive: return 20
        }
    }

    public var structuralBudget: Int {
        switch autonomy {
        case .eco: return 0
        case .balanced: return 5
        case .aggressive: return 15
        }
    }
}

/// The janitor's eyes. A pure function from projected notes to proposals:
/// it holds no service, opens no file, and appends no event, so a rule cannot
/// accidentally acquire the ability to write. Acting on any of this is
/// `JanitorRunner`'s job, under different and much narrower rules.
public enum Janitor {
    public static func scan(
        notes: [Note],
        config: JanitorConfig,
        similarity: SimilarityProvider = TokenOverlapSimilarity()
    ) -> [JanitorProposal] {
        // Archived notes are out of scope entirely. Archiving is how a human
        // says "stop showing me this"; a janitor that kept mining archives for
        // proposals would quietly undo that.
        let live = notes.filter { !$0.archived }

        var proposals = cosmeticTagProposals(live, config: config)

        if config.runsStructuralRules {
            proposals += duplicateProposals(live, config: config, similarity: similarity)
            proposals += mistypedLinkProposals(live)
            if config.detectsOrphans {
                proposals += orphanProposals(live)
            }
        }

        return proposals
    }

    // MARK: - Cosmetic

    /// Reuses tags the corpus already agrees on. Never invents one: the
    /// candidate must already be in use elsewhere *and* appear as a whole word
    /// in this note's own text. Both halves matter — the first keeps the tag
    /// vocabulary from sprawling, the second keeps the janitor from guessing.
    private static func cosmeticTagProposals(_ notes: [Note], config: JanitorConfig) -> [JanitorProposal] {
        let established = establishedTags(notes, config: config)
        var proposals: [JanitorProposal] = []
        for note in notes {
            let words = TokenOverlapSimilarity.tokens("\(note.title) \(note.body)")
            for tag in established.sorted() where !note.tags.contains(tag) {
                guard words.contains(tag.lowercased()) else { continue }
                proposals.append(JanitorProposal(noteID: note.id, noteTitle: note.title, kind: .addTag(tag)))
            }
        }
        return proposals
    }

    /// Tags the corpus already agrees on — used enough to not be a one-off,
    /// not so much it's wallpaper (see `maximumTagSaturation`). Shared between
    /// the after-the-fact scan above and `DraftAdvisor`'s before-the-fact
    /// suggestions at note-creation time, so "what counts as an established
    /// tag" can't drift between the two call sites.
    static func establishedTags(_ notes: [Note], config: JanitorConfig) -> Set<String> {
        var usage: [String: Int] = [:]
        for note in notes {
            for tag in note.tags { usage[tag, default: 0] += 1 }
        }
        let saturationCap = notes.count >= config.saturationAppliesAboveCorpusSize
            ? Double(notes.count) * config.maximumTagSaturation
            : Double.infinity
        return Set(
            usage
                .filter { $0.value >= config.minimumTagCorpusUse && $0.key.count >= 3 }
                .filter { Double($0.value) <= saturationCap }
                .keys
        )
    }

    // MARK: - Structural

    /// O(n²) over live notes. Fine at this corpus's scale (tens to low
    /// thousands); if the log ever gets big this wants blocking by shared token
    /// before the pairwise pass — same caveat as PROJECT_NOTES.md deferred #8.
    private static func duplicateProposals(
        _ notes: [Note],
        config: JanitorConfig,
        similarity: SimilarityProvider
    ) -> [JanitorProposal] {
        // Oldest first, so the proposal always lands on the newer note and
        // points back at the one that was there first.
        let ordered = notes.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let threshold = config.duplicateThreshold(similarity.calibration)
        var proposals: [JanitorProposal] = []

        for (index, older) in ordered.enumerated() {
            for newer in ordered.dropFirst(index + 1) {
                // Titles only, not bodies: a title is permanent and is the
                // note's identity here, while bodies legitimately diverge as
                // different agents append to them.
                let score = similarity.similarity(older.title, newer.title)
                guard score >= threshold else { continue }
                proposals.append(
                    JanitorProposal(
                        noteID: newer.id,
                        noteTitle: newer.title,
                        kind: .possibleDuplicate(other: older.id, otherTitle: older.title, similarity: score)
                    )
                )
            }
        }
        return proposals
    }

    /// Only flags a dangling link that's *nearly* a real title. A link to a note
    /// that doesn't exist yet is a supported, deliberate move in this system —
    /// flagging every one of those would bury the queue in noise.
    private static func mistypedLinkProposals(_ notes: [Note]) -> [JanitorProposal] {
        let titles = notes.map { (id: $0.id, title: $0.title) }
        var proposals: [JanitorProposal] = []

        for note in notes {
            for target in note.danglingLinks.sorted() {
                // Short targets are too easy to land within two edits of an
                // unrelated title by coincidence.
                guard target.count >= 4 else { continue }
                let match = titles
                    .filter { $0.id != note.id }
                    .map { (entry: $0, distance: TextDistance.levenshtein(target, $0.title, limit: 2)) }
                    .filter { $0.distance <= 2 }
                    .min { ($0.distance, $0.entry.title) < ($1.distance, $1.entry.title) }

                guard let match else { continue }
                proposals.append(
                    JanitorProposal(
                        noteID: note.id,
                        noteTitle: note.title,
                        kind: .likelyMistypedLink(
                            target: target,
                            suggestion: match.entry.title,
                            suggestionID: match.entry.id
                        )
                    )
                )
            }
        }
        return proposals
    }

    private static func orphanProposals(_ notes: [Note]) -> [JanitorProposal] {
        notes
            .filter { $0.tags.isEmpty && $0.outboundLinks.isEmpty && $0.backlinks.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
            .map { JanitorProposal(noteID: $0.id, noteTitle: $0.title, kind: .orphaned) }
    }
}
