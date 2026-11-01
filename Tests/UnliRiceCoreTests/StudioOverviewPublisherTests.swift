import XCTest
@testable import UnliRiceCore

final class StudioOverviewPublisherTests: XCTestCase {
    func testMappingAndPathRedaction() throws {
        let date = Date(timeIntervalSince1970: 1000)
        let observed = Date(timeIntervalSince1970: 500)
        let evidence = ProjectGarden.Repository(currentBranch: "main", branchCount: 1, worktreeCount: 0, differentTipCount: nil, observedAt: observed, fromPublishedSnapshot: true)
        let project = ProjectGarden.Project(id: "/secret/path", name: " Example ", repository: evidence, issues: ["Cannot read /secret/path"])
        let branch = RepoSnapshotFile.Branch(name: "main", sha: "abc", tipOnRemote: false, isCurrent: true)
        let repo = RepoSnapshotFile.Repo(name: "example", currentBranch: "main", detachedHead: false, branches: [branch], remoteBranchCount: 0, worktrees: [])
        let report = ProjectGarden.Report(projects: [project], scannedAt: date, issues: ["Could not read /secret/root"])
        let gate = BuildGate.Result(slug: nil, openPlans: [], lights: [.spec: .unknown("unavailable")], issues: [])
        let result = StudioOverviewPublisher.make(report: report, repositories: [repo], gates: ["example": gate], deviceLabel: "Mac", generatedAt: date)
        XCTAssertEqual(result.projects[0].observedAt, observed)
        XCTAssertEqual(result.projects[0].repository?.branches[0].tipOnRemote, false)
        XCTAssertEqual(result.projects[0].stages["spec"]?.state, "unknown")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("/secret"))
        let duplicates = StudioOverviewPublisher.make(report: report, repositories: [repo, repo], gates: [:], deviceLabel: "Mac")
        XCTAssertNil(duplicates.projects[0].repository)
        let missing = StudioOverviewPublisher.make(report: .init(projects: [.init(id: "x", name: "x")], scannedAt: date), repositories: [], gates: [:], deviceLabel: "Mac")
        XCTAssertNil(missing.projects[0].repository)
        XCTAssertEqual(missing.projects[0].observedAt, date)
    }
}
