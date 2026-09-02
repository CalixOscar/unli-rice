import Foundation

/// Every tool the MCP server dispatches, and whether it appends an Event.
///
/// `CaseIterable` + an exhaustive `switch` is the mechanism: adding a case
/// without classifying it is a compile error, where two parallel lists would
/// have silently agreed with each other and missed the new tool entirely.
public enum MCPTool: String, CaseIterable, Sendable {
    case createNote = "create_note"
    case appendToNote = "append_to_note"
    case tagNote = "tag_note"
    case untagNote = "untag_note"
    case archiveNote = "archive_note"
    case unarchiveNote = "unarchive_note"
    case flagForReview = "flag_for_review"
    case resolveReview = "resolve_review"
    case getNote = "get_note"
    case listNotes = "list_notes"
    case searchNotes = "search_notes"
    case noteHistory = "note_history"
    case pendingReviews = "pending_reviews"
    case transactionLog = "transaction_log"

    /// Appends an Event. No `default` — a new case must be classified here.
    public var isWrite: Bool {
        switch self {
        case .createNote, .appendToNote, .tagNote, .untagNote,
             .archiveNote, .unarchiveNote, .flagForReview, .resolveReview:
            return true
        case .getNote, .listNotes, .searchNotes, .noteHistory,
             .pendingReviews, .transactionLog:
            return false
        }
    }
}
