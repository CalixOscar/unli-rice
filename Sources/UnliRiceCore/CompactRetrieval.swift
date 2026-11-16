import Foundation
import CryptoKit

public enum CompactRetrievalError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case invalidArgument(String)
    case invalidCursor
    case staleCursor
    case budgetTooSmall(String)

    public var description: String {
        switch self {
        case .invalidArgument(let message): return message
        case .invalidCursor: return "Invalid cursor. Search again without a cursor."
        case .staleCursor: return "The matching notes changed since this cursor was issued. Search again without a cursor."
        case .budgetTooSmall(let message): return message
        }
    }
    public var errorDescription: String? { description }
}

public enum CompactRetrieval {
    public static let defaultLimit = 10
    public static let limitRange = 1...50
    public static let defaultMaxBytes = 16_384
    public static let maxBytesRange = 2_048...65_536
    public static let envelopeReserve = 128
    public static let maxBatchIDs = 20
    public static let incompleteNotice = "Some notes are left out because their history is incomplete or conflicting. Results may be incomplete."

    static let maxQueryBytes = 1_024
    static let maxCursorBytes = 512
    static let maxTitleBytes = 200
    static let minimalTitleBytes = 96
    static let maxExcerptBytes = 320
    static let excerptLeadBytes = 100
    static let maxTags = 8
    static let maxTagBytes = 64

