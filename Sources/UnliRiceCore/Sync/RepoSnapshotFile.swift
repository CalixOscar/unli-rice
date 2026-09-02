import Foundation

/// A read-only picture of the Mac's repositories, published into the shared sync folder
/// so the phone can display it.
///
/// **Why a file and not a scanner on the phone.** There are no git repositories on an
/// iPhone, and iOS gives an app no access to a Mac's filesystem. The only honest way for
/// Capture to show this is for the Mac — which already has the folder grant and the
/// scanner — to publish a snapshot into the shared iCloud folder both devices agree on.
/// The phone renders it; it never scans, and it cannot act on it.
///
/// **Staleness is part of the data, not an afterthought.** A snapshot is a photograph, and
/// a dashboard confidently showing yesterday's branch state is worse than showing nothing.
/// `generatedAt` is required so the reader can say how old it is, and `isStale` gives the
/// UI one place to make that judgement instead of scattering thresholds.
public struct RepoSnapshotFile: Codable, Equatable, Sendable {

    /// Bumped when the shape changes. A phone on an older build must refuse an unknown
    /// version rather than silently decode a subset and render a half-truth.
    /// v2 adds ancestry (`parent`, `aheadOfParent`, `aheadOfTrunk`, `trunk`). All of it
    /// is optional, so a v1 file still decodes and simply renders without nesting.
    /// v3 adds the junctions a branch's history actually has: where it forked from the
    /// trunk and where (if ever) it rejoined. Still all optional, so v1 and v2 files
    /// decode and render with less detail rather than failing.
    public static let currentVersion = 3

    /// Written by the Mac, atomically, into the shared folder root.
    public static let filename = "repos.json"

    public struct Branch: Codable, Equatable, Sendable {
        public let name: String
        public let sha: String
        public let tipOnRemote: Bool
        public let isCurrent: Bool

        // MARK: Ancestry — nil unless a producer that can read commits filled it in.
        //
        // Refs alone cannot answer these; they need the commit graph. The app's own
        // in-process scanner deliberately leaves them nil rather than guessing, and
        // check-repos.sh fills them using real git. Optionality IS the honesty
        // mechanism: a missing value renders as "unknown", never as zero.

        /// The nearest branch that is a STRICT ancestor of this one — the branch this
        /// one builds on. Strict matters: two branches at the same commit are aliases,
        /// not parent and child, and treating them as related produced mutual cycles
        /// (elegant-chebyshev naming serene-wu naming elegant-chebyshev).
        public let parent: String?
        /// Commits on this branch that are not on `parent`.
        public let aheadOfParent: Int?
        /// Commits on this branch that are not on the trunk.
        public let aheadOfTrunk: Int?
        /// One of "loop", "open" or "tick" — the three shapes a branch's history can
        /// have relative to the trunk, and only one can be true of a given branch.
        ///   loop — it left the trunk and came back, closed by a merge commit
        ///   open — it left and has not come back
        ///   tick — it never left; the label sits on the trunk's own line
        public let shape: String?
        /// Where it left the trunk, and how many trunk commits sit between there and
        /// the tip. Distance is what lets the graph place the junction to scale.
        public let forkSha: String?
        public let forkBack: Int?
        /// Where it rejoined. Nil for "open" and "tick".
        public let rejoinSha: String?
        public let rejoinBack: Int?
        /// Commits that were on the siding — the length of the detour.
        public let sidingCommits: Int?
        /// Commits on the trunk that are not on this branch — how far back it sits.
        /// Only meaningful when `aheadOfTrunk == 0`: such a branch never forked, it is
        /// a label on the trunk's own history, and this says where.
        public let behindTrunk: Int?

        public init(name: String, sha: String, tipOnRemote: Bool, isCurrent: Bool,
                    parent: String? = nil, aheadOfParent: Int? = nil,
                    aheadOfTrunk: Int? = nil, behindTrunk: Int? = nil,
                    shape: String? = nil, forkSha: String? = nil, forkBack: Int? = nil,
                    rejoinSha: String? = nil, rejoinBack: Int? = nil,
                    sidingCommits: Int? = nil) {
            self.name = name
            self.sha = sha
            self.tipOnRemote = tipOnRemote
            self.isCurrent = isCurrent
            self.parent = parent
            self.aheadOfParent = aheadOfParent
            self.aheadOfTrunk = aheadOfTrunk
            self.behindTrunk = behindTrunk
            self.shape = shape
            self.forkSha = forkSha
            self.forkBack = forkBack
            self.rejoinSha = rejoinSha
            self.rejoinBack = rejoinBack
            self.sidingCommits = sidingCommits
        }
    }

    public struct Worktree: Codable, Equatable, Sendable {
        public let name: String
        public let branch: String?
        public let missing: Bool

        public init(name: String, branch: String?, missing: Bool) {
            self.name = name
            self.branch = branch
            self.missing = missing
        }
    }

