import Foundation
import UnliRiceCore

/// The look-back screen.
///
/// Every ingredient for this was already in the corpus and going unused: each
/// note is stamped with when it happened, what wrote it, which project it came
/// from, and what links to it. `Retrospective` is a pure function over exactly
/// that — no new data, no new capture step, nothing to keep up to date.
extension AppStore {
    /// Months and years the corpus actually has something to say about, newest
    /// first. Never offers an empty period.
    var retrospectivePeriods: [RetrospectivePeriod] {
        Retrospective.availablePeriods(notes: notes + archivedNotes)
    }

    /// The period on screen: whichever the user picked, else the most recent
    /// month with anything in it.
    ///
    /// Defaults to a *month* rather than the current year because a month is
    /// the unit that finishes. The year is one click away and is the thing
    /// you'd open in December.
    var currentRetrospectivePeriod: RetrospectivePeriod? {
        let periods = retrospectivePeriods
        if let id = retrospectivePeriodID, let match = periods.first(where: { $0.id == id }) {
            return match
        }
        return periods.first { $0.span == .month } ?? periods.first
    }

    var retrospectiveDigest: RetrospectiveDigest? {
        guard let period = currentRetrospectivePeriod else { return nil }
        // Archived notes are included in the corpus handed over, and
        // `Retrospective.highlights` filters them back out of the highlights
        // themselves — a month's *count* should still reflect what you wrote
        // then, even if you've since filed some of it away.
        return Retrospective.digest(for: period, notes: notes + archivedNotes)
    }

    func showRetrospective(periodID: String? = nil) {
        selectNote(nil)
        closeAllPanes()
        if let periodID { retrospectivePeriodID = periodID }
        showingRetrospective = true
        statusMessage = currentRetrospectivePeriod.map {
            "Looking back on \($0.displayName())."
        } ?? "Nothing to look back on yet — this fills in as you use it."
    }

    func selectRetrospective(_ period: RetrospectivePeriod) {
        retrospectivePeriodID = period.id
        statusMessage = "Looking back on \(period.displayName())."
    }

    /// The note behind a highlight, opened for real reading.
    func openHighlight(_ note: Note) {
        selectNote(note.id)
    }
}
