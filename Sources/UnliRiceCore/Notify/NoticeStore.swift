import Darwin
import Foundation

/// The notification centre's backing store: a small, capped, replaceable list.
///
/// **Not the event log, on purpose.** Everything in `events.jsonl` is permanent
/// and irreversible by design (decision #1), and notices are the opposite of
/// that — they're read, they go stale, they get trimmed. Writing "the janitor
/// noticed something" into an append-only history the user can never compact
/// would be using the wrong tool because it happened to be nearby. Delete this
/// file and nothing the user owns is lost, the same status `/raw` has.
///
/// Corpus-scoped (it sits beside the event log) because the notices are *about*
/// a corpus, and pointing the app at a different vault should not carry over
/// three-week-old news about the last one.
public final class NoticeStore: @unchecked Sendable {
    /// Older notices are dropped past this. Small deliberately: a notification
    /// centre you have to scroll is one nobody reads to the bottom of, and the
    /// durable record of what happened is the event log, not this.
    public static let capacity = 50

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.unlirice.notices")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func url(besideEventLog eventLog: URL) -> URL {
        eventLog.deletingLastPathComponent().appendingPathComponent("notices.json")
    }

    public convenience init(besideEventLog eventLog: URL) {
        self.init(fileURL: NoticeStore.url(besideEventLog: eventLog))
    }

    /// Newest first.
    public func all() -> [Notice] {
        queue.sync { load() }
    }

    public func unreadCount() -> Int {
        all().filter { !$0.isRead }.count
    }

    /// Adds a notice, or refreshes the unread one that already describes the
    /// same situation. See `Notice.key`.
    @discardableResult
    public func post(_ notice: Notice) -> Notice {
        mutate { notices in
            if let index = notices.firstIndex(where: { $0.key == notice.key && !$0.isRead }) {
                // Keep the original id so a view holding a selection doesn't
                // lose it, but take the new wording, time and destination.
                let refreshed = Notice(
                    id: notices[index].id,
                    timestamp: notice.timestamp,
                    kind: notice.kind,
                    key: notice.key,
                    title: notice.title,
                    detail: notice.detail,
                    destination: notice.destination
                )
                notices[index] = refreshed
                return refreshed
            }
            notices.insert(notice, at: 0)
            return notice
        }
    }

    public func markRead(_ id: UUID) {
        mutate { notices in
            if let index = notices.firstIndex(where: { $0.id == id }), notices[index].readAt == nil {
                notices[index].readAt = Date()
            }
        }
    }

    public func markAllRead() {
        mutate { notices in
            let now = Date()
            for index in notices.indices where notices[index].readAt == nil {
                notices[index].readAt = now
            }
        }
    }

    /// Clears everything. The only destructive operation in the app, and it is
    /// allowed precisely because these are derived messages rather than notes —
    /// see the type comment.
    public func clear() {
        mutate { $0.removeAll() }
    }

    // MARK: - Private

    /// Read-modify-write under an exclusive `flock`, because the GUI and
    /// `unlirice-agent` both post. Without the lock, an agent posting at the
    /// same moment the user marks something read would write back a list built
    /// from a stale read, and one of the two changes would vanish.
    @discardableResult
    private func mutate<T>(_ body: (inout [Notice]) -> T) -> T {
        queue.sync {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let fd = open(fileURL.path, O_RDONLY | O_CREAT, 0o644)
            if fd >= 0 {
                flock(fd, LOCK_EX)
            }
            defer {
                if fd >= 0 {
                    flock(fd, LOCK_UN)
                    close(fd)
                }
            }

            var notices = load()
            let result = body(&notices)
            if notices.count > Self.capacity {
                notices = Array(notices.prefix(Self.capacity))
            }
            save(notices)
            return result
        }
    }

    private func load() -> [Notice] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let notices = (try? decoder.decode([Notice].self, from: data)) ?? []
        return notices.sorted { $0.timestamp > $1.timestamp }
    }

    private func save(_ notices: [Notice]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notices) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
