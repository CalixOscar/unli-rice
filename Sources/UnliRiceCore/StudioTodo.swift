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

    public let items: [Item]
    public init(items: [Item]) { self.items = items }

    public var atRisk: [Item] { items.filter { $0.kind == .atRisk } }

    // MARK: - Derivation

    /// Build the list from a published snapshot plus whatever notes are readable.
    ///
    /// `nextSteps` maps project name to the `**Next step:**` line of its memory.md. It
    /// is passed in rather than read here so this stays testable and free of I/O — the
    /// same reason `DataLocation` takes its persisted path as an argument.
    public static func derive(
        from snapshot: RepoSnapshotFile,
        nextSteps: [String: String] = [:],
        worktreeDirt: [String: Int] = [:]
    ) -> StudioTodo {
        var out: [Item] = []

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

            // 3. What the founder said was next. Not inferred — written down.
            // .whitespacesAndNewlines, not .whitespaces: the latter excludes newlines,
            // so a field containing only "  \n  " passed the guard and produced a task
            // with an empty title.
            if let step = nextSteps[p],
               !step.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(Item(
                    id: "\(p)/next-step",
                    project: p,
                    kind: .declared,
                    title: step.trimmingCharacters(in: .whitespacesAndNewlines),
                    evidence: "From \(p)/memory.md",
                    fix: nil))
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
                    title: "\(openWork.count) branch \(openWork.count == 1 ? "is" : "are") ahead of \(repo.trunk ?? "the trunk")",
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
        })
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
