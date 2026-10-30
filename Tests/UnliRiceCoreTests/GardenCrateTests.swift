import XCTest
@testable import UnliRiceCore

final class GardenCrateTests: XCTestCase {
    func testIssuesMeanCantRead() {
        let project = ProjectGarden.Project(id: "one", name: "One", issues: ["could not read"])
        XCTAssertEqual(GardenCrate.state(of: project), .cantRead("could not read"))
    }

    func testAttentionMeansNeedsYou() {
        let note = Note(id: UUID(), title: "todo", body: "", tags: ["todo"], createdAt: .now, updatedAt: .now)
        let project = ProjectGarden.Project(id: "one", name: "One", notes: [note])
        XCTAssertEqual(GardenCrate.state(of: project), .needsYou)
    }

    func testNoStatusNoRepoIsNoStatus() {
        let project = ProjectGarden.Project(id: "one", name: "One")
        XCTAssertEqual(GardenCrate.state(of: project), .noStatus)
    }

    func testRepoWithoutMemoryIsFine() {
        let repository = ProjectGarden.Repository(currentBranch: "main", branchCount: 1, worktreeCount: 1,
                                                  differentTipCount: nil, observedAt: .now, fromPublishedSnapshot: false)
        let project = ProjectGarden.Project(id: "one", name: "One", repository: repository)
        XCTAssertEqual(GardenCrate.state(of: project), .fine)
    }

    func testOrderNewestFirstNilLastByName() {
        let old = Date(timeIntervalSince1970: 100)
        let newest = Date(timeIntervalSince1970: 200)
        let projects = [
            ProjectGarden.Project(id: "a", name: "zeta", statusDate: old),
            ProjectGarden.Project(id: "b", name: "Alpha"),
            ProjectGarden.Project(id: "c", name: "beta"),
            ProjectGarden.Project(id: "d", name: "new", statusDate: newest)
        ]
        let sleeves = GardenCrate.sleeves(from: ProjectGarden.Report(projects: projects, scannedAt: newest))
        XCTAssertEqual(sleeves.map(\.name), ["new", "zeta", "Alpha", "beta"])
    }

    func testSubtitleFallbackAndTruncation() {
        let long = String(repeating: "x", count: 60) + "tail"
        let projects = [
            ProjectGarden.Project(id: "one", name: "One", status: "status\nsecond"),
            ProjectGarden.Project(id: "two", name: "Two", nextStep: long),
            ProjectGarden.Project(id: "three", name: "Three")
        ]
        let sleeves = GardenCrate.sleeves(from: ProjectGarden.Report(projects: projects, scannedAt: .now))
        XCTAssertEqual(sleeves.first(where: { $0.name == "One" })?.subtitle, "status")
        XCTAssertEqual(sleeves.first(where: { $0.name == "Two" })?.subtitle, String(repeating: "x", count: 59) + "…")
        XCTAssertEqual(sleeves.first(where: { $0.name == "Three" })?.subtitle, "No notes yet")
    }

    func testStableIndexIsStable() {
        XCTAssertEqual(GardenCrate.stableIndex("folder:/Projects/Unli Rice", modulo: 8),
                       GardenCrate.stableIndex("folder:/Projects/Unli Rice", modulo: 8))
        XCTAssertGreaterThanOrEqual(GardenCrate.stableIndex("anything", modulo: 8), 0)
        XCTAssertLessThan(GardenCrate.stableIndex("anything", modulo: 8), 8)
    }
}
