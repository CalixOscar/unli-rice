import Foundation

public struct CaptureReceiptFile: Codable, Equatable, Sendable {
    public let version: Int
    public let generatedAt: Date
    public let deviceLabel: String
    public let receivedNoteIDs: [UUID]
    private static let maximumBytes = 2 * 1024 * 1024

    public init(version: Int = 1, generatedAt: Date = Date(), deviceLabel: String, receivedNoteIDs: [UUID]) {
        self.version = version
        self.generatedAt = generatedAt
        self.deviceLabel = deviceLabel
        var seen = Set<UUID>()
        var unique: [UUID] = []
        for id in receivedNoteIDs where seen.insert(id).inserted {
            unique.append(id)
            if unique.count == 2000 { break }
        }
        self.receivedNoteIDs = unique
    }

    public enum ReadError: Error, LocalizedError, Equatable {
        case unreadable, oversized, tooManyFiles, tooManyIDs, unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .unreadable: return "A capture receipt could not be read."
            case .oversized: return "A capture receipt exceeds the 2 MB limit."
            case .tooManyFiles: return "There are more than 100 capture receipts."
            case .tooManyIDs: return "A capture receipt exceeds the 2000 ID limit."
            case .unsupportedVersion(let version): return "Unsupported capture receipt version \(version)."
            }
        }
    }

    public static func filename(deviceID: String) -> String {
        let safe = deviceID.unicodeScalars.filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").contains($0) }
        return "capture-receipt-\(String(String.UnicodeScalarView(safe))).json"
    }

    public func write(toFolder folder: URL, deviceID: String) throws {
        guard version == 1 else { throw ReadError.unsupportedVersion(version) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ReadError.oversized }
        try data.write(to: folder.appendingPathComponent(Self.filename(deviceID: deviceID)), options: .atomic)
    }

    public static func readAll(fromFolder folder: URL) throws -> [CaptureReceiptFile] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
                .filter { $0.lastPathComponent.hasPrefix("capture-receipt-") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch { throw ReadError.unreadable }
        guard urls.count <= 100 else { throw ReadError.tooManyFiles }
        return try urls.map { url in
            let data: Data
            do {
                guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ReadError.unreadable }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            } catch { throw ReadError.unreadable }
            guard data.count <= maximumBytes else { throw ReadError.oversized }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["version"] as? Int else { throw ReadError.unreadable }
            guard version == 1 else { throw ReadError.unsupportedVersion(version) }
            if let ids = object["receivedNoteIDs"] as? [Any], ids.count > 2000 { throw ReadError.tooManyIDs }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            guard let receipt = try? decoder.decode(Self.self, from: data) else { throw ReadError.unreadable }
            return Self(version: receipt.version, generatedAt: receipt.generatedAt, deviceLabel: receipt.deviceLabel,
                        receivedNoteIDs: receipt.receivedNoteIDs)
        }
    }
}
