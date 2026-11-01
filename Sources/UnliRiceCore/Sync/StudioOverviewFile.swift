import Foundation

public struct StudioOverviewFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let filename = "studio-overview.json"
    private static let maximumBytes = 2 * 1024 * 1024
    private static let maximumProjects = 500

    public struct StageEvidence: Codable, Equatable, Sendable {
        public let state: String
        public let reason: String?
        public init(state: String, reason: String? = nil) { self.state = state; self.reason = reason }
    }

    public struct Project: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let projectTag: String
        public let status: String?
        public let statusDate: Date?
        public let nextStep: String?
        public let observedAt: Date
        public let repository: RepoSnapshotFile.Repo?
        public let stages: [String: StageEvidence]
        public let issues: [String]

        public init(id: String, name: String, projectTag: String, status: String? = nil,
                    statusDate: Date? = nil, nextStep: String? = nil, observedAt: Date,
                    repository: RepoSnapshotFile.Repo? = nil, stages: [String: StageEvidence] = [:],
                    issues: [String] = []) {
            self.id = id
            self.name = name
            self.projectTag = projectTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.status = status.map { String($0.prefix(2000)) }
            self.statusDate = statusDate
            self.nextStep = nextStep.map { String($0.prefix(2000)) }
            self.observedAt = observedAt
            self.repository = repository
            self.stages = stages
            self.issues = issues
        }
    }

    public let version: Int
    public let generatedAt: Date
    public let deviceLabel: String
    public let projects: [Project]
    public let issues: [String]

    public init(version: Int = currentVersion, generatedAt: Date = Date(), deviceLabel: String,
                projects: [Project], issues: [String] = []) {
        self.version = version
        self.generatedAt = generatedAt
        self.deviceLabel = deviceLabel
        let counts = Dictionary(grouping: projects, by: \.projectTag).mapValues(\.count)
        let duplicates = Set(counts.filter { $0.value > 1 }.keys)
        self.projects = projects.filter { !duplicates.contains($0.projectTag) }
        self.issues = issues + duplicates.sorted().map { "Duplicate project tag omitted: \($0)" }
    }

    public enum ReadError: Error, LocalizedError, Equatable {
        case missing, unreadable, oversized, tooManyProjects, unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .missing: return "No studio overview has been published yet."
            case .unreadable: return "The studio overview could not be read."
            case .oversized: return "The studio overview exceeds the 2 MB limit."
            case .tooManyProjects: return "The studio overview exceeds the 500 project limit."
            case .unsupportedVersion(let version): return "Unsupported studio overview version \(version)."
            }
        }
    }

    public func isStale(now: Date = Date(), tolerance: TimeInterval = 21600) -> Bool {
        now.timeIntervalSince(generatedAt) > tolerance
    }

    public func write(toFolder folder: URL) throws {
        guard version == Self.currentVersion else { throw ReadError.unsupportedVersion(version) }
        guard projects.count <= Self.maximumProjects else { throw ReadError.tooManyProjects }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ReadError.oversized }
        try data.write(to: folder.appendingPathComponent(Self.filename), options: .atomic)
    }

    public static func read(fromFolder folder: URL) throws -> Self {
        let url = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ReadError.missing }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        } catch { throw ReadError.unreadable }
        guard data.count <= maximumBytes else { throw ReadError.oversized }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int else { throw ReadError.unreadable }
        guard version == currentVersion else { throw ReadError.unsupportedVersion(version) }
        if let entries = object["projects"] as? [Any], entries.count > maximumProjects { throw ReadError.tooManyProjects }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(Self.self, from: data) else { throw ReadError.unreadable }
        let projects = decoded.projects.map { Project(id: $0.id, name: $0.name, projectTag: $0.projectTag,
            status: $0.status, statusDate: $0.statusDate, nextStep: $0.nextStep, observedAt: $0.observedAt,
            repository: $0.repository, stages: $0.stages, issues: $0.issues) }
        return Self(version: decoded.version, generatedAt: decoded.generatedAt, deviceLabel: decoded.deviceLabel,
                    projects: projects, issues: decoded.issues)
    }
}
