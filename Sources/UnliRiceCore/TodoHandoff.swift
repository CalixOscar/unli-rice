import Foundation

public enum TodoHandoff {
    /// The UUID on the body's FIRST line, which must be exactly `Handoff-ID: <uuid>`.
    /// Nothing else — no wiki-link fallback — so an old item's ordinary [[link]] can
    /// never be mistaken for a handoff (P10).
    public static func handoffID(inBody body: String) -> UUID? {
        guard let firstLine = body.components(separatedBy: .newlines).first else {
            return nil
        }
        let prefix = "Handoff-ID: "
        guard firstLine.hasPrefix(prefix) else {
            return nil
        }
        let rawUUID = String(firstLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
        return UUID(uuidString: rawUUID)
    }

    /// The note to open for an item: its handoff if `handoffID` names a note that exists
    /// AND carries the `handoff` tag; otherwise the item itself. One function, called by
    /// both navigation and prompt building, so they cannot disagree (P9, P10).
    public static func target(for item: Note, lookup: (UUID) -> Note?) -> Note {
        guard let id = handoffID(inBody: item.body),
              let candidate = lookup(id),
              candidate.tags.contains("handoff") else {
            return item
        }
        return candidate
    }
}
