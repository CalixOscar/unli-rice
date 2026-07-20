import CryptoKit
import Foundation

/// One file that has been taken into `/raw`.
///
/// The digest is the identity. Two resources with the same bytes are the same
/// resource no matter where they came from or what they were called, which is
/// what stops a re-scan of the same folder from filling the corpus with copies.
public struct RawResource: Sendable, Equatable, Identifiable {
    /// Lowercase hex SHA-256 of the file's bytes.
    public let digest: String
    /// The name the file has *inside* `/raw` — digest-prefixed so two unrelated
    /// files called `notes.md` can coexist without either shadowing the other.
    public let storedName: String
    /// What it was called where it came from. Kept because it's often the only
    /// human-meaningful thing about a file, and the digest is not.
    public let originalName: String
    public let byteCount: Int

    public var id: String { digest }

    public init(digest: String, storedName: String, originalName: String, byteCount: Int) {
        self.digest = digest
        self.storedName = storedName
        self.originalName = originalName
        self.byteCount = byteCount
    }
}

public enum RawStoreError: Error, CustomStringConvertible {
    case notAFile(URL)
    case tooLarge(URL, bytes: Int, limit: Int)

    public var description: String {
        switch self {
        case .notAFile(let url):
            return "Not a readable file: \(url.path)"
        case .tooLarge(let url, let bytes, let limit):
            return "\(url.lastPathComponent) is \(bytes) bytes, over the \(limit)-byte ingest limit"
        }
    }
}

/// The `/raw` half of the knowledge base: every resource the system has ingested,
/// kept verbatim, addressed by content.
///
/// The notes are the `/wiki` half — an index that says what exists and where to
/// look, so an agent can find the one resource it needs without reading all of
/// them. That split is the whole point; a note is a pointer plus a summary, and
/// this is where the thing itself actually lives.
///
/// Two rules here are not negotiable, and both are the same rule the rest of
/// this codebase follows (decision #2 in PROJECT_NOTES.md — nothing destroys
/// data):
///
/// 1. **Ingesting copies; it never moves.** The user's original file stays
///    exactly where it was. This store is a derived artifact — if it were
///    deleted wholesale tomorrow, nothing the user owns would be lost.
/// 2. **A stored file is never overwritten.** If the digest is already present
///    the bytes are by definition identical, so re-ingesting is a no-op that
///    reports `wasNew: false` rather than a rewrite.
public final class RawStore {
    /// Files bigger than this are refused rather than copied. A raw store is
    /// meant to hold transcripts and documents; a stray disk image in a scanned
    /// folder would quietly double the user's storage footprint.
    public static let defaultByteLimit = 8 * 1024 * 1024

    public let directoryURL: URL
    private let byteLimit: Int
    private let fileManager: FileManager

    /// Stored names already on disk, keyed by digest prefix.
    ///
    /// Exists because the digest is the identity but the *filename* also carries
    /// the original name for readability — so the same bytes arriving as
    /// `a.md` and later as `b.md` would compute two different destination paths
    /// and be stored twice. Looking the digest up here instead of trusting the
    /// path is what makes deduplication actually hold. Built once per instance;
    /// a bulk first run over thousands of files would otherwise relist the
    /// directory for every single file.
    private var storedNamesByDigest: [String: String]?

    public init(
        directoryURL: URL,
        byteLimit: Int = RawStore.defaultByteLimit,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.byteLimit = byteLimit
        self.fileManager = fileManager
    }

    /// `/raw` sits beside the event log rather than in a fixed location, so that
    /// pointing the app at a different folder (`switchDataFolder`) moves the raw
    /// resources with the corpus that indexes them. A note whose pointer
    /// resolves to a file belonging to a different vault would be worse than no
    /// pointer at all.
    public static func directoryURL(besideEventLog eventLogURL: URL) -> URL {
        eventLogURL.deletingLastPathComponent().appendingPathComponent("raw", isDirectory: true)
    }

    /// Takes a copy of `sourceURL` into the store.
    ///
    /// Returns the resource and whether this run is what put it there —
    /// `wasNew: false` means the exact bytes were already present, which is the
    /// normal and expected outcome of re-scanning a folder that hasn't changed.
    @discardableResult
    public func ingest(contentsOf sourceURL: URL) throws -> (resource: RawResource, wasNew: Bool) {
        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw RawStoreError.notAFile(sourceURL)
        }
        let byteCount = (attributes[.size] as? Int) ?? 0
        guard byteCount <= byteLimit else {
            throw RawStoreError.tooLarge(sourceURL, bytes: byteCount, limit: byteLimit)
        }

        let digest = try Self.digest(ofFileAt: sourceURL)

        // Identity is the digest, never the path. The same bytes arriving under
        // a second filename resolve to the copy already held.
        if let existing = index()[Self.digestPrefix(digest)] {
            return (
                RawResource(
                    digest: digest,
                    storedName: existing,
                    originalName: sourceURL.lastPathComponent,
                    byteCount: byteCount
                ),
                false
            )
        }

        let resource = RawResource(
            digest: digest,
            storedName: Self.storedName(digest: digest, originalName: sourceURL.lastPathComponent),
            originalName: sourceURL.lastPathComponent,
            byteCount: byteCount
        )

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: url(for: resource))
        storedNamesByDigest?[Self.digestPrefix(digest)] = resource.storedName
        return (resource, true)
    }

    public func url(for resource: RawResource) -> URL {
        directoryURL.appendingPathComponent(resource.storedName)
    }

    public func contains(digest: String) -> Bool {
        index()[Self.digestPrefix(digest)] != nil
    }

    /// The digest-prefix → stored-name map, listed from disk on first use.
    private func index() -> [String: String] {
        if let storedNamesByDigest { return storedNamesByDigest }
        let names = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        let built = Dictionary(
            names.compactMap { name -> (String, String)? in
                // Stored names are `<12 hex chars>-<original name>`.
                guard let separator = name.firstIndex(of: "-") else { return nil }
                return (String(name[name.startIndex..<separator]), name)
            },
            uniquingKeysWith: { first, _ in first }
        )
        storedNamesByDigest = built
        return built
    }

    // MARK: - Naming

    /// Enough digest to be collision-free in any realistic corpus, short enough
    /// that the filename still reads as the original in a Finder window.
    static func digestPrefix(_ digest: String) -> String {
        String(digest.prefix(12))
    }

    static func storedName(digest: String, originalName: String) -> String {
        // Anything that could escape the raw directory or confuse a shell is
        // replaced rather than rejected: the original name is preserved in the
        // note either way, so a mangled filename costs nothing.
        let safe = originalName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let base = safe.isEmpty ? "resource" : String(safe.suffix(80))
        return "\(digestPrefix(digest))-\(base)"
    }

    // MARK: - Hashing

    /// Streams the file through SHA-256 in chunks. A whole-file `Data(contentsOf:)`
    /// would be simpler, but the byte limit is 8 MB per file and a bulk first run
    /// hashes thousands of them.
    static func digest(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
