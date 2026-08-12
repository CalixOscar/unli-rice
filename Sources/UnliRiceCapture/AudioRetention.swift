import Foundation

/// How long recordings are kept on the phone.
///
/// **Prunes audio, never notes.** The obvious reading of "auto-delete after N
/// days" is to delete the note, and this architecture cannot do that: `EventKind`
/// has no `.deleted` case on purpose (see `Event.swift`), because the log is
/// append-only and shared across devices. It also isn't what costs anything —
/// a transcript is a few hundred bytes and the recording it came from is roughly
/// 30MB an hour. Pruning the audio reclaims effectively all of the space and
/// leaves the thought itself intact and still searchable.
public enum AudioRetention: String, Codable, CaseIterable, Identifiable, Sendable {
    case forever = "Keep forever"
    case oneWeek = "7 days"
    case oneMonth = "30 days"
    case threeMonths = "90 days"

    public var id: String { rawValue }

    public var days: Int? {
        switch self {
        case .forever: return nil
        case .oneWeek: return 7
        case .oneMonth: return 30
        case .threeMonths: return 90
        }
    }

    /// Deletes recordings older than the policy allows and returns the bytes
    /// reclaimed. Files are matched on their own modification date rather than
    /// the note timestamp so a recording is never removed early because a note
    /// was backdated by an import.
    @discardableResult
    public func sweep(audioDirectory: URL, now: Date = Date()) -> Int64 {
        guard let days else { return 0 }
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var reclaimed: Int64 = 0

        for url in entries where url.pathExtension.lowercased() == "m4a" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            let size = Int64(values?.fileSize ?? 0)
            if (try? fileManager.removeItem(at: url)) != nil {
                reclaimed += size
            }
        }
        return reclaimed
    }

    /// Total size of everything currently held, for the settings screen. Nobody
    /// picks a retention window without being told what it is costing them.
    public static func audioFootprint(audioDirectory: URL) -> Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return entries.reduce(into: Int64(0)) { total, url in
            guard url.pathExtension.lowercased() == "m4a" else { return }
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }
}
