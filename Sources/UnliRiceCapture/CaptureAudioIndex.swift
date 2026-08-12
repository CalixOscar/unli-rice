import Foundation

/// Maps a note back to the audio it was transcribed from.
///
/// The recording filename is `capture-<random UUID>.m4a` and shares nothing with
/// the note or event ID, so without this file the link between a note and its
/// audio exists only in the `SentCaptureItem` held in memory — it is gone the
/// moment the app is relaunched. That is why playback was not simply a button:
/// there was nothing to point it at.
///
/// Deliberately *not* an event in `events.jsonl`. The event log is immutable and
/// syncs to every device; audio is local, disposable, and pruned by
/// `AudioRetention`. Recording a path there would publish a filename that only
/// resolves on one phone, and would make deleting the file a lie the log keeps
/// telling. A sidecar can be rebuilt or lost without corrupting anything.
struct CaptureAudioIndex: Codable {
    /// Note ID → audio filename, relative to the Audio directory. Relative
    /// because the container path changes between installs.
    private(set) var filenamesByNoteID: [String: String]

    init(filenamesByNoteID: [String: String] = [:]) {
        self.filenamesByNoteID = filenamesByNoteID
    }

    static func url(inDirectory directory: URL) -> URL {
        directory.appendingPathComponent("capture-audio-index.json")
    }

    static func load(from url: URL) -> CaptureAudioIndex {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CaptureAudioIndex.self, from: data)
        else {
            return CaptureAudioIndex()
        }
        return decoded
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    mutating func record(noteID: UUID, filename: String) {
        filenamesByNoteID[noteID.uuidString] = filename
    }

    mutating func forget(noteID: UUID) {
        filenamesByNoteID.removeValue(forKey: noteID.uuidString)
    }

    func filename(for noteID: UUID) -> String? {
        filenamesByNoteID[noteID.uuidString]
    }

    /// Note IDs whose audio file no longer exists — pruned by retention, or
    /// removed by hand. The note survives; only the recording is gone.
    func noteIDsMissingAudio(inAudioDirectory audioDir: URL) -> [UUID] {
        filenamesByNoteID.compactMap { key, filename in
            guard let id = UUID(uuidString: key) else { return nil }
            let exists = FileManager.default.fileExists(
                atPath: audioDir.appendingPathComponent(filename).path
            )
            return exists ? nil : id
        }
    }
}
