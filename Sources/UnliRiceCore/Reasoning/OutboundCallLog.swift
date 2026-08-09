import Darwin
import Foundation

/// One record of something leaving this machine.
///
/// The Trust Center already exists to answer "is this actually doing what it
/// says"; "what left this machine" is the same question, so it gets the same
/// treatment as `MCPConnectionActivity`: **metadata only, never note contents.**
/// Host, time, model, how many notes, how many tokens, what happened. Not a
/// title, not a body, not a tag, not a flag reason — not even in `detail`, which
/// carries fixed strings and counts and nothing a user wrote.
///
/// Deliberately not part of `events.jsonl`: this is operational status, not
/// user memory, and can be discarded without losing a note.
public struct OutboundCall: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// The provider answered and the answer was dispatched.
        case succeeded
        /// Nothing was sent: a cap would have been exceeded, or there was
        /// nothing new to judge. Recorded anyway — "we chose not to call" is
        /// evidence too.
        case notSent
        /// Sent, but the provider errored or answered unusably.
        case failed
        /// A dry run. Shows exactly what *would* have gone, and nothing did.
        case dryRun
    }

    public let id: UUID
    public let host: String
    public let model: String
    public let at: Date
    /// How many notes' titles and bodies were included in the request.
    public let noteCount: Int
    /// Characters ÷ 4 at request time — an estimate, and labelled one.
    public let estimatedTokens: Int
    /// What the provider said it actually charged, when it says. Nil otherwise.
    public let reportedTokens: Int?
    public let outcome: Outcome
    /// A short fixed phrase. Must never contain anything a user wrote.
    public let detail: String?

    public init(
        id: UUID = UUID(),
        host: String,
        model: String,
        at: Date = Date(),
        noteCount: Int,
        estimatedTokens: Int,
        reportedTokens: Int? = nil,
        outcome: Outcome,
        detail: String? = nil
    ) {
        self.id = id
        self.host = host
        self.model = model
        self.at = at
        self.noteCount = noteCount
        self.estimatedTokens = estimatedTokens
        self.reportedTokens = reportedTokens
        self.outcome = outcome
        self.detail = detail
    }

    /// The line the Trust Center shows. Counts and outcomes only.
    public var line: String {
        let tokens = reportedTokens.map { "\($0) tokens" } ?? "~\(estimatedTokens) tokens (est.)"
        return "\(model) · \(noteCount) note\(noteCount == 1 ? "" : "s") · \(tokens) · \(outcome.rawValue)"
    }
}

/// Append-and-cap store beside the event log, same file-locking shape as
/// `MCPConnectionActivityStore` so two processes reading the same vault can't
/// tear the file.
public final class OutboundCallLog: @unchecked Sendable {
    public enum StoreError: Error, LocalizedError {
        case unavailable
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .unavailable: return "The outbound-call log could not be saved."
            case .unreadable: return "The outbound-call log could not be read."
            }
        }
    }

    private struct Envelope: Codable {
        let version: Int
        var calls: [OutboundCall]
    }

    public static let filename = "outbound-calls.json"
    public static let currentVersion = 1
    /// Enough to see a pattern, not so much the file grows without bound.
    public static let retained = 200

    public let fileURL: URL
    private let lockURL: URL
    private let queue = DispatchQueue(label: "com.unlirice.outbound-calls")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.lockURL = fileURL.deletingLastPathComponent().appendingPathComponent("outbound-calls.lock")
    }

    public convenience init(besideEventLog eventLogURL: URL) {
        self.init(fileURL: eventLogURL.deletingLastPathComponent().appendingPathComponent(Self.filename))
    }

    /// Newest first.
    public func list() throws -> [OutboundCall] {
        try queue.sync {
            try withLock(LOCK_SH) { try load().sorted { $0.at > $1.at } }
        }
    }

    @discardableResult
    public func record(_ call: OutboundCall) throws -> OutboundCall {
        try queue.sync {
            try withLock(LOCK_EX) {
                var calls = try load()
                calls.append(call)
                calls = Array(calls.sorted { $0.at > $1.at }.prefix(Self.retained))
                try save(calls)
                return call
            }
        }
    }

    private func load() throws -> [OutboundCall] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { throw StoreError.unavailable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion
        else { throw StoreError.unreadable }
        return envelope.calls
    }

    private func save(_ calls: [OutboundCall]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Envelope(version: Self.currentVersion, calls: calls)) else {
            throw StoreError.unavailable
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func withLock<T>(_ operation: Int32, body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0, flock(fd, operation) == 0 else {
            if fd >= 0 { close(fd) }
            throw StoreError.unavailable
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try body()
    }
}
