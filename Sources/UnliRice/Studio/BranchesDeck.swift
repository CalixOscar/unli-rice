import SwiftUI
import UnliRiceCore

struct BranchesDeck: View {
    @EnvironmentObject var store: AppStore
    @State private var snapshot: GitRepoScanner.Snapshot?
    @State private var ancestry: RepoSnapshotFile.Repo?
    @State private var ancestryAge: Date?
    @State private var ancestryStale = false

    var body: some View {
        Group {
            if let folder = store.studioFrontSleeve?.folderURL {
                if let snapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(snapshot.branches.count) branches")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        ScrollView(.vertical) {
                            BranchGraphView(snapshot: snapshot, ancestry: ancestry,
                                            ancestryAge: ancestryAge, ancestryStale: ancestryStale)
                        }
                        .frame(height: 320)
                    }
                } else {
                    Text("No git repository in \(folder.lastPathComponent)")
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pick a folder with a project in it")
                        .foregroundStyle(Theme.textSecondary)
                    Button("Pick a folder") { store.chooseScanRoot() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: store.studioFrontSleeve?.folderURL) {
            await load()
        }
    }

    private func load() async {
        guard let folder = store.studioFrontSleeve?.folderURL else {
            snapshot = nil; ancestry = nil; return
        }
        let roots = store.scanRoots
        let corpusFolder = store.dataURL.deletingLastPathComponent()
        let loaded = await Task.detached(priority: .userInitiated) {
            let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
            let found = try? GitRepoScanner().scan(repositoryAt: folder)
            let corpusAccess = corpusFolder.startAccessingSecurityScopedResource()
            defer { if corpusAccess { corpusFolder.stopAccessingSecurityScopedResource() } }
            let file = try? RepoSnapshotFile.read(fromFolder: corpusFolder)
            let repo = found.flatMap { foundSnapshot in
                file?.repos.first { $0.name == foundSnapshot.name }
            }
            return (found, repo, file?.generatedAt, file?.isStale() ?? false)
        }.value
        guard !Task.isCancelled else { return }
        snapshot = loaded.0
        ancestry = loaded.1
        ancestryAge = loaded.2
        ancestryStale = loaded.3
    }
}
