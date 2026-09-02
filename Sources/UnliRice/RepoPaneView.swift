import SwiftUI
import UnliRiceCore

/// Branches and worktrees across the folders already granted as `scanRoots`.
///
/// **Read-only, permanently.** No delete, no prune, no `gc`. Two independent reasons,
/// either sufficient: the App Sandbox forbids `Process`, so the subprocess those need
/// cannot exist in a shipping build; and locked decision #3 — this codebase proposes
/// and never applies — is not weaker when the thing being changed is someone's git
/// repository rather than their notes.
///
/// **Reuses the existing grant.** `scanRoots` are folders the user already picked for
/// ingest, persisted as security-scoped bookmarks, so this pane asks for no new
/// permission and stores no new state.
struct RepoPaneView: View {
    @EnvironmentObject var store: AppStore

    @State private var snapshots: [GitRepoScanner.Snapshot] = []
    @State private var scanning = false
    @State private var scanned = false
    /// Published by check-repos.sh --json, keyed by repo name. Empty when the script has
    /// never run — the graph then draws a flat fan and says so.
    @State private var ancestry: [String: RepoSnapshotFile.Repo] = [:]
    @State private var ancestryAge: Date?
    @State private var ancestryStale = false
    /// Persisted: a zoom you have to reset on every launch is worse than no zoom.
    @AppStorage("unliRice.reposGraphZoom") private var zoom: Double = 1.0
    /// Why ancestry is or is not present. Everything used to go through `try?` and
    /// return empty, so "no file", "not allowed to read it" and "decoded but empty" all
    /// rendered identically as a flat graph — which is why this took elimination rather
    /// than one launch to diagnose. The path is included because the folder the app
    /// actually reads is the thing that is hard to guess from outside.
    @State private var ancestryStatus: AncestryStatus = .notLoaded

    enum AncestryStatus {
        case notLoaded
        case loaded(repos: Int, withAncestry: Int, path: String)
        case missing(path: String)
        case denied(path: String)
        case unreadable(path: String, reason: String)

        var line: String {
            switch self {
            case .notLoaded:
                return "ancestry: not loaded yet"
            case .loaded(let n, let a, let p):
                return "ancestry: \(a)/\(n) repos from \(p)"
            case .missing(let p):
                return "ancestry: no repos.json in \(p)"
            case .denied(let p):
                return "ancestry: could not open \(p) — sandbox denied the read"
            case .unreadable(let p, let r):
                return "ancestry: \(p) — \(r)"
            }
        }

