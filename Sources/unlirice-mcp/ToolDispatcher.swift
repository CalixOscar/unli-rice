import Foundation
import UnliRiceCore

enum ToolDispatchError: Error, CustomStringConvertible {
    case unknownTool(String)
    case missingArgument(String)
    case invalidArgument(String)

    var description: String {
        switch self {
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .missingArgument(let name): return "Missing required argument: \(name)"
        case .invalidArgument(let name): return "Invalid argument: \(name)"
        }
    }
}

/// Translates MCP `tools/call` requests into NoteService calls and back into
/// MCP-shaped content blocks. This is the only place tool names are mapped to
/// behavior — the mapping is 1:1 with ToolCatalog.all and with NoteService's
/// public methods, so the exposed capability surface is easy to audit.
struct ToolDispatcher {
    let service: NoteService

    func dispatch(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            guard let tool = MCPTool(rawValue: name) else {
                throw ToolDispatchError.unknownTool(name)
            }
            let payload: Any
            switch tool {
            case .createNote:
                let note = try service.createNote(
                    title: try string(arguments, "title"),
                    body: try string(arguments, "body"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .appendToNote:
                let note = try service.appendToNote(
                    id: try uuid(arguments, "id"),
                    text: try string(arguments, "text"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .tagNote:
                let note = try service.tagNote(
                    id: try uuid(arguments, "id"),
                    tag: try string(arguments, "tag"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .untagNote:
                let note = try service.untagNote(
                    id: try uuid(arguments, "id"),
                    tag: try string(arguments, "tag"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .archiveNote:
                let note = try service.archiveNote(
                    id: try uuid(arguments, "id"),
                    reason: try string(arguments, "reason"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .unarchiveNote:
                let note = try service.unarchiveNote(
                    id: try uuid(arguments, "id"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .flagForReview:
                let note = try service.flagForReview(
                    id: try uuid(arguments, "id"),
                    reason: try string(arguments, "reason"),
                    source: try string(arguments, "source")
                )
                payload = try JSONRPC.plain(note)

            case .resolveReview:
                let note = try service.resolveReview(
                    id: try uuid(arguments, "id"),
                    flagId: try uuid(arguments, "flag_id"),
                    source: try string(arguments, "source"),
                    outcome: arguments["outcome"] as? String
                )
                payload = try JSONRPC.plain(note)

            case .getNote:
                if let note = try service.getNote(id: try uuid(arguments, "id")) {
                    payload = try JSONRPC.plain(note)
                } else {
                    payload = ["found": false]
                }

            case .listNotes:
                let includeArchived = (arguments["include_archived"] as? Bool) ?? false
                payload = try JSONRPC.plain(try service.listNotes(includeArchived: includeArchived))

            case .searchNotes:
                let includeArchived = (arguments["include_archived"] as? Bool) ?? false
                payload = try JSONRPC.plain(
                    try service.searchNotes(query: try string(arguments, "query"), includeArchived: includeArchived)
                )

            case .noteHistory:
                payload = try JSONRPC.plain(
                    try service.noteHistory(id: try uuid(arguments, "id"))
                )

            case .pendingReviews:
                let reviews = try service.pendingReviews()
                payload = reviews.map { entry -> [String: Any] in
                    let notePayload = (try? JSONRPC.plain(entry.note)) ?? [:]
                    let flagPayload = (try? JSONRPC.plain(entry.flag)) ?? [:]
                    return ["note": notePayload, "flag": flagPayload]
                }

            case .transactionLog:
                if let rawLimit = arguments["limit"] as? Int {
                    guard rawLimit >= 0 else {
                        throw ToolDispatchError.invalidArgument("limit must be non-negative, got \(rawLimit)")
                    }
                    payload = try JSONRPC.plain(try service.transactionLog(limit: rawLimit))
                } else {
                    payload = try JSONRPC.plain(try service.transactionLog())
                }
            }

            let text = try jsonString(payload)
            return ["content": [["type": "text", "text": text]]]
        } catch {
            return [
                "content": [["type": "text", "text": "Error: \(error)"]],
                "isError": true
            ]
        }
    }

    private func string(_ arguments: [String: Any], _ key: String) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw ToolDispatchError.missingArgument(key)
        }
        return value
    }

    private func uuid(_ arguments: [String: Any], _ key: String) throws -> UUID {
        guard let raw = arguments[key] as? String, let id = UUID(uuidString: raw) else {
            throw ToolDispatchError.invalidArgument(key)
        }
        return id
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
