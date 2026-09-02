import SwiftUI
import UnliRiceCore

/// The Mac's repositories, as a photograph.
///
/// **This phone has no repositories.** iOS gives an app no access to a Mac's filesystem,
/// so nothing here is scanned — the Mac publishes `repos.json` into the shared folder both
/// devices already use for notes, and this renders it. There is no refresh that reaches
/// the Mac, no action that changes anything, and no path in the file that could be acted
/// on even if there were.
///
/// Because it is a photograph, its **age is shown whenever it is not fresh**. A branch view
/// that looks live but is a day old teaches you not to trust it, which is worse than
/// showing nothing.
struct ReposSnapshotView: View {
    @ObservedObject var store: CaptureStore

    @State private var snapshot: RepoSnapshotFile?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ZStack {
            Theme.bgMain.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let snapshot {
                        freshness(snapshot)
                        ForEach(snapshot.repos, id: \.name) { repoCard($0) }
                    } else if let error {
                        infoCard("Nothing to show", error)
                    } else if loaded {
                        infoCard("No snapshot yet",
                                 "Open Repos on your Mac once — it publishes the list to the "
                                 + "same shared folder your notes use.")
                    } else {
                        ProgressView().padding(.vertical, 24)
                    }
                }
                .padding(18)
            }
        }
        .task { load() }
        .refreshable { load() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Repos")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Your Mac's branches, read-only. This phone has no repositories — it is "
                 + "showing what your Mac last published.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func freshness(_ s: RepoSnapshotFile) -> some View {
        let stale = s.isStale()
        return HStack(spacing: 6) {
            Circle()
                .fill(stale ? Color.orange : Color.secondary)
                .frame(width: 7, height: 7)
            Text("\(s.deviceLabel) · \(s.generatedAt.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(stale ? .orange : Theme.textSecondary)
            if s.totalBranchesNotOnAnyRemote > 0 {
                Spacer(minLength: 8)
                Text("\(s.totalBranchesNotOnAnyRemote) on no remote")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func infoCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(body).font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.bgField, in: RoundedRectangle(cornerRadius: 12))
    }

    private func repoCard(_ r: RepoSnapshotFile.Repo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.name).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(r.branches.count) \(r.branches.count == 1 ? "branch" : "branches")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(r.currentBranch ?? (r.detachedHead ? "detached HEAD" : "—"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)

            ForEach(r.branches, id: \.name) { b in
                HStack(spacing: 7) {
                    Circle()
                        .strokeBorder(b.tipOnRemote ? Color.secondary : Color.orange, lineWidth: 2)
                        .frame(width: 7, height: 7)
                    Text(b.name)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(b.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(b.sha.prefix(7)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !r.worktrees.isEmpty {
                Divider().opacity(0.3)
                ForEach(r.worktrees, id: \.name) { w in
                    HStack(spacing: 7) {
                        Text(w.name).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Text(w.branch ?? "detached")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textLight)
                        Spacer()
                        if w.missing {
                            Text("MISSING").font(.system(size: 9, weight: .semibold,
                                                         design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.bgField, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Loading

    private func load() {
        defer { loaded = true }
        guard let folder = store.sharedFolderURL else {
            error = "No shared folder is set up yet. Choose one in Settings — it is the same "
                  + "folder your notes sync through."
            return
        }
        let needsStop = folder.startAccessingSecurityScopedResource()
        defer { if needsStop { folder.stopAccessingSecurityScopedResource() } }

        do {
            snapshot = try RepoSnapshotFile.read(fromFolder: folder)
            error = nil
        } catch let e as RepoSnapshotFile.ReadError {
            // `.missing` is a normal state — the Mac simply has not published yet — so it
            // gets the friendly empty card rather than an error.
            snapshot = nil
            error = (e == .missing) ? nil : e.localizedDescription
        } catch {
            snapshot = nil
            self.error = "The repository snapshot could not be read."
        }
    }
}
