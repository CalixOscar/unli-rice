import Foundation

/// Structured provenance already embedded in ingest-created note bodies.
///
/// Ingest owns the body format, so the GUI should not grow a second, slightly
/// different parser every time it wants to reveal the underlying file. The
/// most recent marker wins because revised imports append a new provenance
/// block while preserving the old one.
public struct NoteProvenance: Equatable, Sendable {
    public let rawFilename: String?
    public let sourceFilePath: String?
    public let projectPath: String?
    public let sessionID: String?

    public init(
        rawFilename: String? = nil,
        sourceFilePath: String? = nil,
        projectPath: String? = nil,
        sessionID: String? = nil
    ) {
        self.rawFilename = rawFilename
        self.sourceFilePath = sourceFilePath
        self.projectPath = projectPath
        self.sessionID = sessionID
    }

    public static func parse(_ body: String) -> NoteProvenance {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return NoteProvenance(
            rawFilename: lastBacktickedValue(label: "**Raw:**", in: lines),
            sourceFilePath: lastBacktickedValue(label: "**File:**", in: lines),
            projectPath: lastBacktickedValue(label: "**Project:**", in: lines),
            sessionID: lastBacktickedValue(label: "**Session:**", in: lines)
        )
    }

    public func rawURL(besideEventLog eventLogURL: URL) -> URL? {
        rawFilename.map {
            eventLogURL.deletingLastPathComponent()
                .appendingPathComponent("raw", isDirectory: true)
                .appendingPathComponent($0)
        }
    }

    private static func lastBacktickedValue(label: String, in lines: [String]) -> String? {
        for line in lines.reversed() where line.trimmingCharacters(in: .whitespaces).hasPrefix(label) {
            guard let first = line.firstIndex(of: "`") else { continue }
            let remainder = line[line.index(after: first)...]
            guard let second = remainder.firstIndex(of: "`") else { continue }
            let value = remainder[..<second].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
