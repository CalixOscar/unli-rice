import Foundation

/// What is outstanding across the studio, derived from repository state and notes.
///
/// **Nothing here is stored, and nothing can be ticked off.** Every item is computed
/// from the state that makes it true, so it disappears when the work is actually done:
/// push the commits and "6 commits on no remote" goes away on the next scan. A stored
/// checklist drifts from reality the moment someone does the work without ticking the
/// box — and this codebase has spent a lot of effort on notes that contradict the repo.
/// Deriving is how the list stays honest.
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
        /// Work that is finished but not visible to anyone else yet.
        case unshared = 2
        /// Tidying. Costs nothing to leave, but hides the items above it.
        case clutter = 3

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .atRisk:   return "at risk"
            case .declared: return "next step"
            case .unshared: return "unshared"
            case .clutter:  return "clutter"
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

        public init(id: String, project: String, kind: Kind, title: String,
                    evidence: String, fix: String? = nil) {
            self.id = id
            self.project = project
            self.kind = kind
            self.title = title
            self.evidence = evidence
            self.fix = fix
        }
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
                gaps.append("dirt not measured")
            case .partial(let missing):
                gaps.append("dirt not measured for \(missing.count) of \(repositories.count) repositories")
            case .complete:
                break
            }
            switch nextSteps {
            case .none:
                gaps.append("next steps not read")
            case .partial(let missing):
                gaps.append("next steps not read for \(missing.count) of \(repositories.count) repositories")
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
        worktreeDirt: [String: Int] = [:]
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
                    title: "\(unbacked.count) branch \(unbacked.count == 1 ? "tip" : "tips") on no remote",
                    evidence: names.prefix(4).joined(separator: ", ")
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
                    title: "\(dirt) uncommitted \(dirt == 1 ? "file" : "files") in worktrees",
                    evidence: "In no commit anywhere. Deleting the folder loses them.",
                    fix: nil))
            }

            // 3. What the founder said was next.
            let mem = nextSteps[p]
            switch mem {
            case .step(let step):
                let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    out.append(Item(
                        id: "\(p)/next-step",
                        project: p,
                        kind: .declared,
                        title: trimmed,
                        evidence: "From \(p)/memory.md",
                        fix: nil))
                }
            case .readNoStep:
                // File was read and explicitly names no next step.
                // Suppress snapshot fallback!
                break
            case .unreadable, .none:
                // Falls back to snapshot's copy
                if let declared = repo.nextStep,
                   !declared.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    out.append(Item(
                        id: "\(p)/next-step",
                        project: p,
                        kind: .declared,
                        title: declared.trimmingCharacters(in: .whitespacesAndNewlines),
                        evidence: "From \(p)/memory.md, as of the last snapshot",
                        fix: nil))
                }
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
                        ? "1 branch is ahead of \(repo.trunk ?? "the trunk")"
                        : "\(openWork.count) branches are ahead of \(repo.trunk ?? "the trunk")",
                    evidence: openWork.map { "\($0.name) +\($0.aheadOfTrunk ?? 0)" }
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
                    title: "\(merged.count) merged branches could be deleted",
                    evidence: "Nothing on them that is not on \(repo.trunk ?? "the trunk").",
                    fix: "git -C \"\(p)\" branch --merged \(repo.trunk ?? "main") | grep -v '\\*' | xargs -n1 git branch -d"))
            }
        }

        // Most urgent first, then by project so one project's items stay together.
        return StudioTodo(items: out.sorted {
            ($0.kind, $0.project, $0.title) < ($1.kind, $1.project, $1.title)
        }, coverage: coverage)
    }

    /// Pull the `**Next step:**` field out of a memory.md body.
    ///
    /// Deliberately tolerant of the field spanning several lines, because the contract
    /// only fixes the field ORDER, not that each value is one line — and a next step
    /// worth writing is usually longer than one.
    public static func nextStep(fromMemory body: String) -> String? {
        guard let r = body.range(of: "**Next step:**") else { return nil }
        let rest = body[r.upperBound...]
        var collected: [String] = []
        for line in rest.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = line.trimmingCharacters(in: .whitespaces)
            // The next field ends it — the six are fixed and ordered.
            if t.hasPrefix("**") && t.contains(":**") { break }
            if t.isEmpty && !collected.isEmpty { break }
            if !t.isEmpty { collected.append(t) }
        }
        let joined = collected.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? nil : joined
    }
}