    public struct MatchedFields: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let title = MatchedFields(rawValue: 1 << 0)
        public static let body = MatchedFields(rawValue: 1 << 1)
        public static let tags = MatchedFields(rawValue: 1 << 2)
    }

    /// The one match predicate, shared by `searchNotes` and compact search.
    public static func matchedFields(_ note: Note, lowercasedQuery q: String) -> MatchedFields {
        var fields: MatchedFields = []
        if note.title.lowercased().contains(q) { fields.insert(.title) }
        if note.body.lowercased().contains(q) { fields.insert(.body) }
        if note.tags.contains(where: { $0.lowercased().contains(q) }) { fields.insert(.tags) }
        return fields
    }

    // MARK: - Requests

    public struct SearchRequest: Sendable {
        public let query: String
        public let limit: Int
        public let maxBytes: Int
        public let cursor: String?
        public let includeArchived: Bool

        public init(query: String, limit: Int? = nil, maxBytes: Int? = nil,
                    cursor: String? = nil, includeArchived: Bool = false) throws {
            guard !query.isEmpty, query.utf8.count <= CompactRetrieval.maxQueryBytes else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.queryMessage)
            }
            let limit = limit ?? CompactRetrieval.defaultLimit
            guard CompactRetrieval.limitRange.contains(limit) else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.limitMessage)
            }
            let maxBytes = maxBytes ?? CompactRetrieval.defaultMaxBytes
            guard CompactRetrieval.maxBytesRange.contains(maxBytes) else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.maxBytesMessage)
            }
            if let cursor, cursor.utf8.count > CompactRetrieval.maxCursorBytes {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.cursorMessage)
            }
            self.query = query
            self.limit = limit
            self.maxBytes = maxBytes
            self.cursor = cursor
            self.includeArchived = includeArchived
        }

        /// Raw JSON-RPC arguments (SPEC S9). Unknown keys are ignored.
        public init(arguments: [String: Any]) throws {
            guard let query = arguments["query"] as? String else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.queryMessage)
            }
            let limit = try CompactRetrieval.optionalInteger(arguments, "limit", message: CompactRetrieval.limitMessage)
            let maxBytes = try CompactRetrieval.optionalInteger(arguments, "max_bytes", message: CompactRetrieval.maxBytesMessage)
            var cursor: String?
            if let raw = arguments["cursor"] {
                guard let text = raw as? String else {
                    throw CompactRetrievalError.invalidArgument(CompactRetrieval.cursorMessage)
                }
                cursor = text
            }
            let include = try CompactRetrieval.optionalBoolean(arguments, "include_archived", message: CompactRetrieval.includeArchivedMessage)
            try self.init(query: query, limit: limit, maxBytes: maxBytes, cursor: cursor, includeArchived: include ?? false)
        }
    }

    public struct BatchRequest: Sendable {
        public let ids: [UUID]
        public let maxBytes: Int
        public let includeArchived: Bool

        public init(ids: [String], maxBytes: Int? = nil, includeArchived: Bool = false) throws {
            guard (1...CompactRetrieval.maxBatchIDs).contains(ids.count) else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.idsMessage)
            }
            var parsed: [UUID] = []
            var seen = Set<UUID>()
            for (position, text) in ids.enumerated() {
                guard let id = UUID(uuidString: text) else {
                    throw CompactRetrievalError.invalidArgument("ids[\(position)] is not a valid note id.")
                }
                guard seen.insert(id).inserted else {
                    throw CompactRetrievalError.invalidArgument("ids[\(position)] repeats an earlier id.")
                }
                parsed.append(id)
            }
            let maxBytes = maxBytes ?? CompactRetrieval.defaultMaxBytes
            guard CompactRetrieval.maxBytesRange.contains(maxBytes) else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.maxBytesMessage)
            }
            self.ids = parsed
            self.maxBytes = maxBytes
            self.includeArchived = includeArchived
        }

        /// Raw JSON-RPC arguments (SPEC S9). Unknown keys are ignored.
        public init(arguments: [String: Any]) throws {
            guard let raw = arguments["ids"] as? [Any] else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.idsMessage)
            }
            guard (1...CompactRetrieval.maxBatchIDs).contains(raw.count) else {
                throw CompactRetrievalError.invalidArgument(CompactRetrieval.idsMessage)
            }
            var strings: [String] = []
            for (position, element) in raw.enumerated() {
                guard let text = element as? String else {
                    throw CompactRetrievalError.invalidArgument("ids[\(position)] is not a valid note id.")
                }
                strings.append(text)
            }
            let maxBytes = try CompactRetrieval.optionalInteger(arguments, "max_bytes", message: CompactRetrieval.maxBytesMessage)
            let include = try CompactRetrieval.optionalBoolean(arguments, "include_archived", message: CompactRetrieval.includeArchivedMessage)
            try self.init(ids: strings, maxBytes: maxBytes, includeArchived: include ?? false)
        }
    }

    static let idsMessage = "ids must be an array of 1 to 20 note id strings."

    static let queryMessage = "query must be a non-empty string of at most 1024 bytes."
    static let limitMessage = "limit must be an integer from 1 to 50."
    static let maxBytesMessage = "max_bytes must be an integer from 2048 to 65536."
    static let cursorMessage = "cursor must be a string of at most 512 bytes."
    static let includeArchivedMessage = "include_archived must be true or false."

    /// A JSON number that is not a boolean, is finite and whole. Anything else is nil.
    static func wholeNumber(_ raw: Any) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let d = number.doubleValue
        guard d.isFinite, d.rounded(.towardZero) == d, abs(d) < 9.0e18 else { return nil }
        return Int(d)
    }

    /// Absent -> nil. Present but null, non-numeric, boolean, fractional or non-finite -> error.
    /// Out-of-range huge values map to `Int.max` so the caller's range check rejects them.
    static func optionalInteger(_ arguments: [String: Any], _ key: String, message: String) throws -> Int? {
        guard let raw = arguments[key] else { return nil }
        if let value = wholeNumber(raw) { return value }
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
           number.doubleValue.isFinite, number.doubleValue.rounded(.towardZero) == number.doubleValue {
            return number.doubleValue > 0 ? Int.max : Int.min
        }
        throw CompactRetrievalError.invalidArgument(message)
    }

    static func optionalBoolean(_ arguments: [String: Any], _ key: String, message: String) throws -> Bool? {
        guard let raw = arguments[key] else { return nil }
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw CompactRetrievalError.invalidArgument(message)
        }
        return number.boolValue
    }

    // MARK: - Result envelope

    /// `{"content":[{"type":"text","text":…}]}`
    public static func toolResult(text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]]]
    }

    /// Bytes of the result as the server's writer serializes it (default options).
    public static func serializedByteCount(_ toolResult: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: toolResult).count) ?? Int.max
    }

    static func payloadText(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func fits(_ text: String, maxBytes: Int) -> Bool {
        serializedByteCount(toolResult(text: text)) <= maxBytes - envelopeReserve
    }

    static func diagnosticsPayload(_ d: ProjectionDiagnostics) -> [String: Any] {
        [
            "incomplete": !d.incompleteNoteIDs.isEmpty,
            "pending_notes": d.pendingNoteIDs.count,
            "conflicted_notes": d.conflictedNoteIDs.count
        ]
    }

    // MARK: - Text helpers

    /// Longest prefix of `text` of at most `maxBytes` UTF-8 bytes, cut between whole characters.
    static func cut(_ text: String, toBytes maxBytes: Int) -> (text: String, truncated: Bool) {
        if text.utf8.count <= maxBytes { return (text, false) }
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let next = text.index(after: index)
            let n = text[index..<next].utf8.count
            if used + n > maxBytes { break }
            used += n
            end = next
        }
        return (String(text[text.startIndex..<end]), true)
    }

    struct Excerpt {
        let text: String
        let cut: String
        let at: String
    }

    static func excerpt(of body: String, lowercasedQuery q: String) -> Excerpt {
        if body.isEmpty { return Excerpt(text: "", cut: "none", at: "start") }

        func window(from start: String.Index) -> (String, String.Index) {
            var used = 0
            var end = start
            while end < body.endIndex {
                let next = body.index(after: end)
                let n = body[end..<next].utf8.count
                if used + n > maxExcerptBytes { break }
                used += n
                end = next
            }
            return (String(body[start..<end]), end)
        }
        func describe(_ text: String, _ start: String.Index, _ end: String.Index, at: String) -> Excerpt {
            if text.isEmpty { return Excerpt(text: "", cut: "omitted", at: at) }
            let front = start > body.startIndex, back = end < body.endIndex
            return Excerpt(text: text, cut: front && back ? "both" : front ? "start" : back ? "end" : "none", at: at)
        }

        let lowered = body.lowercased()
        if lowered.count == body.count, let found = lowered.firstRange(of: q) {
            let position = lowered.distance(from: lowered.startIndex, to: found.lowerBound)
            var start = body.index(body.startIndex, offsetBy: position)
            var back = 0
            while start > body.startIndex {
                let previous = body.index(before: start)
                let n = body[previous..<start].utf8.count
                if back + n > excerptLeadBytes { break }
                back += n
                start = previous
            }
            let (text, end) = window(from: start)
            if !text.isEmpty, text.lowercased().contains(q) { return describe(text, start, end, at: "match") }
        }
        let (text, end) = window(from: body.startIndex)
        return describe(text, body.startIndex, end, at: "start")
    }

    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Cursor

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func queryDigest(_ lowercasedQuery: String) -> String {
        hex(SHA256.hash(data: Data(lowercasedQuery.utf8)).prefix(8))
    }

    static func matchDigest(_ ids: [UUID]) -> String {
        var hasher = SHA256()
        for id in ids {
            withUnsafeBytes(of: id.uuid) { hasher.update(bufferPointer: $0) }
        }
        return hex(hasher.finalize().prefix(16))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func makeCursor(query: String, includeArchived: Bool, digest: String, offset: Int) throws -> String {
        let object: [String: Any] = [
            "v": 1, "q": queryDigest(query), "a": includeArchived ? 1 : 0,
            "m": digest, "o": offset
        ]
        return base64URL(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    private static func isLowerHex(_ s: String, count: Int) -> Bool {
        s.utf8.count == count && s.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    /// Validates a cursor against the current matches and returns its position.
    static func decodeCursor(_ cursor: String, lowercasedQuery: String, includeArchived: Bool,
                             ids: [UUID]) throws -> Int {
        let bytes = Array(cursor.utf8)
        guard !bytes.isEmpty, bytes.count <= maxCursorBytes, bytes.count % 4 != 1,
              bytes.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 95 })
        else { throw CompactRetrievalError.invalidCursor }
        var padded = cursor.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while padded.utf8.count % 4 != 0 { padded += "=" }
        guard let data = Data(base64Encoded: padded), base64URL(data) == cursor,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(object.keys) == ["v", "q", "a", "m", "o"],
              let version = wholeNumber(object["v"] as Any), version == 1,
              let q = object["q"] as? String, isLowerHex(q, count: 16),
              let a = wholeNumber(object["a"] as Any), a == 0 || a == 1,
              let m = object["m"] as? String, isLowerHex(m, count: 32),
              let o = wholeNumber(object["o"] as Any), o >= 1
        else { throw CompactRetrievalError.invalidCursor }
        guard q == queryDigest(lowercasedQuery), (a == 1) == includeArchived else {
            throw CompactRetrievalError.invalidCursor
        }
        guard m == matchDigest(ids) else { throw CompactRetrievalError.staleCursor }
        guard o < ids.count else { throw CompactRetrievalError.invalidCursor }
        return o
    }

    // MARK: - Search

    static func sortedKeysTags(_ note: Note) -> (shown: [String], omitted: Int) {
        let all = note.tags.sorted()
        let eligible = all.filter { $0.utf8.count <= maxTagBytes }
        let shown = Array(eligible.prefix(maxTags))
        return (shown, all.count - shown.count)
    }

    static func matchedNames(_ fields: MatchedFields) -> [String] {
        var names: [String] = []
        if fields.contains(.title) { names.append("title") }
        if fields.contains(.body) { names.append("body") }
        if fields.contains(.tags) { names.append("tags") }
        return names
    }

    static func normalResult(_ note: Note, _ fields: MatchedFields, lowercasedQuery q: String) -> [String: Any] {
        let title = cut(note.title, toBytes: maxTitleBytes)
        let excerpt = excerpt(of: note.body, lowercasedQuery: q)
        let tags = sortedKeysTags(note)
        var result: [String: Any] = [
            "id": note.id.uuidString,
            "title": title.text,
            "excerpt": excerpt.text,
            "excerpt_cut": excerpt.cut,
            "excerpt_at": excerpt.at,
            "matched": matchedNames(fields),
            "tags": tags.shown,
            "updated_at": timestamp(note.updatedAt),
            "archived": note.archived
        ]
        if title.truncated { result["title_truncated"] = true }
        if tags.omitted > 0 { result["tags_omitted"] = tags.omitted }
        return result
    }

    static func minimalResult(_ note: Note, _ fields: MatchedFields) -> [String: Any] {
        let title = cut(note.title, toBytes: minimalTitleBytes)
        var result: [String: Any] = [
            "id": note.id.uuidString,
            "title": title.text,
            "excerpt": "",
            "excerpt_cut": "omitted",
            "excerpt_at": "start",
            "matched": matchedNames(fields),
            "tags": [String](),
            "tags_omitted": note.tags.count,
            "updated_at": timestamp(note.updatedAt),
            "archived": note.archived,
            "minimal": true
        ]
        if title.truncated { result["title_truncated"] = true }
        return result
    }

    /// Payload JSON text. Guarantees `serializedByteCount(toolResult(text:)) <= maxBytes - envelopeReserve`.
    public static func searchSummaries(_ request: SearchRequest, in snapshot: RetrievalSnapshot) throws -> String {
        let q = request.query.lowercased()
        var matches: [(note: Note, fields: MatchedFields)] = []
        for note in snapshot.notes.values where request.includeArchived || !note.archived {
            let fields = matchedFields(note, lowercasedQuery: q)
            if !fields.isEmpty { matches.append((note, fields)) }
        }
        matches.sort {
            $0.note.updatedAt != $1.note.updatedAt
                ? $0.note.updatedAt > $1.note.updatedAt
                : $0.note.id.uuidString < $1.note.id.uuidString
        }
        let ids = matches.map(\.note.id)
        let total = matches.count
        let idsDigest = matchDigest(ids)
        var offset = 0
        if let cursor = request.cursor {
            offset = try decodeCursor(cursor, lowercasedQuery: q, includeArchived: request.includeArchived, ids: ids)
        }
        let remaining = total - offset
        let diagnostics = diagnosticsPayload(snapshot.diagnostics)
        let incomplete = !snapshot.diagnostics.incompleteNoteIDs.isEmpty

        func page(_ results: [[String: Any]]) throws -> String {
            let end = offset + results.count
            let more = end < total
            let next: Any = more
                ? try makeCursor(query: q, includeArchived: request.includeArchived, digest: idsDigest, offset: end)
                : NSNull()
            var payload: [String: Any] = [
                "diagnostics": diagnostics,
                "next_cursor": next,
                "offset": offset,
                "results": results,
                "returned": results.count,
                "revision": snapshot.revision,
                "stopped_by": !more ? "end" : results.count == request.limit ? "limit" : "budget",
                "total_matches": total
            ]
            if incomplete { payload["notice"] = incompleteNotice }
            return try payloadText(payload)
        }

        let maxCount = min(request.limit, remaining)
        guard maxCount > 0 else {
            let text = try page([])
            guard fits(text, maxBytes: request.maxBytes) else { throw tooSmall }
            return text
        }
        let normal = (0..<maxCount).map { normalResult(matches[offset + $0].note, matches[offset + $0].fields, lowercasedQuery: q) }
        var best: String?
        for count in 1...maxCount {
            let text = try page(Array(normal[0..<count]))
            // Each added result only grows the page, so the first miss ends the search.
            guard fits(text, maxBytes: request.maxBytes) else { break }
            best = text
        }
        if let best { return best }
        let first = matches[offset]
        let text = try page([minimalResult(first.note, first.fields)])
        guard fits(text, maxBytes: request.maxBytes) else { throw tooSmall }
        return text
    }

    // MARK: - Batch

    static let batchTooSmall = CompactRetrievalError.budgetTooSmall("max_bytes is too small to report every requested id. Raise max_bytes or request fewer ids.")
    static let retryCeiling = 65_536

    private enum BatchEntry {
        case plain(String)                       // missing, archived_excluded, unavailable_*
        case omitted(retry: Int?)                // readable, not (yet) returned
        case returned(Note)
    }

    /// Payload JSON text. Guarantees `serializedByteCount(toolResult(text:)) <= maxBytes - envelopeReserve`.
    public static func batch(_ request: BatchRequest, in snapshot: RetrievalSnapshot) throws -> String {
        let diagnostics = diagnosticsPayload(snapshot.diagnostics)
        let incomplete = !snapshot.diagnostics.incompleteNoteIDs.isEmpty

        func entryObject(_ id: UUID, _ entry: BatchEntry) -> [String: Any] {
            switch entry {
            case .plain(let status):
                return ["id": id.uuidString, "status": status]
            case .omitted(let retry):
                var object: [String: Any] = ["id": id.uuidString, "status": "omitted_for_budget", "fits_max_budget": retry != nil]
                if let retry { object["retry_max_bytes"] = retry }
                return object
            case .returned(let note):
                return [
                    "id": id.uuidString, "status": "returned",
                    "title": note.title, "body": note.body,
                    "tags": note.tags.sorted(),
                    "created_at": timestamp(note.createdAt), "updated_at": timestamp(note.updatedAt),
                    "archived": note.archived,
                    "creator": note.creator,
                    "sources": note.sources.sorted()
                ]
            }
        }
        func payload(_ ids: [UUID], _ entries: [BatchEntry]) throws -> String {
            var returned = 0, omitted = 0
            for entry in entries {
                if case .returned = entry { returned += 1 }
                if case .omitted = entry { omitted += 1 }
            }
            var object: [String: Any] = [
                "notes": zip(ids, entries).map { entryObject($0, $1) },
                "returned": returned,
                "omitted_for_budget": omitted,
                "revision": snapshot.revision,
                "diagnostics": diagnostics
            ]
            if incomplete { object["notice"] = incompleteNotice }
            return try payloadText(object)
        }
        func retryBytes(for note: Note) throws -> Int? {
            if note.body.utf8.count > retryCeiling { return nil }
            let alone = try payload([note.id], [.returned(note)])
            let needed = serializedByteCount(toolResult(text: alone)) + envelopeReserve
            return needed > retryCeiling ? nil : max(maxBytesRange.lowerBound, needed)
        }

        var entries: [BatchEntry] = []
        for id in request.ids {
            if snapshot.diagnostics.conflictedNoteIDs.contains(id) {
                entries.append(.plain("unavailable_conflicted"))
            } else if snapshot.diagnostics.pendingNoteIDs.contains(id) {
                entries.append(.plain("unavailable_pending"))
            } else if let note = snapshot.notes[id] {
                if note.archived && !request.includeArchived {
                    entries.append(.plain("archived_excluded"))
                } else {
                    entries.append(.omitted(retry: try retryBytes(for: note)))
                }
            } else {
                entries.append(.plain("missing"))
            }
        }
        var best = try payload(request.ids, entries)
        guard fits(best, maxBytes: request.maxBytes) else { throw batchTooSmall }
        for index in entries.indices {
            // A note that cannot fit alone cannot fit here either, so it is never serialized again.
            guard case .omitted(let retry?) = entries[index], retry <= request.maxBytes,
                  let note = snapshot.notes[request.ids[index]] else { continue }
            var trial = entries
            trial[index] = .returned(note)
            let text = try payload(request.ids, trial)
            if fits(text, maxBytes: request.maxBytes) {
                entries = trial
                best = text
            }
        }
        return best
    }

    static let tooSmall = CompactRetrievalError.budgetTooSmall("max_bytes is too small to return a result. Raise max_bytes.")
}
