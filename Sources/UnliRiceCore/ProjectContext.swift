import Foundation

public enum ProjectContext {
    public struct Preview: Codable, Sendable {
        public let id: UUID
        public let title: String
        public let preview: String
        public let updatedAt: Date
        fileprivate init(_ note: Note) {
            id = note.id; title = String(note.title.prefix(120))
            preview = String(note.body.prefix(300)); updatedAt = note.updatedAt
        }
    }
    public struct Entry: Codable, Sendable {
        public let name: String
        public let projectTag: String
        public let status: String?
        public let statusDate: Date?
        public let nextStep: String?
        public let observedAt: Date?
        public let repository: RepoSnapshotFile.Repo?
        public let remoteLiveChecked: Bool
        public let remoteEvidence: String
        public let pendingCaptures: [Preview]
        public let pendingCaptureCount: Int
        public let capturesTruncated: Bool
        public let todos: [Preview]
        public let todoCount: Int
        public let todosTruncated: Bool
    }
    public struct Report: Codable, Sendable {
        public let generatedAt: Date
        public let overviewGeneratedAt: Date?
        public let overviewStale: Bool?
        public let overviewIssue: String?
        public let totalProjectCount: Int
        public let offset: Int
        public let nextOffset: Int?
        public let projectsTruncated: Bool
        public let projects: [Entry]
        public let unassignedCaptures: [Preview]
        public let unassignedCaptureCount: Int
        public let unassignedTruncated: Bool
    }
    public static func build(notes: [Note], overview: StudioOverviewFile?, project: String? = nil, overviewIssue: String? = nil, offset: Int = 0) -> Report {
        let known = overview?.projects ?? []
        let requested = project.map { String(CaptureContext.normalizedProject($0).prefix(2000)) }
        let matched = requested.flatMap { key in known.first { CaptureContext.normalizedProject($0.projectTag) == key } }
        var issues = [overviewIssue].compactMap { $0 } + (overview?.issues ?? [])
        if overview == nil && issues.isEmpty { issues.append("Studio overview unavailable.") }
        if let requested, matched == nil {
            let missing = "Project \(requested) is not present in the studio overview."
            issues.append(missing)
        }
        let sorted = known.sorted {
            let a = CaptureContext.normalizedProject($0.name), b = CaptureContext.normalizedProject($1.name)
            return a == b ? $0.projectTag < $1.projectTag : a < b
        }
        func entry(name: String, tag: String, metadata: StudioOverviewFile.Project?) -> Entry {
            let captures = CaptureContext.pendingNotes(in: notes, project: tag)
            let key = CaptureContext.normalizedProject(tag)
            let todos = notes.filter { note in
                !note.archived && note.tags.contains("todo") && CaptureContext.isValidProject(key) &&
                note.tags.contains { CaptureContext.normalizedProject($0) == key }
            }.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            let evidence: String
            if let repo = metadata?.repository {
                evidence = repo.remoteBranchCount == 0 ? "No remote records available" : "Local tips compared with recorded remote refs; not live GitHub"
            } else { evidence = "Repository evidence unavailable" }
            return Entry(name: String(name.prefix(2000)), projectTag: String(key.prefix(2000)), status: metadata?.status,
                         statusDate: metadata?.statusDate, nextStep: metadata?.nextStep,
                         observedAt: metadata?.observedAt, repository: metadata?.repository,
                         remoteLiveChecked: false, remoteEvidence: evidence,
                         pendingCaptures: captures.prefix(10).map(Preview.init), pendingCaptureCount: captures.count,
                         capturesTruncated: captures.count > 10, todos: todos.prefix(10).map(Preview.init),
                         todoCount: todos.count, todosTruncated: todos.count > 10)
        }
        let pageOffset = project == nil ? max(0, offset) : 0
        let entries: [Entry]
        if let requested {
            entries = [entry(name: matched?.name ?? project ?? requested, tag: requested, metadata: matched)]
        } else {
            entries = sorted.dropFirst(pageOffset).prefix(20).map { entry(name: $0.name, tag: $0.projectTag, metadata: $0) }
        }
        let unassigned = CaptureContext.unassignedNotes(in: notes, knownProjects: known.map(\.projectTag))
        let total = requested == nil ? sorted.count : 1
        let hasMore = pageOffset < total && entries.count < total - pageOffset
        let next = hasMore ? pageOffset + entries.count : nil
        let issue = issues.isEmpty ? nil : String(issues.joined(separator: " ").prefix(2000))
        return Report(generatedAt: Date(), overviewGeneratedAt: overview?.generatedAt, overviewStale: overview.map { $0.isStale() }, overviewIssue: issue,
                      totalProjectCount: total, offset: pageOffset, nextOffset: next, projectsTruncated: hasMore, projects: entries,
                      unassignedCaptures: unassigned.prefix(10).map(Preview.init), unassignedCaptureCount: unassigned.count,
                      unassignedTruncated: unassigned.count > 10)
    }
}