        var isProblem: Bool {
            if case .loaded(_, let a, _) = self { return a == 0 }
            if case .notLoaded = self { return false }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if store.scanRoots.isEmpty {
                    emptyGrant
                } else if scanning {
                    ProgressView("Reading refs…")
                        .padding(.vertical, 24)
                } else if scanned && snapshots.isEmpty {
                    noRepos
                } else {
                    ForEach(snapshots, id: \.path) { repoCard($0) }
                }
            }
            .padding(22)
        }
        .task(id: store.scanRoots.map(\.path)) { await scan() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repos")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Branches and worktrees in your scan folders. Read-only — nothing here "
                 + "deletes, prunes or rewrites anything.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Diagnostic, deliberately always visible rather than only on failure: the
            // path it reads is the one thing that cannot be guessed from outside.
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: $zoom, in: 0.6...3.0)
                    .frame(width: 150)
                    .controlSize(.mini)
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Text(String(format: "%.1f×", zoom))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, alignment: .leading)
                Button("Reset") { zoom = 1.0 }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .disabled(abs(zoom - 1.0) < 0.01)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            Text(ancestryStatus.line)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(ancestryStatus.isProblem ? .orange : Theme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyGrant: some View {
        infoCard(
            title: "No folders granted yet",
            body: "This pane reads the same folders Unli Rice already scans for notes. "
                + "Add one under More → Setup and it will appear here.")
    }

    private var noRepos: some View {
        infoCard(
            title: "No git repositories found",
            body: "None of the granted folders contain a repository at their top level.")
    }

    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 12)
    }

    private func repoCard(_ s: GitRepoScanner.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(s.currentBranch ?? (s.detachedHead ? "detached HEAD" : "—"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(s.branches.count) \(Self.plural(s.branches.count, "branch", "branches")) "
                     + "· \(s.remoteBranchCount) remote")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            // The one claim refs alone can prove, stated exactly that narrowly.
            let unbacked = s.branchesNotOnAnyRemote
            if !unbacked.isEmpty {
                calloutRow(
                    "\(unbacked.count) branch \(Self.plural(unbacked.count, "tip", "tips")) on no remote",
                    detail: "Not on any remote this repo has fetched. Ahead/behind counts "
                          + "need a commit walk and are deliberately not shown.")
            }

            // The graph first — it answers "what is the shape of this repo" at a glance;
            // the list below answers "what exactly is each branch".
            BranchGraphView(snapshot: s,
                            ancestry: ancestry[s.name],
                            ancestryAge: ancestryAge,
                            ancestryStale: ancestryStale,
                            zoom: CGFloat(zoom))

            Divider().opacity(0.35)

            ForEach(s.branches) { b in
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(b.tipOnRemote ? Theme.textSecondary : Color.orange,
                                      lineWidth: 2)
                        .frame(width: 8, height: 8)
                    Text(b.name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(b.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    if b.isCurrent {
                        Text("HEAD")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(String(b.sha.prefix(7)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !s.worktrees.isEmpty {
                Divider().opacity(0.35)
                Text("WORKTREES")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(s.worktrees) { w in
                    HStack(spacing: 8) {
                        Text(w.name)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Text(w.branch ?? "detached")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if w.missing {
                            Text("MISSING")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                // The distinction that decides whether deleting a folder is safe.
                calloutRow(
                    "A worktree's commits are safe; its uncommitted files are not",
                    detail: "Commits live in this repo's shared object store, so removing a "
                          + "worktree folder cannot lose them. Anything uncommitted inside it "
                          + "exists in that folder and in no commit anywhere.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 12)
    }

    private func calloutRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    /// English pluralisation is irregular — "branch"/"branches" does not take the same
    /// suffix as "tip"/"tips", and appending "es" to "tip" produced "3 branch tipes" in
    /// the first build. Pass both forms rather than deriving one.
    private static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? one : many
    }

    // MARK: - Scanning

    /// Security-scoped roots must be opened before reading and closed after, in pairs —
    /// the same shape `AppStore+Ingest` uses for these very URLs.
    private func scan() async {
        let roots = store.scanRoots
        guard !roots.isEmpty else { snapshots = []; scanned = true; return }
        scanning = true
        defer { scanning = false; scanned = true }

        snapshots = await Task.detached(priority: .userInitiated) { () -> [GitRepoScanner.Snapshot] in
            let opened = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (url, ok) in opened where ok { url.stopAccessingSecurityScopedResource() } }

            let scanner = GitRepoScanner()
            var out: [GitRepoScanner.Snapshot] = []
            for (root, _) in opened {
                // A root may itself be a repository, or hold several.
                if let one = try? scanner.scan(repositoryAt: root) {
                    out.append(one)
                } else {
                    out.append(contentsOf: scanner.scanAll(in: root))
                }
            }
            return out
        }.value

        ancestry = loadAncestry()
    }

    /// Read the ancestry the script published, if any.
    ///
    /// The app does NOT write this file. It used to, and that was a bug in the making:
    /// the in-app scanner cannot compute ancestry — refs do not record it — so its
    /// snapshot would have overwritten the script's richer one with a poorer one every
    /// time the pane was opened. `check-repos.sh --json` is the sole producer; this is a
    /// pure reader, and the graph degrades to a flat fan when the file is absent.
    private func loadAncestry() -> [String: RepoSnapshotFile.Repo] {
        let folder = store.dataURL.deletingLastPathComponent()
        // Security-scoped access, in a start/stop pair. A sandboxed read of a
        // user-granted folder needs it, and the pair is a no-op on one that is not scoped.
        let needsStop = folder.startAccessingSecurityScopedResource()
        defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }

        let path = folder.path
        // Distinguish "not there" from "not allowed", which look identical from a `try?`.
        let fileURL = folder.appendingPathComponent(RepoSnapshotFile.filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            ancestryStatus = .missing(path: path)
            return [:]
        }
        if !FileManager.default.isReadableFile(atPath: fileURL.path) {
            ancestryStatus = .denied(path: path)
            return [:]
        }

        do {
            let file = try RepoSnapshotFile.read(fromFolder: folder)
            ancestryAge = file.generatedAt
            ancestryStale = file.isStale()
            ancestryStatus = .loaded(repos: file.repos.count,
                                     withAncestry: file.repos.filter(\.hasAncestry).count,
                                     path: path)
            return Dictionary(uniqueKeysWithValues: file.repos.map { ($0.name, $0) })
        } catch {
            ancestryStatus = .unreadable(
                path: path,
                reason: (error as? RepoSnapshotFile.ReadError)?.localizedDescription
                        ?? String(describing: error))
            return [:]
        }
    }
}
