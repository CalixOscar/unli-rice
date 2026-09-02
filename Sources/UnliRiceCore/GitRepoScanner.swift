import Foundation

/// Reads a git repository's *refs* — branches, remotes, worktrees — without running
/// git.
///
/// **Why no `Process`.** This app ships sandboxed on the Mac App Store, and the App
/// Sandbox forbids `Process`/`NSTask` outright; there is no entitlement that permits
/// it and `temporary-exception.*` does not survive App Review. Unli Disk learned this
/// the expensive way on 2026-08-01: its `GitObjectScanner` used four `git`
/// subprocesses, and under the sandbox it would have compiled, run, and *silently
/// stopped finding anything*. This type is written the same way that one was
/// rewritten — direct reads of `HEAD`, `refs/`, `packed-refs` and `worktrees/`.
///
/// **What it deliberately does not do: ahead/behind counts.** Those need a walk over
/// commit objects, which are zlib-deflated when loose and inside a packfile when not.
/// A partial implementation would answer confidently and wrongly on any established
/// repo, where most commits are packed. Refs alone can prove whether a branch tip
/// exists on a remote, and that is the question worth answering — so that is the
/// question this answers. Anything it cannot prove is reported as unknown rather than
/// guessed, matching the conservative `Bool?` semantics the studio's other scanner
/// settled on.
public struct GitRepoScanner: Sendable {

    public init() {}

    // MARK: - Model

    public struct Branch: Identifiable, Equatable, Sendable {
        public let name: String
        public let sha: String
        /// True when some remote-tracking ref points at exactly this commit, so the
        /// tip is known to exist somewhere other than this machine. False means the
        /// tip is not on any remote *this repo has fetched* — which is the honest
        /// claim; a remote could hold it under a ref we have never fetched.
        public let tipOnRemote: Bool
        public let isCurrent: Bool

        public var id: String { name }
    }

    public struct Worktree: Identifiable, Equatable, Sendable {
        public let name: String
        public let path: String
        public let branch: String?
        /// A registered worktree whose directory is gone. `git worktree prune`
        /// clears it; nothing is lost, because the commits live in this repo's
        /// shared object store.
        public let missing: Bool

        public var id: String { path }
    }

    public struct Snapshot: Equatable, Sendable {
        public let name: String
        public let path: String
        public let currentBranch: String?
        public let detachedHead: Bool
        public let branches: [Branch]
        public let remoteBranchCount: Int
        public let worktrees: [Worktree]
        /// The branch every other branch is understood to fork from. Read from
        /// `refs/remotes/origin/HEAD` where it exists, else `main`, else `master`.
        /// Nil only when none of those resolve to a local branch.
        public let defaultBranch: String?

        /// Branches whose tip is on no remote this repo has fetched. The number that
        /// describes work which would be lost with the disk.
        public var branchesNotOnAnyRemote: [Branch] { branches.filter { !$0.tipOnRemote } }
    }

    public enum ScanError: Error, LocalizedError, Equatable {
        case notARepository(String)

        public var errorDescription: String? {
            switch self {
            case .notARepository(let p):
                return "No git repository at \(p). Nothing was read."
            }
        }
    }

    // MARK: - Scanning

    /// Scan one repository. `url` is the working directory, not the `.git` folder.
    public func scan(repositoryAt url: URL) throws -> Snapshot {
        let fm = FileManager.default
        let dotGit = url.appendingPathComponent(".git")

        // `.git` is a directory in a normal clone and a FILE in a linked worktree,
        // where it holds "gitdir: <path>". Resolving that is what makes a worktree
        // scannable at all.
        var gitDir = dotGit
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) else {
            throw ScanError.notARepository(url.path)
        }
        if !isDir.boolValue {
            guard let line = try? String(contentsOf: dotGit, encoding: .utf8),
                  let raw = line.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
            else { throw ScanError.notARepository(url.path) }
            let p = raw.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            gitDir = URL(fileURLWithPath: p)
        }

        // A linked worktree's refs live in the COMMON dir, not its own gitdir. Without
        // this a worktree reports zero branches, which reads as an empty repo.
        let commonDir = Self.commonDir(for: gitDir)

        let packed = Self.readPackedRefs(in: commonDir)
        let localRefs = Self.readLooseRefs(in: commonDir.appendingPathComponent("refs/heads"))
            .merging(packed.heads) { loose, _ in loose }     // loose wins; it is newer
        let remoteRefs = Self.readLooseRefs(in: commonDir.appendingPathComponent("refs/remotes"))
            .merging(packed.remotes) { loose, _ in loose }

        let remoteSHAs = Set(remoteRefs.values)
        let (current, detached) = Self.readHead(in: gitDir)

        let branches = localRefs
            .map { name, sha in
                Branch(name: name,
                       sha: sha,
                       tipOnRemote: remoteSHAs.contains(sha),
                       isCurrent: name == current)
            }
            .sorted { $0.name < $1.name }

