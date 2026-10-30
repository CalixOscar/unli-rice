import Foundation
import UnliRiceCore

enum StudioGardenState: Equatable {
    case loading
    case loaded
    case failed(String)
}

extension AppStore {
    var studioFrontSleeve: GardenCrate.Sleeve? {
        guard studioSleeves.indices.contains(studioFrontIndex) else { return nil }
        return studioSleeves[studioFrontIndex]
    }

    func refreshStudioGarden() async {
        studioGardenState = .loading
        let roots = scanRoots
        let corpusFolder = dataURL.deletingLastPathComponent()
        let service = service

        do {
            let worker = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let corpusAccess = corpusFolder.startAccessingSecurityScopedResource()
                defer { if corpusAccess { corpusFolder.stopAccessingSecurityScopedResource() } }
                let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
                defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
                let notes = try service.listNotes(includeArchived: false)
                try Task.checkCancellation()
                let snapshotURL = corpusFolder.appendingPathComponent(RepoSnapshotFile.filename)
                var snapshot: RepoSnapshotFile?
                var issues: [String] = []
                if FileManager.default.fileExists(atPath: snapshotURL.path) {
                    do { snapshot = try RepoSnapshotFile.read(fromFolder: corpusFolder) }
                    catch { issues.append("Saved repository details could not be read. Available notes and folders are shown. \(error.localizedDescription)") }
                }
                let loaded = ProjectGarden.load(roots: roots, notes: notes, publishedSnapshot: snapshot)
                try Task.checkCancellation()
                return ProjectGarden.Report(projects: loaded.projects, scannedAt: loaded.scannedAt,
                                            issues: loaded.issues + issues)
            }
            let report = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            studioSleeves = GardenCrate.sleeves(from: report)
            studioFrontIndex = min(studioFrontIndex, max(studioSleeves.count - 1, 0))
            studioGardenState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            studioGardenState = .failed(error.localizedDescription)
        }
    }

    func refreshStudioGate() async {
        guard let folder = studioFrontSleeve?.folderURL else {
            studioFrontGate = nil
            return
        }
        let roots = scanRoots
        let result = await Task.detached(priority: .userInitiated) {
            let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
            return BuildGate.current(folder: folder)
        }.value
        guard !Task.isCancelled else { return }
        studioFrontGate = result
    }
}
