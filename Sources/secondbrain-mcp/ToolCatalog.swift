import Foundation

/// The full set of tools exposed to MCP clients (Claude, Gemini, ChatGPT, Kimi,
/// or anything else that speaks MCP). Notice there is no delete/overwrite tool
/// here at all — the capability simply doesn't exist on this surface. See
/// PROJECT_NOTES.md for why that's a deliberate, load-bearing decision.
enum ToolCatalog {
    static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    static func bool(_ description: String, default def: Bool) -> [String: Any] {
        ["type": "boolean", "description": description, "default": def]
    }

    static func integer(_ description: String, default def: Int) -> [String: Any] {
        ["type": "integer", "description": description, "default": def]
    }

    static let sourceDescription = "Identity of the calling agent, e.g. 'claude', 'gemini', 'chatgpt', 'kimi'"

    static let all: [[String: Any]] = [
        [
            "name": "create_note",
            "description": "Create a new note. Always creates a brand-new note; never overwrites an existing one.",
            "inputSchema": schema([
                "title": string("Short title for the note"),
                "body": string("Note content"),
                "source": string(sourceDescription)
            ], required: ["title", "body", "source"])
        ],
        [
            "name": "append_to_note",
            "description": "Append new content to an existing note. Never replaces or removes prior content — this preserves full history from every contributing agent.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "text": string("Text to append"),
                "source": string(sourceDescription)
            ], required: ["id", "text", "source"])
        ],
        [
            "name": "tag_note",
            "description": "Add a tag to a note.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "tag": string("Tag to add"),
                "source": string(sourceDescription)
            ], required: ["id", "tag", "source"])
        ],
        [
            "name": "untag_note",
            "description": "Remove a tag from a note.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "tag": string("Tag to remove"),
                "source": string(sourceDescription)
            ], required: ["id", "tag", "source"])
        ],
        [
            "name": "archive_note",
            "description": "Soft-archive a note: hides it from default listings. Fully reversible with unarchive_note. This is the closest thing to delete that exists — there is no permanent delete tool.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "reason": string("Why this note is being archived"),
                "source": string(sourceDescription)
            ], required: ["id", "reason", "source"])
        ],
        [
            "name": "unarchive_note",
            "description": "Restore a previously archived note back to normal listings.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "source": string(sourceDescription)
            ], required: ["id", "source"])
        ],
        [
            "name": "flag_for_review",
            "description": "Flag a note for human review — e.g. a suspected duplicate, a conflict with another agent's note, or a proposed merge/restructure. This NEVER applies a change itself; it only queues the concern. Use this instead of trying to resolve conflicts yourself.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "reason": string("What the concern is and what you'd suggest doing about it"),
                "source": string(sourceDescription)
            ], required: ["id", "reason", "source"])
        ],
        [
            "name": "resolve_review",
            "description": "Mark a pending review flag as resolved. Intended for use once a human has decided what to do about it.",
            "inputSchema": schema([
                "id": string("Note id (UUID)"),
                "flag_id": string("The id of the flag being resolved"),
                "source": string(sourceDescription)
            ], required: ["id", "flag_id", "source"])
        ],
        [
            "name": "get_note",
            "description": "Fetch a single note by id.",
            "inputSchema": schema(["id": string("Note id (UUID)")], required: ["id"])
        ],
        [
            "name": "list_notes",
            "description": "List notes, most recently updated first.",
            "inputSchema": schema(["include_archived": bool("Include archived notes", default: false)])
        ],
        [
            "name": "search_notes",
            "description": "Keyword search over note titles, bodies, and tags. Simple substring matching in this MVP — no semantic/vector search yet.",
            "inputSchema": schema([
                "query": string("Search text"),
                "include_archived": bool("Include archived notes", default: false)
            ], required: ["query"])
        ],
        [
            "name": "pending_reviews",
            "description": "List all unresolved review flags across all notes, oldest first.",
            "inputSchema": schema([:])
        ],
        [
            "name": "transaction_log",
            "description": "Raw recent events across the whole brain, most recent first — the audit trail.",
            "inputSchema": schema(["limit": integer("Max number of events to return", default: 50)])
        ]
    ]
}
