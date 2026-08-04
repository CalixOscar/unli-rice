import Foundation

public struct ShardWriter: Sendable {
    public let shardFileURL: URL
    public let deviceLabel: String

    public init(shardFileURL: URL, deviceLabel: String = "iPhone") {
        self.shardFileURL = shardFileURL
        self.deviceLabel = deviceLabel
    }

    public func writeCapture(transcript: String, date: Date = Date()) throws -> Event {
        let noteID = UUID()
        let eventID = UUID()

        // HARD REQUIREMENT: title derived via ImporterText.sanitizeTitle(ImporterText.condense(transcript, limit: 60))
        let condensed = ImporterText.condense(transcript, limit: 60)
        let derivedTitle = ImporterText.sanitizeTitle(condensed)
        let finalTitle = derivedTitle.isEmpty ? "Voice note" : derivedTitle

        let event = Event(
            id: eventID,
            noteId: noteID,
            timestamp: date,
            source: "human",
            kind: .created,
            title: finalTitle,
            text: transcript,
            device: deviceLabel
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let fileManager = FileManager.default
        let directory = shardFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: shardFileURL.path) {
            fileManager.createFile(atPath: shardFileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: shardFileURL)
        defer { try? handle.close() }

        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data("\n".utf8))

        return event
    }
}
