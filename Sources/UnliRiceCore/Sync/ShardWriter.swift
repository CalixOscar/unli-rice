import Foundation

public struct ShardWriter: Sendable {
    public let shardFileURL: URL
    public let deviceLabel: String

    public init(shardFileURL: URL, deviceLabel: String = "iPhone") {
        self.shardFileURL = shardFileURL
        self.deviceLabel = deviceLabel
    }

    public func writeCapture(transcript: String, date: Date = Date(), tags: [String] = []) throws -> Event {
        let noteID = UUID()
        let eventID = UUID()

        // Titles must differ between captures, and not as a matter of taste:
        // `Janitor.duplicateProposals` scores note *titles* alone and proposes a
        // merge at >= 0.85 token overlap. A constant fallback scores 1.0 against
        // every other capture that used it, so a handful of failed
        // transcriptions would fill the review queue with proposals to merge
        // unrelated recordings. Empty titles are worse still — `Projector` turns
        // them into "Untitled", which then fights over `idsByTitle`.
        let condensed = ImporterText.condense(transcript, limit: 60)
        let derivedTitle = ImporterText.sanitizeTitle(condensed)
        let finalTitle = derivedTitle.isEmpty ? Self.timestampedFallbackTitle(for: date) : derivedTitle

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

        var eventsToWrite = [event]
        
        for tag in tags {
            eventsToWrite.append(Event(
                id: UUID(),
                noteId: noteID,
                timestamp: date.addingTimeInterval(0.001),
                source: "human",
                kind: .tagged,
                tag: tag,
                device: deviceLabel
            ))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let fileManager = FileManager.default
        let directory = shardFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: shardFileURL.path) {
            fileManager.createFile(atPath: shardFileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: shardFileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        for e in eventsToWrite {
            let data = try encoder.encode(e)
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data("\n".utf8))
        }

        return event
    }

    /// The title for a capture whose transcript came back empty — a silent
    /// recording, or a transcription that failed after the audio was saved.
    ///
    /// Second precision, not minute, so two captures in the same minute stay
    /// distinguishable to the janitor's title comparison.
    public static func timestampedFallbackTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "Voice note — \(formatter.string(from: date))"
    }
}
