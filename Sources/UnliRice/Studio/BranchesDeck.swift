import SwiftUI
import UnliRiceCore

struct BranchesDeck: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var allRepos: [(index: Int, name: String, branches: Int)] = []
    @State private var snapshot: GitRepoScanner.Snapshot?
    @State private var ancestry: RepoSnapshotFile.Repo?
    @State private var ancestryAge: Date?
    @State private var ancestryStale = false

    var body: some View {
        Group {
            if store.studioScope == .all {
                if allRepos.isEmpty {
                    Text("No git repositories in your projects")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(allRepos.count) repos")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(allRepos, id: \.index) { repo in
                                    Button {
                                        if repo.index != store.studioFrontIndex { FlipSound.play() }
                                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.78)) {
                                            store.studioFrontIndex = repo.index
                                            store.studioScope = .project
                                        }
                                    } label: {
                                        HStack {
                                            Text(repo.name).font(.system(size: 13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                            Spacer()
                                            Text("\(repo.branches) branches").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 320)
                    }
                }
            } else if let folder = store.studioFrontSleeve?.folderURL {
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
        .task(id: LoadKey(scope: store.studioScope, folderURL: store.studioFrontSleeve?.folderURL,
                          sleeveIDs: store.studioSleeves.map(\.id))) {
            await load()
        }
    }

    private func load() async {
        if store.studioScope == .all {
            let sleeves = store.studioSleeves
            let roots = store.scanRoots
            let repos = await Task.detached(priority: .userInitiated) {
                let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
                defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
                return sleeves.enumerated().compactMap { index, sleeve -> (index: Int, name: String, branches: Int)? in
                    guard let folder = sleeve.folderURL,
                          let found = try? GitRepoScanner().scan(repositoryAt: folder) else { return nil }
                    return (index, sleeve.name, found.branches.count)
                }
            }.value
            guard !Task.isCancelled else { return }
            allRepos = repos
            return
        }
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

private struct LoadKey: Equatable {
    let scope: StudioScope
    let folderURL: URL?
    let sleeveIDs: [String]
}
