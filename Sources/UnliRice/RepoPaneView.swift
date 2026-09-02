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
                            ancestryStale: ancestryStale)

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
        guard let file = try? RepoSnapshotFile.read(fromFolder: folder) else { return [:] }
        ancestryAge = file.generatedAt
        ancestryStale = file.isStale()
        return Dictionary(uniqueKeysWithValues: file.repos.map { ($0.name, $0) })
    }
}
