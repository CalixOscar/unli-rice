import Foundation

/// Which notes this vault has already paid a model to look at.
///
/// The single biggest lever on cost after "never send the corpus" is never
/// sending the *same* note twice. A note that hasn't changed since the model
/// last read it will produce the same judgement, so re-sending it buys nothing
/// and costs the user money.
///
/// Copies `SyncState`'s pattern — a plain Codable cursor saved beside the event
/// log, so progress moves with the vault data rather than with this Mac — with
/// one deliberate difference: it records a **fingerprint of what was judged**,
/// not the `updatedAt` it was judged at.
///
/// Timestamps were the obvious first choice and are wrong here. Event
/// timestamps round-trip through the log as whole seconds, so a note edited in
/// the same second as a run is indistinguishable from one that wasn't touched,
/// and would silently never be looked at again. A fingerprint answers the
/// question actually being asked — "is this the same text the model already
/// read?" — at any clock resolution.
public struct ReasoningCursor: Codable, Equatable, Sendable {
    /// Note id → fingerprint of the content that was judged. Keyed by string
    /// because JSON dictionary keys are strings and this file is meant to be
    /// readable by anyone who wants to check it.
    public var judged: [String: String]
    public var lastRunAt: Date?

    public init(judged: [String: String] = [:], lastRunAt: Date? = nil) {
        self.judged = judged
        self.lastRunAt = lastRunAt
    }

    /// True when this note is new, or its title, body, or tags have changed
    /// since it was last judged.
    ///
    /// Tags count because they are part of what the model is shown and part of
    /// what it is asked about — a note that has since been tagged is a different
    /// question from the one already answered.
    public func needsJudgement(_ note: Note) -> Bool {
        judged[note.id.uuidString] != Self.fingerprint(note)
    }

    /// Marks these notes as judged, at the content they had when sent.
    ///
    /// Called only after a provider actually answered. A failed call must not
    /// advance the cursor — otherwise a network blip silently means those notes
    /// are never looked at.
    public mutating func record(_ notes: [Note], at date: Date = Date()) {
        for note in notes { judged[note.id.uuidString] = Self.fingerprint(note) }
        lastRunAt = date
    }

    /// FNV-1a over exactly what `ReasoningRun.digest(for:)` sends.
    ///
    /// Not a cryptographic hash and not trying to be: nothing security-relevant
    /// rests on it, and a collision costs one skipped re-judgement. Hand-rolled
    /// because Swift's own `hashValue` is seeded per process and would make
    /// every note look changed on every launch.
    static func fingerprint(_ note: Note) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array("\(note.title)\u{0}\(note.body)\u{0}\(note.tags.sorted().joined(separator: ","))".utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Persistence

    public static func url(besideEventLog eventLog: URL) -> URL {
        eventLog.deletingLastPathComponent().appendingPathComponent("reasoning-cursor.json")
    }

    public static func load(from url: URL) -> ReasoningCursor {
        guard let data = try? Data(contentsOf: url) else { return ReasoningCursor() }
        return (try? JSONDecoder().decode(ReasoningCursor.self, from: data)) ?? ReasoningCursor()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
