import Foundation

/// A bounded, read-only report of projects assembled from granted folders and notes.
/// This is deliberately an in-memory projection: it has no persisted representation.
public enum ProjectGarden {
    public struct Report: Sendable {
        public let projects: [Project]
        public let scannedAt: Date
        public let issues: [String]

        public init(projects: [Project], scannedAt: Date, issues: [String] = []) {
            self.projects = projects
            self.scannedAt = scannedAt
            self.issues = issues
        }
    }

    public struct Project: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let folderURL: URL?
        public let status: String?
        public let statusSource: String?
        public let statusDate: Date?
        public let nextStep: String?
        public let nextStepSource: String?
        public let notes: [Note]
        public let repository: Repository?
        public let issues: [String]

        public var todoCount: Int { notes.filter { $0.tags.contains(where: { $0.caseInsensitiveCompare("todo") == .orderedSame }) }.count }
        public var reviewCount: Int { notes.reduce(0) { $0 + $1.flags.filter { !$0.resolved }.count } }
        public var needsAttention: Bool { todoCount > 0 || reviewCount > 0 }

        public init(id: String, name: String, folderURL: URL? = nil, status: String? = nil,
                    statusSource: String? = nil, statusDate: Date? = nil, nextStep: String? = nil,
                    nextStepSource: String? = nil, notes: [Note] = [], repository: Repository? = nil,
                    issues: [String] = []) {
            self.id = id; self.name = name; self.folderURL = folderURL
            self.status = status; self.statusSource = statusSource; self.statusDate = statusDate
            self.nextStep = nextStep; self.nextStepSource = nextStepSource; self.notes = notes
            self.repository = repository; self.issues = issues
        }
    }

    public struct Repository: Sendable {
        public let currentBranch: String?
        public let branchCount: Int
        public let worktreeCount: Int
        public let differentTipCount: Int?
        public let observedAt: Date
        public let fromPublishedSnapshot: Bool

        public init(currentBranch: String?, branchCount: Int, worktreeCount: Int,
                    differentTipCount: Int?, observedAt: Date, fromPublishedSnapshot: Bool) {
            self.currentBranch = currentBranch; self.branchCount = branchCount
            self.worktreeCount = worktreeCount; self.differentTipCount = differentTipCount
            self.observedAt = observedAt; self.fromPublishedSnapshot = fromPublishedSnapshot
        }
    }

    private struct Candidate {
        let url: URL
        let name: String
        var issues: [String] = []
    }

    private struct Memory {
        let body: String
        let modifiedAt: Date?
        let status: String?
        let nextStep: String?
        let issue: String?
    }

    private static let maxMemoryBytes = 128 * 1024
    private static let maxDirectories = 2_000
    private static let maxProjects = 500
    private static let maxDepth = 4

    public static func load(roots: [URL], notes: [Note],
                            publishedSnapshot: RepoSnapshotFile? = nil,
                            now: Date = Date()) -> Report {
        var globalIssues: [String] = []
        let candidates = discover(roots: roots, issues: &globalIssues)
        let activeNotes = notes.filter { !$0.archived }
        let canonicalCandidates = candidates.sorted { canonical($0.url).path < canonical($1.url).path }
        let names = Dictionary(grouping: canonicalCandidates, by: { $0.name.lowercased() })
        var projects = canonicalCandidates.map { makeProject(candidate: $0, nameGroups: names, notes: activeNotes, now: now, issues: &globalIssues) }

        let registrations = activeNotes.compactMap { registration(from: $0) }
        for (name, _) in registrations {
            let matches = names[name.lowercased()] ?? []
            guard matches.count != 1 else { continue }
            if !projects.contains(where: { $0.id == "notes:\(name.lowercased())" }) {
                let selected = registrations.filter { $0.0.caseInsensitiveCompare(name) == .orderedSame }
                    .map { $0.1 }
                    .sorted { noteOrder($0, $1) }
                let related = activeNotes.filter { n in selected.contains(where: { $0.id == n.id }) || registration(from: n)?.0.caseInsensitiveCompare(name) == .orderedSame }
                projects.append(makeNotesOnly(name: name, notes: related, now: now))
            }
        }

        if let snapshot = publishedSnapshot {
            var seen: Set<String> = []
            for repo in snapshot.repos {
                let key = repo.name.lowercased()
                guard seen.insert(key).inserted else {
                    globalIssues.append("Published repository snapshot contains duplicate project name \(repo.name).")
                    continue
                }
                let matches = names[key] ?? []
                let repository = snapshotRepository(repo, observedAt: snapshot.generatedAt)
                if matches.count == 1, let match = matches.first,
                   let index = projects.firstIndex(where: { $0.id == projectID(for: match.url) }) {
                    if projects[index].repository == nil {
                        var updated = replacing(projects[index], repository: repository)
                        if updated.nextStep == nil, let snapshotStep = clipped(repo.nextStep, limit: 800),
                           let folder = updated.folderURL {
                            let memory = readMemory(in: folder)
                            if memory == nil || memory?.issue != nil {
                                updated = replacing(updated, nextStep: snapshotStep, nextStepSource: "published snapshot (saved snapshot)")
                            }
                        }
                        projects[index] = updated
                    }
                } else if matches.isEmpty && !projects.contains(where: { $0.name.caseInsensitiveCompare(repo.name) == .orderedSame && $0.folderURL == nil }) {
                    projects.append(Project(id: "snapshot:\(repo.name.lowercased())", name: repo.name,
                                            nextStep: clipped(repo.nextStep, limit: 800),
                                            nextStepSource: repo.nextStep == nil ? nil : "published snapshot",
                                            repository: repository))
                }
            }
        }

        projects = projects.map { sortNotes(in: $0) }.sorted {
            if $0.needsAttention != $1.needsAttention { return $0.needsAttention && !$1.needsAttention }
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }
        return Report(projects: projects, scannedAt: now, issues: unique(globalIssues))
    }

    private static func discover(roots: [URL], issues: inout [String]) -> [Candidate] {
        let fm = FileManager.default
        var result: [Candidate] = [], seen: Set<String> = [], visited = 0, truncated = false
        func walk(_ rawURL: URL, depth: Int) {
            if visited >= maxDirectories || result.count >= maxProjects { truncated = true; return }
            let url = canonical(rawURL)
            let key = url.path
            guard seen.insert(key).inserted else { return }
            visited += 1
            if fm.fileExists(atPath: url.appendingPathComponent(LocalFileImporter.ignoreMarkerFilename).path) { return }
            let isProject = [".git", "memory.md", "PROJECT_NOTES.md"].contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
            if isProject {
                result.append(Candidate(url: url, name: url.lastPathComponent))
                return
            }
            guard depth < maxDepth, let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return }
            for entry in entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
                if isSkippableDirectory(entry) { continue }
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                walk(entry, depth: depth + 1)
                if truncated { return }
            }
        }
        for root in roots { walk(root, depth: 0); if truncated { break } }
        if truncated { issues.append("Project discovery was bounded; some folders were not scanned.") }
        return result
    }

    private static func makeProject(candidate: Candidate, nameGroups: [String: [Candidate]], notes: [Note], now: Date, issues: inout [String]) -> Project {
        let folder = candidate.url
        var projectIssues = candidate.issues
        let memory = readMemory(in: folder)
        if let issue = memory?.issue { projectIssues.append(issue) }
        let related = relatedNotes(notes, for: candidate, nameGroups: nameGroups)
        let registration = related.first(where: { registration(from: $0) != nil })
        let status: String?
        let statusSource: String?
        let statusDate: Date?
        let nextStep: String?
        let nextSource: String?
        if let memory, memory.issue == nil {
            if let memoryStatus = memory.status {
                status = clipped(memoryStatus, limit: 400); statusSource = "memory.md (file updated)"; statusDate = memory.modifiedAt
            } else {
                let source = related.sorted(by: noteOrder).first
                status = source.flatMap { clipped(excerpt(from: latestBlock($0.body), limit: 400), limit: 400) }
                statusSource = source.map { "note: \($0.title) (note updated)" }; statusDate = source?.updatedAt
            }
            nextStep = clipped(memory.nextStep, limit: 800); nextSource = memory.nextStep == nil ? nil : "memory.md (file updated)"
        } else {
            let source = registration ?? related.sorted(by: noteOrder).first
            status = source.flatMap { excerpt(from: latestBlock($0.body), limit: 400) }
            statusSource = source.map { "note: \($0.title) (note updated)" }; statusDate = source?.updatedAt
            let noteStep = source.flatMap { field("**Next step:**", in: latestBlock($0.body)) }
            nextStep = clipped(noteStep, limit: 800); nextSource = noteStep == nil ? nil : source.map { "note: \($0.title) (note updated)" }
        }
        let repo: Repository?
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
            do {
                let scan = try GitRepoScanner().scan(repositoryAt: folder)
                repo = Repository(currentBranch: scan.currentBranch, branchCount: scan.branches.count,
                                  worktreeCount: scan.worktrees.count,
                                  differentTipCount: scan.remoteBranchCount == 0 ? nil : scan.branchesNotOnAnyRemote.count,
                                  observedAt: now, fromPublishedSnapshot: false)
            } catch { projectIssues.append("Repository facts are unavailable for \(candidate.name)." ); repo = nil }
        } else { repo = nil }
        let project = Project(id: projectID(for: folder), name: candidate.name, folderURL: folder,
                              status: status, statusSource: statusSource, statusDate: statusDate,
                              nextStep: nextStep, nextStepSource: nextSource, notes: related,
                              repository: repo, issues: projectIssues)
        return project
    }

    private static func makeNotesOnly(name: String, notes: [Note], now: Date) -> Project {
        let ordered = notes.sorted(by: noteOrder), source = ordered.first
        let step = source.flatMap { field("**Next step:**", in: latestBlock($0.body)) }
        return Project(id: "notes:\(name.lowercased())", name: name,
                       status: source.flatMap { clipped(excerpt(from: latestBlock($0.body), limit: 400), limit: 400) },
                       statusSource: source.map { "note: \($0.title) (note updated)" }, statusDate: source?.updatedAt,
                       nextStep: clipped(step, limit: 800), nextStepSource: step == nil ? nil : source.map { "note: \($0.title) (note updated)" }, notes: ordered)
    }

    private static func relatedNotes(_ notes: [Note], for candidate: Candidate, nameGroups: [String: [Candidate]]) -> [Note] {
        let path = canonical(candidate.url).path
        return notes.filter { note in
            let provenance = NoteProvenance.parse(note.body)
            let paths = [provenance.projectPath, provenance.sourceFilePath].compactMap { $0 }.map { canonical(URL(fileURLWithPath: $0)).path }
            if paths.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return true }
            // Any explicit provenance is authoritative, even when it points outside
            // this candidate. A conflicting tag must not pull the note into a
            // different project merely because the path was unavailable or stale.
            if !paths.isEmpty { return false }
            guard nameGroups[candidate.name.lowercased()]?.count == 1 else { return false }
            if let registered = registration(from: note), registered.0.caseInsensitiveCompare(candidate.name) == .orderedSame { return true }
            return note.tags.contains { $0.caseInsensitiveCompare(candidate.name) == .orderedSame }
        }
    }

    private static func readMemory(in folder: URL) -> Memory? {
        let url = folder.appendingPathComponent("memory.md"), fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return Memory(body: "", modifiedAt: nil, status: nil, nextStep: nil, issue: "memory.md is a symlink and was not read.")
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let data = try handle.read(upToCount: maxMemoryBytes + 1) ?? Data()
            try handle.close()
            guard data.count <= maxMemoryBytes else { return Memory(body: "", modifiedAt: nil, status: nil, nextStep: nil, issue: "memory.md is too large to read safely.") }
            guard let body = String(data: data, encoding: .utf8) else { return Memory(body: "", modifiedAt: nil, status: nil, nextStep: nil, issue: "memory.md could not be read.") }
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return Memory(body: body, modifiedAt: date ?? nil, status: field("**Status:**", in: body), nextStep: StudioTodo.nextStep(fromMemory: body), issue: nil)
        } catch { return Memory(body: "", modifiedAt: nil, status: nil, nextStep: nil, issue: "memory.md could not be read.") }
    }

    private static func snapshotRepository(_ repo: RepoSnapshotFile.Repo, observedAt: Date) -> Repository {
        Repository(currentBranch: repo.currentBranch, branchCount: repo.branches.count,
                    worktreeCount: repo.worktrees.count, differentTipCount: repo.remoteBranchCount == 0 ? nil : repo.branchesNotOnAnyRemote.count,
                    observedAt: observedAt, fromPublishedSnapshot: true)
    }

    private static func replacing(_ project: Project, repository: Repository) -> Project {
        Project(id: project.id, name: project.name, folderURL: project.folderURL, status: project.status,
                statusSource: project.statusSource, statusDate: project.statusDate, nextStep: project.nextStep,
                nextStepSource: project.nextStepSource, notes: project.notes, repository: repository, issues: project.issues)
    }

    private static func replacing(_ project: Project, nextStep: String?, nextStepSource: String?) -> Project {
        Project(id: project.id, name: project.name, folderURL: project.folderURL, status: project.status,
                statusSource: project.statusSource, statusDate: project.statusDate, nextStep: nextStep,
                nextStepSource: nextStepSource, notes: project.notes, repository: project.repository, issues: project.issues)
    }

    private static func registration(from note: Note) -> (String, Note)? {
        guard note.title.count > 9, note.title.lowercased().hasPrefix("project:") else { return nil }
        let name = String(note.title.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : (name, note)
    }

    private static func latestBlock(_ body: String) -> String { body.components(separatedBy: "\n\n---\n").last ?? body }

    private static func field(_ label: String, in body: String) -> String? {
        guard let range = body.range(of: label) else { return nil }
        var values: [String] = []
        for line in body[range.upperBound...].split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("**") && trimmed.contains(":**") { break }
            if trimmed.isEmpty && !values.isEmpty { break }
            if !trimmed.isEmpty { values.append(trimmed) }
        }
        let value = values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func excerpt(from body: String, limit: Int) -> String? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var prose: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { if !prose.isEmpty { break }; continue }
            if t.hasPrefix("#") || t.hasPrefix("**") || t.hasPrefix("[") { continue }
            prose.append(t)
        }
        return prose.isEmpty ? nil : prose.joined(separator: " ")
    }

    private static func clipped(_ value: String?, limit: Int) -> String? {
        guard let value, value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }

    private static func canonical(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }
    private static func projectID(for url: URL) -> String { "folder:\(canonical(url).path)" }
    private static func noteOrder(_ a: Note, _ b: Note) -> Bool { a.updatedAt == b.updatedAt ? a.id.uuidString < b.id.uuidString : a.updatedAt > b.updatedAt }
    private static func sortNotes(in project: Project) -> Project { replacingNotes(project, notes: project.notes.sorted(by: noteOrder)) }
    private static func replacingNotes(_ p: Project, notes: [Note]) -> Project { Project(id: p.id, name: p.name, folderURL: p.folderURL, status: p.status, statusSource: p.statusSource, statusDate: p.statusDate, nextStep: p.nextStep, nextStepSource: p.nextStepSource, notes: notes, repository: p.repository, issues: p.issues) }
    private static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
    private static func isSkippableDirectory(_ url: URL) -> Bool { LocalFileImporter.skippedDirectories.contains(url.lastPathComponent) || url.lastPathComponent.hasPrefix(".") }
}
