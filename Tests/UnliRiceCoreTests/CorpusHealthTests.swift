import XCTest
@testable import UnliRiceCore

/// The check that would have caught the 2026-07 fork on the next launch instead
/// of a month later: a previous default location holding notes that the log
/// currently open has never seen.
final class CorpusHealthTests: XCTestCase {
    private let openLog = URL(fileURLWithPath: "/group/Unli Rice/events.jsonl")
    private let strandedLog = URL(fileURLWithPath: "/support/Unli Rice/events.jsonl")
    private let preRename = URL(fileURLWithPath: "/support/SecondBrain/events.jsonl")

    private func onDefault() -> CorpusLocation {
        CorpusLocation(url: openLog, source: .defaultLocation)
    }

    func testNotesPresentOnlyInAnOlderLogAreReported() {
        let ids = [openLog: Set(["a", "b"]), strandedLog: Set(["c", "d", "e"])]
        let findings = CorpusHealth.check(
            location: onDefault(), candidates: [strandedLog], noteIDs: { ids[$0] }
        )
        XCTAssertEqual(findings, [.strandedCorpus(path: "/support/Unli Rice", missingNotes: 3)])
    }

    /// The case a size comparison gets wrong. After a large ingest the live log
    /// dwarfs the stranded one while every stranded note is still missing from
    /// it — counting events would call this healthy.
    func testABiggerOpenLogDoesNotHideNotesItHasNeverSeen() {
        let ids = [openLog: Set((1...1000).map(String.init)), strandedLog: Set(["x", "y"])]
        let findings = CorpusHealth.check(
            location: onDefault(), candidates: [strandedLog], noteIDs: { ids[$0] }
        )
        XCTAssertEqual(findings, [.strandedCorpus(path: "/support/Unli Rice", missingNotes: 2)])
    }

    /// A predecessor whose notes were all carried across is not news.
    func testAFullyAdoptedOlderLogIsSilent() {
        let ids = [openLog: Set(["a", "b", "c"]), strandedLog: Set(["a", "b"])]
        let findings = CorpusHealth.check(
            location: onDefault(), candidates: [strandedLog], noteIDs: { ids[$0] }
        )
        XCTAssertTrue(findings.isEmpty, "every note is already in the open corpus")
    }

    func testTheLogWithTheMostMissingNotesWins() {
        let ids = [
            openLog: Set(["a"]),
            strandedLog: Set(["b", "c", "d"]),
            preRename: Set(["e"])
        ]
        let findings = CorpusHealth.check(
            location: onDefault(), candidates: [preRename, strandedLog], noteIDs: { ids[$0] }
        )
        XCTAssertEqual(findings, [.strandedCorpus(path: "/support/Unli Rice", missingNotes: 3)])
    }

    func testTheOpenLogIsNeverReportedAsStrandedFromItself() {
        let ids = [openLog: Set(["a", "b"])]
        let findings = CorpusHealth.check(
            location: onDefault(), candidates: [openLog], noteIDs: { ids[$0] }
        )
        XCTAssertTrue(findings.isEmpty)
    }

    /// A folder the user picked is *supposed* to differ from whatever sits in
    /// the app's own directory. Nagging about that trains the alert away.
    func testAChosenFolderIsNotComparedAgainstPreviousDefaults() {
        let chosen = URL(fileURLWithPath: "/Users/x/My Notes", isDirectory: true)
        let location = CorpusLocation(
            url: chosen.appendingPathComponent("events.jsonl"),
            source: .chosenFolder(chosen),
            scopedFolder: chosen
        )
        let findings = CorpusHealth.check(
            location: location,
            candidates: [strandedLog],
            noteIDs: { _ in Set(["only", "in", "the", "old", "one"]) }
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testAnUnavailableChosenFolderIsReported() {
        let location = CorpusLocation(
            url: openLog,
            source: .defaultAfterFolderFailed(.unresolvable(path: "/Volumes/Stick/Notes"))
        )
        let findings = CorpusHealth.check(
            location: location, candidates: [], noteIDs: { _ in nil }
        )
        XCTAssertEqual(findings, [.chosenFolderUnavailable(.unresolvable(path: "/Volumes/Stick/Notes"))])
    }

    /// Both problems at once — an unreachable folder *and* a stranded log — has
    /// to surface both, because they have different fixes.
    func testBothProblemsSurfaceTogether() {
        let location = CorpusLocation(
            url: openLog,
            source: .defaultAfterFolderFailed(.noBookmark(path: "/Users/x/My Notes"))
        )
        let ids = [openLog: Set(["a"]), strandedLog: Set(["b", "c"])]
        let findings = CorpusHealth.check(
            location: location, candidates: [strandedLog], noteIDs: { ids[$0] }
        )
        XCTAssertEqual(findings.count, 2)
    }

    // MARK: - What the user actually reads

    func testEveryFindingBecomesAProblemNoticeThatNamesTheFolder() {
        let findings: [CorpusHealth.Finding] = [
            .chosenFolderUnavailable(.unresolvable(path: "/Volumes/Stick/Notes")),
            .strandedCorpus(path: "/support/Unli Rice", missingNotes: 235)
        ]
        let notices = CorpusHealth.notices(for: findings)

        XCTAssertEqual(notices.count, 2)
        XCTAssertTrue(notices.allSatisfy { $0.kind == .problem })
        XCTAssertTrue(notices.allSatisfy { $0.destination == .notesFolder })
        XCTAssertTrue(notices[0].detail.contains("/Volumes/Stick/Notes"))
        XCTAssertTrue(notices[1].detail.contains("/support/Unli Rice"))
        // The line that stops notes piling up in the wrong corpus.
        XCTAssertTrue(notices[0].detail.contains("saved in the wrong place"))
        // Reassurance first: nothing was destroyed.
        XCTAssertTrue(notices[1].detail.contains("Nothing has been moved"))
    }

    /// Keyed by situation, not by occurrence — a flapping network volume must
    /// not stack a new notice on every launch.
    func testRepeatedFailuresCollapseOntoOneNotice() {
        let first = NoticeFactory.notesFolderUnavailable(.unresolvable(path: "/a"))
        let second = NoticeFactory.notesFolderUnavailable(.accessRefused(path: "/b"))
        XCTAssertEqual(first.key, second.key)
    }
}
