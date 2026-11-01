import XCTest
@testable import UnliRiceCore

final class StudioOverviewFileTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func project(_ tag: String, repository: RepoSnapshotFile.Repo? = nil) -> StudioOverviewFile.Project {
        .init(id: tag, name: tag, projectTag: tag, status: String(repeating: "x", count: 2001),
              observedAt: date, repository: repository)
    }
    func testRoundTripAndEvidence() throws {
        let dir = try folder()
        let branch = RepoSnapshotFile.Branch(name: "main", sha: "abc", tipOnRemote: false, isCurrent: true)
        let repo = RepoSnapshotFile.Repo(name: "repo", currentBranch: "main", detachedHead: false,
                                         branches: [branch], remoteBranchCount: 1, worktrees: [])
        let value = StudioOverviewFile(generatedAt: date, deviceLabel: "Mac", projects: [project(" A "), project("b", repository: repo)])
        try value.write(toFolder: dir)
        let read = try StudioOverviewFile.read(fromFolder: dir)
        XCTAssertEqual(read, value)
        XCTAssertEqual(read.projects[0].projectTag, "a")
        XCTAssertEqual(read.projects[0].status?.count, 2000)
        XCTAssertNil(read.projects[0].repository)
        XCTAssertEqual(read.projects[1].repository?.branches[0].tipOnRemote, false)
        XCTAssertNil(read.projects[1].repository?.branches[0].aheadOfTrunk)
        XCTAssertTrue(read.isStale(now: date.addingTimeInterval(21601)))
    }
    func testDuplicatesAndLimits() throws {
        let dir = try folder()
        let value = StudioOverviewFile(generatedAt: date, deviceLabel: "Mac", projects: [project(" A "), project("a"), project("b")])
        XCTAssertEqual(value.projects.map(\.projectTag), ["b"])
        XCTAssertEqual(value.issues.count, 1)
        XCTAssertThrowsError(try StudioOverviewFile(version: 2, deviceLabel: "Mac", projects: []).write(toFolder: dir))
        let oversized = Data(repeating: 32, count: 2 * 1024 * 1024 + 1)
        try oversized.write(to: dir.appendingPathComponent(StudioOverviewFile.filename))
        XCTAssertThrowsError(try StudioOverviewFile.read(fromFolder: dir)) { XCTAssertEqual($0 as? StudioOverviewFile.ReadError, .oversized) }
        let many = StudioOverviewFile(deviceLabel: "Mac", projects: (0...500).map { project("\($0)") })
        XCTAssertThrowsError(try many.write(toFolder: dir)) { XCTAssertEqual($0 as? StudioOverviewFile.ReadError, .tooManyProjects) }
        try Data("{\"version\":2}".utf8).write(to: dir.appendingPathComponent(StudioOverviewFile.filename))
        XCTAssertThrowsError(try StudioOverviewFile.read(fromFolder: dir)) { XCTAssertEqual($0 as? StudioOverviewFile.ReadError, .unsupportedVersion(2)) }
    }
    func testReceiptsMatchingAndLimits() throws {
        let dir = try folder()
        let ids = (0..<2001).map { _ in UUID() }
        let receipt = CaptureReceiptFile(generatedAt: date, deviceLabel: "Mac", receivedNoteIDs: [ids[0], ids[0]] + ids)
        XCTAssertEqual(receipt.receivedNoteIDs.count, 2000)
        try receipt.write(toFolder: dir, deviceID: "../abc")
        try Data("ignored".utf8).write(to: dir.appendingPathComponent("other.json"))
        XCTAssertEqual(try CaptureReceiptFile.readAll(fromFolder: dir), [receipt])
        try Data("{\"version\":2}".utf8).write(to: dir.appendingPathComponent("capture-receipt-new.json"))
        XCTAssertThrowsError(try CaptureReceiptFile.readAll(fromFolder: dir)) { XCTAssertEqual($0 as? CaptureReceiptFile.ReadError, .unsupportedVersion(2)) }
    }
}