    /// A fork-and-rejoin in the trunk's history.
    ///
    /// Loops belong to MERGE COMMITS, not to branches. Attributing one to every branch
    /// whose tip happens to sit upstream of a merge reported the same pair for fourteen
    /// branches in one repo, which says nothing. A branch is only *on* a loop when its
    /// tip is one of the siding's commits — and a loop whose branch label was since
    /// deleted is still real history, which is why these are carried per repo.
    public struct Loop: Codable, Equatable, Sendable {
        public let mergeSha: String
        public let forkSha: String
        /// Trunk commits between the junction and the trunk tip. Larger is older.
        public let forkBack: Int
        public let rejoinBack: Int
        /// How many commits ran on the siding.
        public let commits: Int
        public let subject: String

        public init(mergeSha: String, forkSha: String, forkBack: Int,
                    rejoinBack: Int, commits: Int, subject: String) {
            self.mergeSha = mergeSha
            self.forkSha = forkSha
            self.forkBack = forkBack
            self.rejoinBack = rejoinBack
            self.commits = commits
            self.subject = subject
        }

        /// Trunk commits the siding ran alongside. Zero means it rejoined immediately.
        public var trunkSpan: Int { max(0, forkBack - rejoinBack) }
    }

    public struct Repo: Codable, Equatable, Sendable {
        public let name: String
        public let currentBranch: String?
        public let detachedHead: Bool
        public let branches: [Branch]
        public let remoteBranchCount: Int
        public let worktrees: [Worktree]
        /// The branch the ancestry is measured against.
        public let trunk: String?
        /// Commits on the trunk. The scale every junction position is measured against.
        public let trunkLength: Int?
        public let loops: [Loop]?

        /// True when a producer supplied ancestry. The UI uses this to choose between
        /// drawing real nesting and drawing a flat fan, rather than inferring it from
        /// whether some branch happens to have a parent.
        public var hasAncestry: Bool { branches.contains { $0.parent != nil || $0.aheadOfTrunk != nil } }

        public init(name: String, currentBranch: String?, detachedHead: Bool,
                    branches: [Branch], remoteBranchCount: Int, worktrees: [Worktree],
                    trunk: String? = nil, trunkLength: Int? = nil,
                    loops: [Loop]? = nil) {
            self.name = name
            self.currentBranch = currentBranch
            self.detachedHead = detachedHead
            self.branches = branches
            self.remoteBranchCount = remoteBranchCount
            self.worktrees = worktrees
            self.trunk = trunk
            self.trunkLength = trunkLength
            self.loops = loops
        }

        public var branchesNotOnAnyRemote: [Branch] { branches.filter { !$0.tipOnRemote } }
    }

    public let version: Int
    public let generatedAt: Date
    /// Which Mac produced this. Two Macs writing the same folder would otherwise be
    /// indistinguishable, and "your repos" would silently mean "somebody's repos".
    public let deviceLabel: String
    public let repos: [Repo]

    public init(version: Int = RepoSnapshotFile.currentVersion,
                generatedAt: Date = Date(),
                deviceLabel: String,
                repos: [Repo]) {
        self.version = version
        self.generatedAt = generatedAt
        self.deviceLabel = deviceLabel
        self.repos = repos
    }

    /// No path here is a deletion path. Nothing in this file can act on a repository —
    /// it carries names and flags, never a filesystem path the phone could try to use.
    public var totalBranchesNotOnAnyRemote: Int {
        repos.reduce(0) { $0 + $1.branchesNotOnAnyRemote.count }
    }

    public func isStale(now: Date = Date(), tolerance: TimeInterval = 60 * 60 * 6) -> Bool {
        now.timeIntervalSince(generatedAt) > tolerance
    }

    // MARK: - Reading and writing

    public enum ReadError: Error, LocalizedError, Equatable {
        case missing
        case unreadable
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .missing:
                return "No repository snapshot has been published to the shared folder yet."
            case .unreadable:
                return "The repository snapshot could not be read. It was left untouched."
            case .unsupportedVersion(let v):
                return "This snapshot uses format version \(v), which this app does not understand. Update the app."
            }
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Atomic by construction. A half-written JSON read mid-scan by the phone is the
    /// obvious first bug in a two-process file handoff, and `.atomic` costs nothing.
    public func write(toFolder folder: URL) throws {
        let data = try Self.encoder.encode(self)
        try data.write(to: folder.appendingPathComponent(Self.filename), options: .atomic)
    }

    public static func read(fromFolder folder: URL) throws -> RepoSnapshotFile {
        let url = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ReadError.missing }
        guard let data = try? Data(contentsOf: url) else { throw ReadError.unreadable }

        // Check the version before a full decode, so a newer file fails with a message
        // that names the problem instead of a generic decoding error.
        if let probe = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = probe["version"] as? Int, v > currentVersion {
            throw ReadError.unsupportedVersion(v)
        }
        guard let decoded = try? decoder.decode(RepoSnapshotFile.self, from: data) else {
            throw ReadError.unreadable
        }
        return decoded
    }
}
