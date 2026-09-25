import Foundation

/// What is outstanding across the studio, derived from repository state and notes.
///
/// **The derivation stores nothing, and derived items cannot be ticked off.** Every item
/// is computed from the state that makes it true, so it disappears when the work is actually
/// done: push the commits and "6 commits on no remote" goes away on the next scan. A stored
/// checklist drifts from reality the moment someone does the work without ticking the
/// box — and this codebase has spent a lot of effort on notes that contradict the repo.
/// Deriving is how the list stays honest. One input it derives from is stored notes tagged
/// `todo`: those are notes, and Done archives them.
///
/// It adds no `EventKind` and writes nothing. Locked decision #3 — propose, never apply —
/// holds: this reports, and the founder acts.
/// The result of trying to read one project's memory.md.
///
/// `.readNoStep` is the case the loader could not express before: the file was
/// read successfully and names no next step. Collapsing it into "unreadable"
/// let the snapshot's older copy win, resurrecting steps already completed.
public enum MemoryRead: Equatable, Sendable {
    case unreadable
    case readNoStep
    case step(String)
}

extension MemoryRead: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .step(value)
    }
}

public struct StudioTodo: Equatable, Sendable {

    /// Why an item exists. Ordering of the enum is the ordering of urgency, and it is
    /// deliberate: work that exists on one machine only is the only category here that
    /// can be permanently lost.
    public enum Kind: Int, Comparable, Sendable, CaseIterable {
        /// Commits or files that exist nowhere else. Losing the disk loses them.
        case atRisk = 0
        /// Something the founder wrote down as the next step and has not done.
        case declared = 1
        /// An AI session flagged this, not the founder.
        case aiFlagged = 2
        /// Work that is finished but not visible to anyone else yet.
        case unshared = 3
        /// Tidying. Costs nothing to leave, but hides the items above it.
        case clutter = 4

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// The group heading. Plain words: the founder reads this list, and is not a
        /// developer (2026-09-25). The technical term, where one helps an AI, stays in
        /// each item's evidence line instead.
        public var label: String {
            switch self {
            case .atRisk:    return "not backed up"
            case .declared:  return "next step"
            case .aiFlagged: return "suggested by AI"
            case .unshared:  return "not merged yet"
            case .clutter:   return "tidy-up"
            }
        }

        /// Why the group is where it is, so the ordering is not arbitrary. One place, so
        /// the Mac and phone panes can't word it differently.
        public var blurb: String {
            switch self {
            case .atRisk:    return "only on this Mac — if the Mac is lost, this work is gone"
            case .declared:  return "written down as the next step in the project's notes"
            case .aiFlagged: return "an AI assistant suggested this for later"
            case .unshared:  return "backed up online, but not yet part of the main version"
            case .clutter:   return "harmless leftovers that crowd the list"
            }
        }
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let project: String
        public let kind: Kind
        public let title: String
        /// What makes this true, so the reader can check rather than trust.
        public let evidence: String
        /// The command that resolves it, when one exists. Never run automatically.
        public let fix: String?
        /// The underlying note, when this item came from one — lets the UI archive it
        /// directly instead of parsing an intent back out of `id`. Nil for every kind
        /// that isn't `.aiFlagged`.
        public let noteID: UUID?
        /// The full text behind a shortened `title`, shown on request. Set only for a
        /// memory.md next step, which is written for the next AI session and can run to
        /// a paragraph; the list shows its first sentence (2026-09-25).
        public let detail: String?

        public init(id: String, project: String, kind: Kind, title: String,
                    evidence: String, fix: String? = nil, noteID: UUID? = nil,
                    detail: String? = nil) {
            self.id = id
            self.project = project
            self.kind = kind
            self.title = title
            self.evidence = evidence
            self.fix = fix
            self.noteID = noteID
            self.detail = detail
        }
    }

