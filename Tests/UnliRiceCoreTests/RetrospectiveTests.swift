import XCTest
@testable import UnliRiceCore

final class RetrospectiveTests: XCTestCase {
    /// A fixed calendar and fixed dates, so a test that passes in July still
    /// passes in December — the same reason `RoutineSchedulerTests` pins its
    /// clock.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func note(
        _ title: String,
        created: Date,
        updated: Date? = nil,
        body: String = "",
        tags: Set<String> = [],
        sources: Set<String> = ["human"],
        creator: String? = nil,
        editors: Set<String> = [],
        archived: Bool = false,
        backlinks: Set<UUID> = []
    ) -> Note {
        var note = Note(
            id: UUID(),
            title: title,
            body: body,
            sources: sources,
            creator: creator ?? sources.sorted().first ?? "",
            editors: editors,
            createdAt: created,
            updatedAt: updated ?? created
        )
        note.tags = tags
        note.archived = archived
        note.backlinks = backlinks
        return note
    }

    // MARK: - Periods

    func testOnlyPeriodsWithNotesAreOffered() {
        let notes = [
            note("March", created: date(2026, 3, 4)),
            note("June", created: date(2026, 6, 20))
        ]
        let ids = Retrospective.availablePeriods(notes: notes, calendar: calendar).map(\.id)

        XCTAssertEqual(ids, ["2026", "2026-06", "2026-03"])
        // Nothing happened in April, so April is not on offer. An empty
        // retrospective is a worse answer than not offering one.
        XCTAssertFalse(ids.contains("2026-04"))
    }

    func testAPeriodIdIsStableAndSortable() {
        let month = RetrospectivePeriod.month(containing: date(2026, 2, 14), calendar: calendar)
        XCTAssertEqual(month?.id, "2026-02")
        XCTAssertEqual(RetrospectivePeriod.year(containing: date(2026, 2, 14), calendar: calendar)?.id, "2026")
    }

    // MARK: - The digest

    func testAMonthCountsWhatWasWrittenAndWhatWasReturnedTo() {
        let june = RetrospectivePeriod.month(containing: date(2026, 6, 1), calendar: calendar)!
        let notes = [
            note("written in june", created: date(2026, 6, 3)),
            note("also june", created: date(2026, 6, 20)),
            // Started in May, added to in June — being worked on, not started.
            note("older", created: date(2026, 5, 2), updated: date(2026, 6, 9)),
            note("untouched since may", created: date(2026, 5, 2))
        ]

        let digest = Retrospective.digest(for: june, notes: notes, calendar: calendar)
        XCTAssertEqual(digest.notesCreated, 2)
        XCTAssertEqual(digest.notesRevisited, 1)
        XCTAssertFalse(digest.isEmpty)
    }

    /// "Which projects ate your time" — read out of the `**Project:**` line the
    /// ingest pipelines already write. No new data, which is the whole premise.
    func testProjectsAreReadFromWhatIngestAlreadyWrote() {
        let body = "**Project:** `/Users/someone/Documents/Projects/Unli Rice`\n**When:** 2026-06-01"
        XCTAssertEqual(Retrospective.project(of: note("s", created: date(2026, 6, 1), body: body)), "Unli Rice")
        XCTAssertNil(Retrospective.project(of: note("hand written", created: date(2026, 6, 1))))
    }

    /// Both caught by running this over the real corpus, which is the habit this
    /// project keeps paying for: the top "project" came out as the home folder's
    /// name, and a note whose prose began "**Project:** Architecturally…" was
    /// counted as a project called "Architecturally".
    func testOnlyRealProjectPathsCount() {
        let home = "**Project:** `/Users/someone`"
        XCTAssertNil(Retrospective.project(of: note("session", created: date(2026, 6, 1), body: home)))

        let prose = "**Project:** Architecturally this was a mess"
        XCTAssertNil(Retrospective.project(of: note("essay", created: date(2026, 6, 1), body: prose)))

        let real = "**Project:** `/Users/someone/Projects/Unli Rice`"
        XCTAssertEqual(Retrospective.project(of: note("s", created: date(2026, 6, 1), body: real)), "Unli Rice")
    }

    /// The point of the section: several agents write into one corpus, and the
    /// screen should be able to say which one wrote what.
    func testContributorsAreCountedByWhoStartedTheNote() {
        let month = RetrospectivePeriod.month(containing: date(2026, 6, 1), calendar: calendar)!
        let notes = [
            note("a", created: date(2026, 6, 2), body: "one two three", sources: ["claude"]),
            note("b", created: date(2026, 6, 3), body: "four five", sources: ["claude"]),
            note("c", created: date(2026, 6, 4), sources: ["codex"])
        ]

        let contributors = Retrospective.digest(for: month, notes: notes, calendar: calendar).contributors
        XCTAssertEqual(contributors.map(\.name), ["Claude", "Codex"])
        XCTAssertEqual(contributors[0].notesCreated, 2)
        XCTAssertEqual(contributors[0].wordsWritten, 5)
        XCTAssertEqual(contributors[1].notesCreated, 1)
    }

    /// A second agent tagging or appending to a note is not its author, and a
    /// `sources` set alone cannot tell the two apart — which is why `Note`
    /// carries `creator` and `editors`.
    func testEditingSomeoneElsesNoteCountsSeparatelyFromWritingIt() {
        let month = RetrospectivePeriod.month(containing: date(2026, 6, 1), calendar: calendar)!
        let notes = [
            note("a", created: date(2026, 6, 2), sources: ["claude"], creator: "claude", editors: ["gemini"]),
            // Written before the month, worked on during it.
            note(
                "old",
                created: date(2026, 5, 2),
                updated: date(2026, 6, 9),
                sources: ["claude"],
                creator: "claude",
                editors: ["gemini"]
            )
        ]

        let contributors = Retrospective.digest(for: month, notes: notes, calendar: calendar).contributors
        let gemini = contributors.first { $0.identity == "gemini" }
        XCTAssertEqual(gemini?.notesCreated, 0)
        XCTAssertEqual(gemini?.notesTouched, 2)
        XCTAssertEqual(contributors.first { $0.identity == "claude" }?.notesCreated, 1)
        // Authorship ranks above edit volume.
        XCTAssertEqual(contributors.map(\.identity), ["claude", "gemini"])
    }

    /// Every pipeline writes under the single identity `ingest`, so crediting
    /// the raw source would name the machinery instead of the agent whose work
    /// it swept up — one anonymous row on top of the whole section.
    func testIngestedNotesAreCreditedToThePipelineThatFoundThem() {
        let month = RetrospectivePeriod.month(containing: date(2026, 6, 1), calendar: calendar)!
        let notes = [
            note("session", created: date(2026, 6, 2), tags: ["claude-session", "ingested"], sources: ["ingest"]),
            note("vault", created: date(2026, 6, 3), tags: ["obsidian-import"], sources: ["ingest"])
        ]

        let names = Retrospective.digest(for: month, notes: notes, calendar: calendar).contributors.map(\.name)
        XCTAssertEqual(Set(names), ["Claude Code sessions", "Obsidian vault"])
    }

    /// An agent nobody has heard of yet still shows up under its own name.
    func testAnUnknownAgentIsNamedRatherThanDropped() {
        XCTAssertEqual(Retrospective.contributorName(of: "new-agent"), "New Agent")
    }

    func testAYearBreaksDownByMonthIncludingTheQuietOnes() {
        let year = RetrospectivePeriod.year(containing: date(2026, 6, 1), calendar: calendar)!
        let notes = [
            note("a", created: date(2026, 2, 1)),
            note("b", created: date(2026, 2, 8)),
            note("c", created: date(2026, 9, 3))
        ]

        let digest = Retrospective.digest(for: year, notes: notes, calendar: calendar)
        XCTAssertEqual(digest.months.count, 12)
        XCTAssertEqual(digest.months.first { $0.period.id == "2026-02" }?.noteCount, 2)
        // A month with nothing in it still gets a row: the shape of a year
        // includes when you weren't working.
        XCTAssertEqual(digest.months.first { $0.period.id == "2026-04" }?.noteCount, 0)
        XCTAssertEqual(digest.busiestMonth?.period.id, "2026-02")
    }

    /// Archiving is how someone says stop showing me this. A year-in-review that
    /// resurfaced exactly what they filed away would be the app arguing with its
    /// user — the same mistake `JanitorRunner`'s untag check exists to avoid.
    func testArchivedNotesNeverAppearAsHighlights() {
        let notes = [
            note("filed away", created: date(2026, 6, 1), body: String(repeating: "x", count: 2000), archived: true),
            note("kept", created: date(2026, 6, 2))
        ]
        let june = RetrospectivePeriod.month(containing: date(2026, 6, 1), calendar: calendar)!
        let digest = Retrospective.digest(for: june, notes: notes, calendar: calendar)

        XCTAssertEqual(digest.highlights.map(\.title), ["kept"])
        // The count still reflects what was written that month.
        XCTAssertEqual(digest.notesCreated, 2)
    }

    func testTheSeededGuidesAreNotPresentedAsThingsYouWrote() {
        let notes = [
            note("Welcome to Unli Rice", created: date(2026, 6, 1), sources: [Onboarding.source]),
            note("something real", created: date(2026, 6, 2))
        ]
        XCTAssertEqual(Retrospective.highlights(among: notes, limit: 5).map(\.title), ["something real"])
    }

    /// Recognition, not volume: a note the rest of the corpus keeps pointing
    /// back at outranks a longer one nothing refers to.
    func testHighlightsRankLinkedNotesAboveLongOnes() {
        let long = note("long but isolated", created: date(2026, 6, 1), body: String(repeating: "x", count: 5000))
        let linked = note("referred to constantly", created: date(2026, 6, 1), backlinks: [UUID(), UUID()])

        XCTAssertEqual(Retrospective.highlights(among: [long, linked], limit: 1).map(\.title), ["referred to constantly"])
    }

    // MARK: - Announcing

    func testTheMonthJustEndedIsAnnouncedOnce() {
        let notes = [note("june work", created: date(2026, 6, 15))]
        let now = date(2026, 7, 2)

        let first = DigestAnnouncer.pendingAnnouncement(
            now: now, lastAnnouncedPeriodID: nil, notes: notes, calendar: calendar
        )
        XCTAssertEqual(first?.id, "2026-06")

        XCTAssertNil(
            DigestAnnouncer.pendingAnnouncement(
                now: now, lastAnnouncedPeriodID: "2026-06", notes: notes, calendar: calendar
            )
        )
    }

    /// Being told you have nothing to look back on is worse than not being told
    /// anything.
    func testAnEmptyMonthIsNotAnnounced() {
        let notes = [note("may work", created: date(2026, 5, 15))]
        XCTAssertNil(
            DigestAnnouncer.pendingAnnouncement(
                now: date(2026, 7, 2), lastAnnouncedPeriodID: nil, notes: notes, calendar: calendar
            )
        )
    }

    /// Someone who ignores the app for a year comes back to *one* notice about
    /// last month, not twelve about the year — the pile-of-chores failure this
    /// whole feature exists to avoid.
    func testAYearAwayStillOnlyProducesOneAnnouncement() {
        let notes = (1...12).map { note("m\($0)", created: date(2026, $0, 10)) }
        let period = DigestAnnouncer.pendingAnnouncement(
            now: date(2027, 1, 5), lastAnnouncedPeriodID: nil, notes: notes, calendar: calendar
        )
        XCTAssertEqual(period?.id, "2026-12")
    }
}
