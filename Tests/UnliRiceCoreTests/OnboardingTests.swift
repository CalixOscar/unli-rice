import XCTest
@testable import UnliRiceCore

final class OnboardingTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-onboarding-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    private func fakeFlag() -> (get: () -> Bool, set: () -> Void) {
        var seeded = false
        return ({ seeded }, { seeded = true })
    }

    func testSeedsTwoNotesOnAGenuinelyEmptyCorpus() throws {
        let flag = fakeFlag()
        let didSeed = try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)

        XCTAssertTrue(didSeed)
        let notes = try service.listNotes(includeArchived: true)
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.allSatisfy { $0.sources == ["unlirice"] })
    }

    /// The whole point: two notes sharing a tag gives the janitor's cosmetic
    /// rule exactly the usage count it requires (`minimumTagCorpusUse == 2` at
    /// Eco/Balanced) — otherwise a fresh corpus can never demonstrate the
    /// feature no matter what the user writes.
    func testSeedNotesShareATagAtJanitorsMinimumUsageThreshold() throws {
        let flag = fakeFlag()
        try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)

        let notes = try service.listNotes(includeArchived: true)
        XCTAssertTrue(notes.allSatisfy { $0.tags.contains(Onboarding.seedTag) })

        let usage = notes.filter { $0.tags.contains(Onboarding.seedTag) }.count
        XCTAssertGreaterThanOrEqual(usage, JanitorConfig(autonomy: .balanced).minimumTagCorpusUse)
    }

    func testDoesNotReseedOnSecondLaunch() throws {
        let flag = fakeFlag()
        try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)
        let secondRun = try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)

        XCTAssertFalse(secondRun)
        XCTAssertEqual(try service.listNotes(includeArchived: true).count, 2)
    }

    /// A user who archives both welcome notes should not get them reinjected —
    /// this is a one-time seed, not a standing invariant the app re-enforces.
    func testArchivingSeedNotesDoesNotTriggerReseed() throws {
        let flag = fakeFlag()
        try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)
        for note in try service.listNotes(includeArchived: true) {
            _ = try service.archiveNote(id: note.id, reason: "cleared for a fresh start", source: "human")
        }

        let reseeded = try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)
        XCTAssertFalse(reseeded)
    }

    /// A migrated legacy log (or any corpus a human/agent already populated)
    /// must never be touched — `hasSeeded` being false is not sufficient on its
    /// own, the corpus also has to be empty.
    func testNeverSeedsIntoAnExistingCorpus() throws {
        _ = try service.createNote(title: "Pre-existing note", body: "real user data", source: "claude")
        let flag = fakeFlag()

        let didSeed = try Onboarding.seedIfNeeded(service: service, hasSeeded: flag.get, markSeeded: flag.set)

        XCTAssertFalse(didSeed)
        XCTAssertEqual(try service.listNotes(includeArchived: true).count, 1)
    }
}
