import AppKit
import Foundation
import UnliRiceCore

enum StudioScope: Equatable { case project, all }
struct StudioGateKey: Equatable { let sleeveID: String?; let refresh: Int }

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
        _ = runShardImportIfNeeded()
        let roots = scanRoots
        let corpusFolder = dataURL.deletingLastPathComponent()
        let service = service
        let identity = DeviceIdentity.current(inDirectory: corpusFolder)
        let exportFolder = exportFolderURL

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
                var report = ProjectGarden.Report(projects: loaded.projects, scannedAt: loaded.scannedAt,
                                                  issues: loaded.issues + issues)
                var repos: [RepoSnapshotFile.Repo] = []
                var gates: [String: BuildGate.Result] = [:]
                let groups = Dictionary(grouping: report.projects, by: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                var adjustedProjects: [ProjectGarden.Project] = []
                for project in report.projects {
                    let key = project.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard groups[key]?.count == 1 else { adjustedProjects.append(project); continue }
                    if let folder = project.folderURL { gates[key] = BuildGate.current(folder: folder) }
                    var adjusted = project
                    if project.repository?.fromPublishedSnapshot == false, let folder = project.folderURL,
                       let scan = try? GitRepoScanner().scan(repositoryAt: folder) {
                        repos.append(contentsOf: RepoSnapshotFile(scans: [scan], deviceLabel: identity.label).repos)
                    } else if let snapshot {
                        let matches = snapshot.repos.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
                        if matches.count == 1 {
                            let repo = matches[0]
                            repos.append(repo)
                            let evidence = ProjectGarden.Repository(currentBranch: repo.currentBranch, branchCount: repo.branches.count,
                                worktreeCount: repo.worktrees.count, differentTipCount: repo.remoteBranchCount == 0 ? nil : repo.branchesNotOnAnyRemote.count,
                                observedAt: snapshot.generatedAt, fromPublishedSnapshot: true)
                            adjusted = ProjectGarden.Project(id: project.id, name: project.name, folderURL: project.folderURL,
                                status: project.status, statusSource: project.statusSource, statusDate: project.statusDate,
                                nextStep: project.nextStep, nextStepSource: project.nextStepSource, notes: project.notes,
                                repository: evidence, issues: project.issues)
                        }
                    }
                    adjustedProjects.append(adjusted)
                }
                report = ProjectGarden.Report(projects: adjustedProjects, scannedAt: report.scannedAt, issues: report.issues)
                let overview = StudioOverviewPublisher.make(report: report, repositories: repos, gates: gates, deviceLabel: identity.label)
                let allNotes = try service.listNotes(includeArchived: true)
                let ids = allNotes.filter { CaptureContext.isCapture($0) }.sorted { $0.updatedAt > $1.updatedAt }.prefix(2000).map(\.id)
                return (report, overview, ids)
            }
            let (report, overview, ids) = try await withTaskCancellationHandler(operation: {
                try await worker.value
            }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            var failures: [String] = []
            let corpusAccess = corpusFolder.startAccessingSecurityScopedResource()
            do { try overview.write(toFolder: corpusFolder) } catch { failures.append("local overview: \(error.localizedDescription)") }
            if corpusAccess { corpusFolder.stopAccessingSecurityScopedResource() }
            if let exportFolder {
                let scoped = exportFolder.startAccessingSecurityScopedResource()
                do { try overview.write(toFolder: exportFolder) } catch { failures.append("shared overview: \(error.localizedDescription)") }
                do {
                    try CaptureReceiptFile(deviceLabel: identity.label, receivedNoteIDs: ids).write(toFolder: exportFolder, deviceID: identity.id)
                } catch { failures.append("capture receipt: \(error.localizedDescription)") }
                if scoped { exportFolder.stopAccessingSecurityScopedResource() }
            }
            if !failures.isEmpty { statusMessage = "Studio sync needs retry: " + failures.joined(separator: "; ") }
            studioSleeves = GardenCrate.sleeves(from: report)
            studioFrontIndex = min(studioFrontIndex, max(studioSleeves.count - 1, 0))
            studioGardenState = .loaded
            studioRefreshCount &+= 1
            await loadStudioIcons()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            studioGardenState = .failed(error.localizedDescription)
        }
    }

    func loadStudioIcons() async {
        let projects = studioSleeves.compactMap { sleeve in
            sleeve.folderURL.map { (sleeve.id, $0) }
        }
        let roots = scanRoots
        let worker = Task.detached(priority: .utility) {
            let openedRoots = roots.map { ($0, $0.startAccessingSecurityScopedResource()) }
            defer { for (root, opened) in openedRoots where opened { root.stopAccessingSecurityScopedResource() } }
            var icons: [String: Data] = [:]
            for (id, folder) in projects {
                guard !Task.isCancelled else { break }
                if let url = ProjectIcon.find(in: folder),
                   (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 <= 5_000_000 }) == true,
                   let data = try? Data(contentsOf: url), data.count <= 5_000_000 {
                    icons[id] = data
                }
            }
            return icons
        }
        let data = await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: { worker.cancel() })
        guard !Task.isCancelled else { return }
        var icons: [String: NSImage] = [:]
        for (id, imageData) in data {
            if let image = NSImage(data: imageData), image.isValid { icons[id] = image }
        }
        studioIcons = icons
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
