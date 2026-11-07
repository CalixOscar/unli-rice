import Foundation

public enum NativeOverviewGatherer {
    public struct Output {
        public let report: ProjectGarden.Report
        public let overview: StudioOverviewFile
        public let receivedCaptureIDs: [UUID]
    }
    public enum GatherError: Error, LocalizedError {
        case inaccessibleRoots
        public var errorDescription: String? { "Project folders could not be scanned; the previous overview was kept." }
    }
    public static func gather(roots: [URL], service: NoteService, corpusFolder: URL, identity: DeviceIdentity) throws -> Output {
        for root in roots {
            guard (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) != nil else {
                throw GatherError.inaccessibleRoots
            }
        }
        let snapshot = try service.projectionSnapshot(includeArchived: true)
        let notes = snapshot.notes.filter { !$0.archived }
        try Task.checkCancellation()
        let snapshotURL = corpusFolder.appendingPathComponent(RepoSnapshotFile.filename)
        var repoSnapshot: RepoSnapshotFile?
        var issues: [String] = snapshot.diagnostics.summary.map { [$0] } ?? []
        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            do { repoSnapshot = try RepoSnapshotFile.read(fromFolder: corpusFolder) }
            catch { issues.append("Saved repository details could not be read. Available notes and folders are shown. \(error.localizedDescription)") }
        }
        let loaded = ProjectGarden.load(roots: roots, notes: notes, publishedSnapshot: repoSnapshot)
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
            } else if let snapshot = repoSnapshot {
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
        let ids = snapshot.notes.filter { CaptureContext.isCapture($0) }.sorted { $0.updatedAt > $1.updatedAt }.prefix(2000).map(\.id)
        return Output(report: report, overview: overview, receivedCaptureIDs: ids)
    }
}
