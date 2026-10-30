import Foundation

public enum GardenCrate {
    public enum State: Equatable, Sendable {
        case fine
        case needsYou
        case noStatus
        case cantRead(String)
    }

    public struct Sleeve: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let subtitle: String
        public let state: State
        public let lastActivity: Date?
        public let folderURL: URL?
        public let coverIndex: Int

        public init(id: String, name: String, subtitle: String, state: State,
                    lastActivity: Date?, folderURL: URL?, coverIndex: Int) {
            self.id = id
            self.name = name
            self.subtitle = subtitle
            self.state = state
            self.lastActivity = lastActivity
            self.folderURL = folderURL
            self.coverIndex = coverIndex
        }
    }

    public static func state(of project: ProjectGarden.Project) -> State {
        if let issue = project.issues.first { return .cantRead(issue) }
        if project.needsAttention { return .needsYou }
        if project.status == nil && project.repository == nil { return .noStatus }
        return .fine
    }

    public static func sleeves(from report: ProjectGarden.Report) -> [Sleeve] {
        report.projects.map { project in
            let activity = ([project.statusDate] + project.notes.map(\.updatedAt)).compactMap { $0 }.max()
            let subtitle = clippedFirstLine(project.nextStep ?? project.status ?? "No notes yet")
            return Sleeve(id: project.id, name: project.name, subtitle: subtitle,
                          state: state(of: project), lastActivity: activity,
                          folderURL: project.folderURL, coverIndex: stableIndex(project.id, modulo: 8))
        }.sorted { lhs, rhs in
            switch (lhs.lastActivity, rhs.lastActivity) {
            case let (left?, right?) where left != right:
                return left > right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                let names = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                return names == .orderedSame ? lhs.id < rhs.id : names == .orderedAscending
            }
        }
    }

    public static func stableIndex(_ id: String, modulo: Int) -> Int {
        precondition(modulo > 0, "modulo must be positive")
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash) % modulo
    }

    private static func clippedFirstLine(_ value: String) -> String {
        let firstLine = value.components(separatedBy: .newlines).first ?? value
        guard firstLine.count > 60 else { return firstLine }
        return String(firstLine.prefix(59)) + "…"
    }
}
