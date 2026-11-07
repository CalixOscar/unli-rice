import XCTest
@testable import UnliRiceCore
final class NativeCloudProjectionTests: XCTestCase {
    func testDeclaredAncestryOverridesInputOrder() {
        let id = UUID(), date = Date()
        let create = Event(noteId: id, timestamp: date, source: "human", kind: .created, title: "A", causalParents: [])
        let tag = Event(noteId: id, timestamp: date, source: "human", kind: .tagged, tag: "capture", causalParents: [create.id])
        XCTAssertEqual(Projector.project([tag, create]), Projector.project([create, tag]))
        XCTAssertTrue(Projector.project([tag, create])[id]!.tags.contains("capture"))
    }
}
