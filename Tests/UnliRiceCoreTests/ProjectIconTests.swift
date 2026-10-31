import Foundation
import XCTest
@testable import UnliRiceCore

final class ProjectIconTests: XCTestCase {
    private func resolved(_ url: URL?) -> String? {
        url.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }
    }

    private func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @discardableResult
    private func file(_ path: String, in root: URL, width: UInt32 = 64) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        func bytes(_ value: UInt32) -> [UInt8] {
            [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        let data = Data([137, 80, 78, 71, 13, 10, 26, 10] + bytes(13) + [73, 72, 68, 82] + bytes(width) + bytes(width))
        try data.write(to: url)
        return url
    }

    func testNoIconReturnsNil() throws {
        try fixture { root in
            try file("readme.txt", in: root)
            XCTAssertNil(ProjectIcon.find(in: root))
        }
    }

    func testAppIconSetBeatsShallowerLogo() throws {
        try fixture { root in
            try file("logo.png", in: root)
            let icon = try file("App/Assets.xcassets/AppIcon.appiconset/a.png", in: root)
            XCTAssertEqual(resolved(ProjectIcon.find(in: root)), resolved(icon))
        }
    }

    func testWidestAppIconPNGWins() throws {
        try fixture { root in
            try file("AppIcon.appiconset/small.png", in: root, width: 64)
            let icon = try file("AppIcon.appiconset/large.png", in: root, width: 1024)
            XCTAssertEqual(resolved(ProjectIcon.find(in: root)), resolved(icon))
        }
    }

    func testSkipsHiddenAndBuildFolders() throws {
        try fixture { root in
            for path in [".git/icon.png", "node_modules/icon.png", "build/icon.png"] { try file(path, in: root) }
            XCTAssertNil(ProjectIcon.find(in: root))
        }
    }

    func testShallowerWinsWithinARank() throws {
        try fixture { root in
            let icon = try file("logo.png", in: root)
            try file("a/b/logo.png", in: root)
            XCTAssertEqual(resolved(ProjectIcon.find(in: root)), resolved(icon))
        }
    }

    func testRespectsMaxDepth() throws {
        try fixture { root in
            try file("a/b/c/d/e/f/icon.png", in: root)
            XCTAssertNil(ProjectIcon.find(in: root))
            let icon = try file("a/b/c/d/e/icon.png", in: root)
            XCTAssertEqual(resolved(ProjectIcon.find(in: root)), resolved(icon))
        }
    }
}