    /// A memory.md next step's headline, for the founder to scan: the first paragraph when
    /// the field is written the current way (plain sentence, blank line, detail), else the
    /// first sentence, cut at 160 characters. Markdown emphasis and code ticks removed.
    /// `detail` is the full text, or nil when the headline already is all of it.
    public static func headline(forNextStep text: String) -> (title: String, detail: String?) {
        let full = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = full.replacingOccurrences(of: "**", with: "")
                        .replacingOccurrences(of: "`", with: "")
        // Written the current way — a plain first paragraph, then the detail: the whole
        // first paragraph is the headline, unless it runs long.
        if let breakRange = plain.range(of: "\n\n") {
            let lead = String(plain[..<breakRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !lead.isEmpty && lead.count <= 240 { return (lead, full) }
        }
        var end = plain.endIndex
        for marker in [". ", ".\n", "\n", "! ", "? "] {
            if let r = plain.range(of: marker), r.lowerBound < end {
                end = marker.hasPrefix("\n") ? r.lowerBound : plain.index(after: r.lowerBound)
            }
        }
        var first = String(plain[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if first.count > 160 {
            first = String(first.prefix(157)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return first == full ? (full, nil) : (first, full)
    }

    /// What this list actually looked at.
    ///
    /// Separate from the items, because "found nothing" and "never looked" are
    /// different answers and only one of them licenses the words "nothing
    /// outstanding". Measured against the snapshot's OWN repository set: a set of
    /// measured names alone cannot tell partial coverage from complete, and
    /// reporting partial as complete is the bug this type exists to prevent.
    public struct Coverage: Equatable, Sendable {

        public enum Extent: Equatable, Sendable {
            /// Nothing was inspected. The list is uninformed, not empty.
            case none
            /// Some repositories were inspected; `missing` names those that were not.
            case partial(missing: Set<String>)
            /// Every repository in the snapshot was inspected.
            case complete
        }

        /// False means no snapshot was read at all — the whole list is uninformed.
        public let snapshotRead: Bool
        /// Every repository the snapshot contained. Empty with `snapshotRead == true`
        /// is its own answer: a snapshot that found no repositories.
        public let repositories: Set<String>
        /// How much of `repositories` had its uncommitted-file count measured.
        public let dirt: Extent
        /// How much of `repositories` had its memory.md read — successfully, whether
        /// or not a step was found. See `MemoryRead`.
        public let nextSteps: Extent
        /// When the snapshot was produced. Every finding is only as current as this.
        public let generatedAt: Date?

        public init(
            snapshotRead: Bool,
            repositories: Set<String>,
            dirt: Extent,
            nextSteps: Extent,
            generatedAt: Date? = nil
        ) {
            self.snapshotRead = snapshotRead
            self.repositories = repositories
            self.dirt = dirt
            self.nextSteps = nextSteps
            self.generatedAt = generatedAt
        }

        public var gapSummary: String? {
            guard snapshotRead, !repositories.isEmpty else { return nil }
            var gaps: [String] = []
            switch dirt {
            case .none:
                gaps.append("unsaved changes weren't checked")
            case .partial(let missing):
                gaps.append("unsaved changes weren't checked in \(missing.count) of \(repositories.count) projects")
            case .complete:
                break
            }
            switch nextSteps {
            case .none:
                gaps.append("next steps weren't read")
            case .partial(let missing):
                gaps.append("next steps weren't read in \(missing.count) of \(repositories.count) projects")
            case .complete:
                break
            }
            return gaps.isEmpty ? nil : gaps.joined(separator: " · ")
        }
    }

    public let items: [Item]
    public let coverage: Coverage

    public init(items: [Item], coverage: Coverage) {
        self.items = items
        self.coverage = coverage
    }

    public init(items: [Item]) {
        self.items = items
        self.coverage = Coverage(
            snapshotRead: false,
            repositories: [],
            dirt: .none,
            nextSteps: .none,
            generatedAt: nil
        )
    }

    public static func unread() -> StudioTodo {
        StudioTodo(
            items: [],
            coverage: Coverage(
                snapshotRead: false,
                repositories: [],
                dirt: .none,
                nextSteps: .none,
                generatedAt: nil
            )
        )
    }

    public var atRisk: [Item] { items.filter { $0.kind == .atRisk } }

    // MARK: - Derivation

    private static func computeExtent(inspected: Set<String>, against repositories: Set<String>) -> Coverage.Extent {
        guard !repositories.isEmpty else { return .complete }
        let measured = inspected.intersection(repositories)
        if measured.isEmpty {
            return .none
        } else if measured == repositories {
            return .complete
        } else {
            return .partial(missing: repositories.subtracting(measured))
        }
    }

    /// Build the list from a published snapshot plus whatever notes are readable.
    ///
    /// `nextSteps` maps project name to the result of reading its memory.md. It
    /// is passed in rather than read here so this stays testable and free of I/O — the
    /// same reason `DataLocation` takes its persisted path as an argument.
    public static func derive(
        from snapshot: RepoSnapshotFile,
        nextSteps: [String: MemoryRead] = [:],
        worktreeDirt: [String: Int] = [:],
        aiFlags: [String: [Note]] = [:]
    ) -> StudioTodo {
        var out: [Item] = []
        let reposSet = Set(snapshot.repos.map(\.name))

        let dirtExtent = computeExtent(inspected: Set(worktreeDirt.keys), against: reposSet)

        let readNextSteps = Set(nextSteps.compactMap { (repo, read) -> String? in
            switch read {
            case .readNoStep, .step:
                return repo
            case .unreadable:
                return nil
            }
        })
        let nextStepsExtent = computeExtent(inspected: readNextSteps, against: reposSet)

        let coverage = Coverage(
            snapshotRead: true,
            repositories: reposSet,
            dirt: dirtExtent,
            nextSteps: nextStepsExtent,
            generatedAt: snapshot.generatedAt
        )

        for repo in snapshot.repos {
            let p = repo.name

            // 1. Tips that exist on no remote. The only genuinely unrecoverable state.
            let unbacked = repo.branchesNotOnAnyRemote
            if !unbacked.isEmpty {
                let names = unbacked.map(\.name).sorted()
                out.append(Item(
                    id: "\(p)/unbacked",
                    project: p,
                    kind: .atRisk,
                    title: unbacked.count == 1
                        ? "1 piece of work is saved only on this Mac"
                        : "\(unbacked.count) pieces of work are saved only on this Mac",
                    evidence: "Not backed up online. Branches: "
                            + names.prefix(4).joined(separator: ", ")
                            + (names.count > 4 ? " and \(names.count - 4) more" : ""),
                    fix: "git -C \"\(p)\" push --all"))
            }

            // 2. Files in an abandoned worktree. Its COMMITS are safe in the shared
            //    object store; anything uncommitted is in that folder and nowhere else.
            if let dirt = worktreeDirt[p], dirt > 0 {
                out.append(Item(
                    id: "\(p)/worktree-dirt",
                    project: p,
                    kind: .atRisk,
                    title: dirt == 1
                        ? "1 changed file hasn't been saved yet"
                        : "\(dirt) changed files haven't been saved yet",
                    evidence: "They're only in a side copy of the project (a worktree), in no saved "
                            + "version anywhere. Deleting that folder would lose them.",
                    fix: nil))
            }

            // 3. What the founder said was next.
            let mem = nextSteps[p]
            switch mem {
            case .step(let step):
                let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let head = headline(forNextStep: trimmed)
                    out.append(Item(
                        id: "\(p)/next-step",
                        project: p,
                        kind: .declared,
                        title: head.title,
                        evidence: "Written in \(p)'s notes (memory.md)",
                        fix: nil,
                        detail: head.detail))
                }
            case .readNoStep:
                // File was read and explicitly names no next step.
                // Suppress snapshot fallback!
                break
            case .unreadable, .none:
                // Falls back to snapshot's copy
                if let declared = repo.nextStep,
                   !declared.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let head = headline(forNextStep: declared)
                    out.append(Item(
                        id: "\(p)/next-step",
                        project: p,
                        kind: .declared,
                        title: head.title,
                        evidence: "Written in \(p)'s notes (memory.md), as of the last check",
                        fix: nil,
                        detail: head.detail))
                }
            }

            // 3b. Flagged by AI.
            let pLower = p.lowercased()
            let projectFlags = (aiFlags[pLower] ?? []) + (p != pLower ? (aiFlags[p] ?? []) : [])
            for note in projectFlags where !note.archived && note.tags.contains("todo") && (note.tags.contains(pLower) || note.tags.contains(p)) {
                out.append(Item(
                    id: "\(p)/ai-todo/\(note.id.uuidString)",
                    project: p,
                    kind: .aiFlagged,
                    title: note.title,
                    evidence: TodoWording.subtitle(creator: note.creator,
                                                   createdAt: note.createdAt,
                                                   projects: [p]),
                    fix: nil,
                    noteID: note.id))
            }

            // 4. Finished work nobody else can see. Distinct from at-risk: it exists on
            //    a remote under some name, just not where others would look.
            let openWork = repo.branches.filter {
                ($0.aheadOfTrunk ?? 0) > 0 && $0.tipOnRemote
            }
            if !openWork.isEmpty {
                out.append(Item(
                    id: "\(p)/open-branches",
                    project: p,
                    kind: .unshared,
                    // Pluralise the NOUN as well as the verb. "3 branch are ahead" was
                    // the same slip as "3 branch tipes" — deriving one form from another
                    // instead of writing both.
                    title: openWork.count == 1
                        ? "1 piece of finished work isn't part of \(repo.trunk ?? "the main version") yet"
                        : "\(openWork.count) pieces of finished work aren't part of \(repo.trunk ?? "the main version") yet",
                    evidence: "Backed up online, not merged. Branches: "
                            + openWork.map { "\($0.name) +\($0.aheadOfTrunk ?? 0)" }
                                      .sorted().prefix(3).joined(separator: ", "),
                    fix: nil))
            }

            // 5. Merged branches. Free to delete, and they bury everything above.
            let merged = repo.branches.filter {
                $0.shape == "tick" || ($0.aheadOfTrunk == 0 && $0.name != repo.trunk)
            }.filter { $0.name != repo.trunk }
            if merged.count >= 5 {
                out.append(Item(
                    id: "\(p)/merged",
                    project: p,
                    kind: .clutter,
                    title: "\(merged.count) old, finished branches can be tidied away",
                    evidence: "Everything on them is already in \(repo.trunk ?? "the main version"), so "
                            + "deleting them loses nothing.",
                    fix: "git -C \"\(p)\" branch --merged \(repo.trunk ?? "main") | grep -v '\\*' | xargs -n1 git branch -d"))
            }
        }

        // Most urgent first, then by project so one project's items stay together.
        return StudioTodo(items: out.sorted {
            ($0.kind, $0.project, $0.title) < ($1.kind, $1.project, $1.title)
        }, coverage: coverage)
    }

    /// Open AI-filed to-do notes, keyed by the LOWERCASED project tag, exactly as the two
    /// pane loops do today. Behaviour-preserving extraction; do not re-key (P15).
    /// Open to-dos that no repository in the list claims, as items of their own.
    ///
    /// The widget shows every open `todo` note (D9). The pane used to show only the ones
    /// whose project tag matched a repo in the published snapshot, so a customer with no
    /// snapshot, the default for everyone but the studio, saw none of their AI to-dos.
    /// These rows close that gap: same wording as the widget, grouped under the tag.
    public static func unmatchedAIItems(from notes: [Note], repoNames: Set<String>,
                                        now: Date = Date()) -> [Item] {
        let known = Set(repoNames.map { $0.lowercased() })
        return notes
            .filter { !$0.archived && $0.tags.contains("todo") }
            .filter { note in !TodoWidgetList.projects(of: note).contains { known.contains($0.lowercased()) } }
            .sorted { $0.createdAt < $1.createdAt }
            .map { note in
                let projects = TodoWidgetList.projects(of: note)
                let project = projects.isEmpty ? "no project" : projects.joined(separator: ", ")
                return Item(id: "\(project)/ai-todo/\(note.id.uuidString)",
                            project: project,
                            kind: .aiFlagged,
                            title: note.title,
                            evidence: TodoWording.subtitle(creator: note.creator,
                                                           createdAt: note.createdAt,
                                                           projects: projects, now: now),
                            fix: nil,
                            noteID: note.id)
            }
    }

    /// This list plus extra items, with the same coverage.
    public func adding(_ extra: [Item]) -> StudioTodo {
        extra.isEmpty ? self : StudioTodo(items: items + extra, coverage: coverage)
    }

    public static func aiFlags(from notes: [Note], repoNames: Set<String>) -> [String: [Note]] {
        var aiFlags: [String: [Note]] = [:]
        for note in notes where note.tags.contains("todo") {
            for tag in note.tags where repoNames.contains(where: { $0.lowercased() == tag }) {
                aiFlags[tag, default: []].append(note)
            }
        }
        return aiFlags
    }

    /// Pull the `**Next step:**` field out of a memory.md body.
    ///
    /// Deliberately tolerant of the field spanning several lines, because the contract
    /// only fixes the field ORDER, not that each value is one line — and a next step
    /// worth writing is usually longer than one.
    public static func nextStep(fromMemory body: String) -> String? {
        guard let r = body.range(of: "**Next step:**") else { return nil }
        let rest = body[r.upperBound...]
        // Paragraphs are kept: since 2026-09-25 the field opens with one plain sentence for
        // the founder, then a blank line, then the detail for the next AI session. The
        // headline comes from the first paragraph; Details and Fix with AI get the rest.
        var paragraphs: [[String]] = [[]]
        for line in rest.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            // The next field, a heading, or a comment ends it — the fields are fixed and ordered.
            if t.hasPrefix("**") && t.contains(":**") { break }
            if t.hasPrefix("#") || t.hasPrefix("<!--") { break }
            if t.isEmpty {
                if !(paragraphs.last ?? []).isEmpty { paragraphs.append([]) }
            } else {
                paragraphs[paragraphs.count - 1].append(t)
            }
        }
        let joined = paragraphs
            .map { $0.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}
