import Foundation

/// Pure Core presentation decision for the To do pane's empty state.
///
/// Both the Mac app and the phone render through this function so neither
/// can round partial coverage or an unreadable snapshot up to "Nothing outstanding".
public enum TodoEmptyState: Equatable, Sendable {
    /// The snapshot was not read at all.
    case unread
    /// The snapshot was read successfully, but contained 0 repositories.
    case emptySnapshot
    /// Both dirt and nextSteps were completely inspected across all repositories.
    case nothingOutstanding
    /// Findings are incomplete because one or both areas were not completely inspected.
    case qualified(message: String)

    public var headline: String {
        switch self {
        case .unread:
            return "Nothing to read yet."
        case .emptySnapshot:
            return "This snapshot contains no repositories."
        case .nothingOutstanding:
            return "Nothing outstanding"
        case .qualified:
            return "Nothing outstanding that this can see."
        }
    }

    public var renderedString: String {
        switch self {
        case .unread:
            return "Nothing to read yet."
        case .emptySnapshot:
            return "This snapshot contains no repositories."
        case .nothingOutstanding:
            return "Nothing outstanding"
        case .qualified(let message):
            return message
        }
    }

    public static func `for`(coverage: StudioTodo.Coverage) -> TodoEmptyState {
        guard coverage.snapshotRead else {
            return .unread
        }
        guard !coverage.repositories.isEmpty else {
            return .emptySnapshot
        }
        if coverage.dirt == .complete && coverage.nextSteps == .complete {
            return .nothingOutstanding
        }
        let message = coverage.gapSummary ?? "not all repositories were fully inspected"
        return .qualified(message: message)
    }
}
