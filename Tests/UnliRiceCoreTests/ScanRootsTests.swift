import XCTest
@testable import UnliRiceCore

final class ScanRootsTests: XCTestCase {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    func testAddingAnUnrelatedFolderKeepsBoth() {
        let change = ScanRoots.adding(url("/Users/me/Desktop"), to: [url("/Users/me/Documents")])
        XCTAssertEqual(change.roots.map(\.path), ["/Users/me/Documents", "/Users/me/Desktop"])
        XCTAssertTrue(change.removed.isEmpty)
        XCTAssertTrue(change.didChange)
    }

    func testAddingAParentReplacesTheChildrenItCovers() {
        let change = ScanRoots.adding(
            url("/Users/me/Documents"),
            to: [url("/Users/me/Documents/Obsidian Vault"), url("/Users/me/Documents/Projects"), url("/Users/me/Desktop")]
        )
        // The unrelated root survives; the two nested ones are folded in.
        XCTAssertEqual(change.roots.map(\.path), ["/Users/me/Desktop", "/Users/me/Documents"])
        XCTAssertEqual(
            change.removed.map(\.path).sorted(),
            ["/Users/me/Documents/Obsidian Vault", "/Users/me/Documents/Projects"]
        )
    }

    func testAddingAChildOfAnExistingRootIsANoOp() {
        let roots = [url("/Users/me/Documents")]
        let change = ScanRoots.adding(url("/Users/me/Documents/Projects/Nuptia"), to: roots)
        XCTAssertFalse(change.didChange)
        XCTAssertEqual(change.roots.map(\.path), roots.map(\.path))
        XCTAssertEqual(change.alreadyCoveredBy?.path, "/Users/me/Documents")
    }

    func testAddingTheSameFolderTwiceIsANoOp() {
        let change = ScanRoots.adding(url("/Users/me/Documents"), to: [url("/Users/me/Documents")])
        XCTAssertFalse(change.didChange)
        XCTAssertEqual(change.roots.count, 1)
    }

    /// The bug a string-prefix check would introduce: these are unrelated
    /// folders that happen to share a prefix.
    func testSiblingWithASharedNamePrefixIsNotTreatedAsNested() {
        let change = ScanRoots.adding(url("/Users/me/Notes2"), to: [url("/Users/me/Notes")])
        XCTAssertTrue(change.didChange)
        XCTAssertTrue(change.removed.isEmpty)
        XCTAssertEqual(change.roots.count, 2)
    }

    func testTrailingSlashesAndDotSegmentsAreTheSameFolder() {
        let change = ScanRoots.adding(
            url("/Users/me/Documents/Projects/.."), to: [url("/Users/me/Documents/")]
        )
        XCTAssertFalse(change.didChange, "…/Projects/.. is /Users/me/Documents")
    }

    func testIsInsideIsStrict() {
        XCTAssertTrue(url("/a/b/c").isInside(url("/a/b")))
        XCTAssertFalse(url("/a/b").isInside(url("/a/b")), "a folder is not inside itself")
        XCTAssertFalse(url("/a/b").isInside(url("/a/b/c")))
        XCTAssertFalse(url("/a/bc").isInside(url("/a/b")))
    }
}
