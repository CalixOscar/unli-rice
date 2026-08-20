import Foundation

/// The only notices this app knows how to write.
///
/// Kept in one place, and kept few, because the point of the notification centre
/// is that opening it is worth doing. Every entry here had to answer "would you
/// want to be told this in six months' time" — which is why there is no "ingest
/// found nothing" and no "scan complete".
public enum NoticeFactory {
    /// Something is waiting for a human decision.
    ///
    /// One notice for the whole queue, not one per flag: the queue is a single
    /// thing you either look at or don't, and the janitor's per-run budgets
    /// already exist to stop it burying anyone. Keyed so it updates in place as
    /// the count changes rather than stacking.
    public static func reviewQueue(pendingCount: Int, clusterCount: Int) -> Notice? {
        guard pendingCount > 0 else { return nil }
        let things = clusterCount > 0 ? clusterCount : pendingCount
        return Notice(
            kind: .review,
            key: "review-queue",
            title: things == 1 ? "One thing needs your OK" : "\(things) things need your OK",
            detail: "The janitor found things it isn't allowed to decide on its own. Nothing has been changed.",
            destination: .reviewQueue
        )
    }

    /// A routine did something while nobody was watching.
    ///
    /// Only posted when the run actually changed the corpus. A routine that ran
    /// and found nothing is the system working correctly and is not news.
    public static func routineRan(kind: RoutineKind, summary: String, at date: Date = Date()) -> Notice {
        Notice(
            timestamp: date,
            kind: .routine,
            // Keyed per routine, so a week of quiet Tuesday ingests collapses to
            // one line saying what the latest one did.
            key: "routine-\(kind.rawValue)",
            title: "\(kind.displayName) ran on its own",
            detail: summary,
            destination: .none
        )
    }

    /// Something failed unattended.
    ///
    /// Deliberately never collapsed with the success notice above: a pipeline
    /// that quietly stops while still looking maintained is the failure this
    /// design is most afraid of, so a failure gets its own line and its own key.
    public static func routineFailed(kind: RoutineKind, reason: String, at date: Date = Date()) -> Notice {
        Notice(
            timestamp: date,
            kind: .problem,
            key: "routine-failed-\(kind.rawValue)",
            title: "\(kind.displayName) couldn't finish",
            detail: reason,
            destination: .none
        )
    }

    public static func retrospective(_ period: RetrospectivePeriod, noteCount: Int, calendar: Calendar = .current) -> Notice {
        Notice(
            kind: .retrospective,
            key: "retrospective-\(period.id)",
            title: "\(period.displayName(calendar: calendar)) is ready to look back on",
            detail: "\(noteCount) note\(noteCount == 1 ? "" : "s") from that \(period.span == .year ? "year" : "month").",
            destination: .retrospective(period: period.id)
        )
    }

    /// Notice raised when `Memory: capsule` exceeds the 2,500 character ceiling.
    public static func memoryCapsuleExceeded(length: Int) -> Notice {
        Notice(
            kind: .problem,
            key: "memory-capsule-size",
            title: "Memory capsule is too long (\(length) chars)",
            detail: "The `Memory: capsule` note is \(length) characters, exceeding the 2,500 character target for cold-start LLMs. Ask your assistant to condense it.",
            destination: .none
        )
    }

    /// Notice raised when the raw/ data store becomes large.
    public static func rawStoreSize(sizeBytes: Int, fileCount: Int) -> Notice {
        let mb = sizeBytes / (1024 * 1024)
        return Notice(
            kind: .routine,
            key: "raw-store-size",
            title: "Raw store health check (\(mb) MB)",
            detail: "\(fileCount) raw files collected (\(mb) MB). Derivations remain intact and safe.",
            destination: .none
        )
    }

    /// Notice raised when foreign shard captures arrive and are imported.
    public static func capturesArrived(count: Int, at date: Date = Date()) -> Notice {
        Notice(
            timestamp: date,
            kind: .routine,
            key: "captures-arrived",
            title: count == 1 ? "New capture arrived" : "\(count) new captures arrived",
            detail: "\(count) event\(count == 1 ? "" : "s") imported from foreign shard.",
            destination: .none
        )
    }
}

/// Decides when a period is worth announcing.
///
/// Pure, and separate from the routine scheduler on purpose. A routine *does
/// work to the corpus*; this only leaves a message. PROJECT_NOTES.md records the
/// decision not to add a third routine for human review — "a routine is
/// something this app makes happen, and it cannot make a person look at a
/// queue" — and that still holds. This is the other half of that thought: if the
/// app can't make you look, the least it can do is pick a moment worth
/// mentioning it, once, and then be quiet.
public enum DigestAnnouncer {
    /// The period to announce now, or nil.
    ///
    /// Announces the month *just ended*, never the one in progress — a
    /// retrospective on an unfinished month is a status bar, not a memory. Skips
    /// a month with nothing in it: being told you have nothing to look back on
    /// is worse than not being told anything.
    public static func pendingAnnouncement(
        now: Date = Date(),
        lastAnnouncedPeriodID: String?,
        notes: [Note],
        calendar: Calendar = .current
    ) -> RetrospectivePeriod? {
        guard let month = RetrospectivePeriod.previousMonth(before: now, calendar: calendar) else { return nil }
        guard month.id != lastAnnouncedPeriodID else { return nil }
        guard notes.contains(where: { month.contains($0.createdAt) }) else { return nil }
        return month
    }
}

// MARK: - Corpus integrity
//
// These two are the loudest notices the app can post, and the reason is
// historical: the system once ran for a month on the wrong event log and had no
// way to say so. A corpus problem is not "news you might like" — it is the app
// telling you it may be writing your notes somewhere you didn't ask for.

extension NoticeFactory {
    /// The user picked a notes folder and the app couldn't open it.
    ///
    /// Written for someone who has just opened the app and found it empty, so
    /// it leads with reassurance — the notes still exist — before the fix. The
    /// warning not to write is the important line: notes added now go into the
    /// default corpus and have to be merged back by hand later.
    public static func notesFolderUnavailable(_ failure: CorpusLocation.FolderFailure) -> Notice {
        let named = failure.path.map { " (\($0))" } ?? ""
        return Notice(
            kind: .problem,
            // Not keyed per-path: it is one situation — "we aren't on your
            // folder" — and a flapping network volume shouldn't stack notices.
            key: "notes-folder-unavailable",
            title: "Your notes folder isn't available",
            detail: """
                \(failure.plainReason) Your notes\(named) are safe — Unli Rice hasn't changed \
                or deleted anything, it just can't reach them right now, so it's showing its own \
                notes instead.

                Reconnect the folder to get them back. Until you do, anything you add will be \
                saved in the wrong place.
                """,
            destination: .notesFolder
        )
    }

    /// A previous default location holds more notes than the open one.
    ///
    /// Phrased as an observation with no recommended action, on purpose. Two
    /// corpora is a situation only the user can adjudicate, and merging them is
    /// a structural change this app proposes rather than performs.
    public static func strandedCorpus(path: String, missingNotes: Int) -> Notice {
        let count = missingNotes == 1 ? "1 note" : "\(missingNotes) notes"
        return Notice(
            kind: .problem,
            key: "stranded-corpus",
            title: "Found notes in an older location",
            detail: """
                There are \(count) at \(path) that aren't in the set Unli Rice has open now.

                That usually means an update moved where notes are kept and left some behind. \
                Nothing has been moved, merged, or deleted — both sets are still on your Mac. \
                Open the older folder to look through it before deciding what to keep.
                """,
            destination: .notesFolder
        )
    }
}
