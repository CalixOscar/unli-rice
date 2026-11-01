import Foundation

public enum StudioOverviewPublisher {
    private static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func issue(_ value: String) -> String {
        let pattern = #"(^|[\s:(])/(?!/)|file://"#
        if value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return "Some project folders could not be read on the Mac."
        }
        return String(value.prefix(500))
    }
    private static func evidence(_ light: BuildGate.Light) -> StudioOverviewFile.StageEvidence {
        switch light {
        case .done: return .init(state: "done")
        case .draft(let reason): return .init(state: "draft", reason: issue(reason))
        case .skipped(let reason): return .init(state: "skipped", reason: issue(reason))
        case .notRequired(let reason): return .init(state: "notRequired", reason: issue(reason))
        case .notRecorded: return .init(state: "notRecorded")
        case .missing: return .init(state: "missing")
        case .unknown(let reason): return .init(state: "unknown", reason: issue(reason))
        }
    }
    public static func make(report: ProjectGarden.Report, repositories: [RepoSnapshotFile.Repo],
                            gates: [String: BuildGate.Result], deviceLabel: String,
                            generatedAt: Date = Date()) -> StudioOverviewFile {
        let grouped = Dictionary(grouping: repositories, by: { key($0.name) })
        let validProjects = report.projects.filter { CaptureContext.isValidProject($0.name) }
        let projects = validProjects.map { project in
            let tag = key(project.name)
            let matches = grouped[tag] ?? []
            let gate = gates[tag]
            let stages = Dictionary(uniqueKeysWithValues: (gate?.lights ?? [:]).map { ($0.key.rawValue, evidence($0.value)) })
            return StudioOverviewFile.Project(id: tag, name: project.name, projectTag: tag,
                status: project.status, statusDate: project.statusDate, nextStep: project.nextStep,
                observedAt: project.repository?.observedAt ?? report.scannedAt,
                repository: matches.count == 1 ? matches[0] : nil, stages: stages,
                issues: (project.issues + (gate?.issues ?? [])).map(issue))
        }
        return StudioOverviewFile(generatedAt: generatedAt, deviceLabel: deviceLabel,
                                  projects: projects, issues: report.issues.map(issue) + (validProjects.count == report.projects.count ? [] : ["A project name conflicts with a reserved note tag; association unavailable."]))
    }
}
