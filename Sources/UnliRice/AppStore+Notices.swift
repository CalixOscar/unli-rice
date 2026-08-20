import Foundation
import UnliRiceCore

/// The notification centre.
///
/// It exists because of a mismatch this app had between two things the user
/// wants: it should run itself, *and* opening it a year later should be a
/// pleasure rather than a chore. Those clash the moment the app needs you to
/// come to it — a year of unattended work with no way to mention anything
/// becomes a pile of pending chores waiting at the door.
///
/// So the centre is deliberately small and deliberately passive. It notices
/// things; it never acts on them. Every entry points at a screen where *you*
/// decide, which keeps it on the safe side of decision #3 exactly like the
/// review queue it usually points at.
extension AppStore {
    var unreadNoticeCount: Int {
        notices.filter { !$0.isRead }.count
    }

    /// Re-reads the notice file. Called from `reload()` because
    /// `unlirice-agent` writes into it while this window is open — the notices
    /// are the one piece of state here another process legitimately changes
    /// behind our back.
    func refreshNotices() {
        notices = noticeStore.all()
    }

    func showNotices() {
        selectNote(nil)
        closeAllPanes()
        showingNotices = true
        statusMessage = notices.isEmpty
            ? "Nothing to report — the app has been quiet."
            : "\(notices.count) recent thing\(notices.count == 1 ? "" : "s"), \(unreadNoticeCount) unread."
    }

    /// Opening a notice marks it read and goes where it points.
    ///
    /// Marking on *open* rather than on merely being displayed is the difference
    /// between a badge that means something and one that clears itself the
    /// moment you glance at the sidebar.
    func open(_ notice: Notice) {
        noticeStore.markRead(notice.id)
        refreshNotices()

        switch notice.destination {
        case .none:
            break
        case .reviewQueue:
            showReviewQueue()
        case .retrospective(let period):
            showRetrospective(periodID: period)
        case .notesFolder:
            showNotesFolder()
        }
    }

    func markNoticeRead(_ notice: Notice) {
        noticeStore.markRead(notice.id)
        refreshNotices()
    }

    func markAllNoticesRead() {
        noticeStore.markAllRead()
        refreshNotices()
    }

    /// Clears the list. Allowed, and the only clearing operation in the app,
    /// because notices are derived messages rather than notes — the durable
    /// record of everything that happened is still the event log, which this
    /// cannot touch. See `NoticeStore`.
    func clearNotices() {
        noticeStore.clear()
        refreshNotices()
        statusMessage = "Cleared. Your notes are untouched — this only clears the messages."
    }
}

// MARK: - Corpus integrity

extension AppStore {
    /// Checks at launch that the corpus we opened is the one the user meant,
    /// and posts a notice if it isn't.
    ///
    /// Runs on every launch rather than on a schedule: the situations it
    /// detects — an unreachable folder, a corpus left behind by a relocation —
    /// are established *by* launching, and a user who has lost their notes
    /// should not have to wait for a routine tick to be told why.
    ///
    /// Costs two newline counts over files already on disk. It is cheap because
    /// it has to be: an integrity check expensive enough to be worth skipping
    /// is one that eventually gets skipped.
    func checkCorpusHealth() {
        guard let location = corpusLocation else { return }
        let findings = CorpusHealth.check(location: location)
        guard !findings.isEmpty else { return }
        for notice in CorpusHealth.notices(for: findings) {
            _ = noticeStore.post(notice)
        }
        refreshNotices()
    }
}