        return Snapshot(
            name: url.lastPathComponent,
            path: url.path,
            currentBranch: current,
            detachedHead: detached,
            branches: branches,
            remoteBranchCount: remoteRefs.count,
            worktrees: Self.readWorktrees(in: commonDir),
            defaultBranch: Self.defaultBranch(in: commonDir, localNames: Set(localRefs.keys))
        )
    }

    /// Scan every immediate subdirectory of `url` that is a repository. Directories
    /// that are not repositories are skipped silently — a projects folder holds
    /// plenty of things that were never git repos, and that is not an error.
    public func scanAll(in url: URL) -> [Snapshot] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { try? scan(repositoryAt: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Reading git's on-disk formats

    /// Which branch is the trunk.
    ///
    /// `refs/remotes/origin/HEAD` is a symref naming the remote's default branch — the
    /// authoritative answer when it exists. It is skipped by `readLooseRefs` because it
    /// holds a ref name rather than a 40-character SHA, so it is read separately here.
    /// Falling back to `main` then `master` covers repos that were never cloned.
    static func defaultBranch(in commonDir: URL, localNames: Set<String>) -> String? {
        let head = commonDir.appendingPathComponent("refs/remotes/origin/HEAD")
        if let raw = try? String(contentsOf: head, encoding: .utf8) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let r = line.range(of: "refs/remotes/origin/") {
                let name = String(line[r.upperBound...])
                if localNames.contains(name) { return name }
            }
        }
        for candidate in ["main", "master"] where localNames.contains(candidate) {
            return candidate
        }
        return nil
    }

    /// A linked worktree's gitdir is `<common>/worktrees/<name>`, and `commondir`
    /// inside it points back. Resolve it so refs are read from one place.
    static func commonDir(for gitDir: URL) -> URL {
        let marker = gitDir.appendingPathComponent("commondir")
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return gitDir }
        let rel = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rel.isEmpty else { return gitDir }
        if rel.hasPrefix("/") { return URL(fileURLWithPath: rel) }
        return URL(fileURLWithPath: rel, relativeTo: gitDir).standardizedFileURL
    }

    /// `HEAD` is either `ref: refs/heads/<name>` or a bare SHA (detached).
    static func readHead(in gitDir: URL) -> (branch: String?, detached: Bool) {
        guard let raw = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"),
                                    encoding: .utf8) else { return (nil, false) }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") {
            return (String(line.dropFirst("ref: refs/heads/".count)), false)
        }
        return (nil, !line.isEmpty)
    }

    /// Walk a refs directory. Branch names contain slashes (`feature/x`), which are
    /// real subdirectories on disk, so this recurses and rebuilds the name.
    ///
    /// The name is rebuilt from *path components*, not by stripping a string prefix.
    /// Prefix stripping looks correct and is not: the enumerator hands back
    /// symlink-resolved paths, so on any tree under `/var` (which is a symlink to
    /// `/private/var`) the prefix fails to match at the front and instead matches
    /// mid-path, turning `main` into `/privatemain`. Every branch name in the repo
    /// comes out corrupted, and the branch/packed-ref merge then silently keeps the
    /// stale packed SHA because the loose key no longer collides with it. Caught by
    /// the tests on 2026-09-02.
    static func readLooseRefs(in root: URL) -> [String: String] {
        let fm = FileManager.default
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        // No `.skipsHiddenFiles`. Everything here lives inside `.git`, which IS a
        // hidden directory, and on a real volume the enumerator then yields nothing at
        // all — it treats descendants of a hidden ancestor as hidden. In a temp-dir
        // fixture it does not, so this passed nine unit tests while returning zero
        // loose refs against the actual repository: 13 packed branches found, 21 real,
        // and the missing 9 were silently replaced by their stale packed SHAs. Caught
        // 2026-09-02 only because the integration test ran against a real checkout.
        // Ref names cannot begin with a dot, so nothing needs filtering here.
        guard let e = fm.enumerator(at: base,
                                    includingPropertiesForKeys: [.isRegularFileKey],
                                    options: []) else { return [:] }
        let baseCount = base.pathComponents.count
        var out: [String: String] = [:]
        for case let url as URL in e {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let sha = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            let parts = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard parts.count > baseCount else { continue }
            let name = parts.dropFirst(baseCount).joined(separator: "/")
            let value = sha.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 40 else { continue }   // skip symrefs like origin/HEAD
            out[name] = value
        }
        return out
    }

    /// `packed-refs` is a flat text file. Anything not refreshed recently lives here
    /// rather than as a loose file, so a scanner that reads only `refs/` misses most
    /// branches in an established repo.
    static func readPackedRefs(in commonDir: URL) -> (heads: [String: String], remotes: [String: String]) {
        guard let raw = try? String(contentsOf: commonDir.appendingPathComponent("packed-refs"),
                                    encoding: .utf8) else { return ([:], [:]) }
        var heads: [String: String] = [:], remotes: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            if line.hasPrefix("#") || line.hasPrefix("^") { continue }  // ^ = peeled tag
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let sha = String(parts[0]), ref = String(parts[1])
            if ref.hasPrefix("refs/heads/") {
                heads[String(ref.dropFirst("refs/heads/".count))] = sha
            } else if ref.hasPrefix("refs/remotes/") {
                let n = String(ref.dropFirst("refs/remotes/".count))
                if !n.hasSuffix("/HEAD") { remotes[n] = sha }
            }
        }
        return (heads, remotes)
    }

    /// Linked worktrees are registered under `<common>/worktrees/<name>/`, each with a
    /// `gitdir` file naming the checkout's `.git` path.
    static func readWorktrees(in commonDir: URL) -> [Worktree] {
        let fm = FileManager.default
        let root = commonDir.appendingPathComponent("worktrees")
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        return names.sorted().compactMap { name in
            let dir = root.appendingPathComponent(name)
            guard let raw = try? String(contentsOf: dir.appendingPathComponent("gitdir"),
                                        encoding: .utf8) else { return nil }
            // The file names the worktree's own .git; the checkout is its parent.
            let gitPath = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let checkout = URL(fileURLWithPath: gitPath).deletingLastPathComponent()
            let (branch, _) = readHead(in: dir)
            return Worktree(name: name,
                            path: checkout.path,
                            branch: branch,
                            missing: !fm.fileExists(atPath: checkout.path))
        }
    }
}
