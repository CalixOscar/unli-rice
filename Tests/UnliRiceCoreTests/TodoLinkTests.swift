import XCTest
@testable import UnliRiceCore

final class TodoLinkTests: XCTestCase {

    func testGoodRoutes() {
        let todoURL = URL(string: "unlirice://todo")!
        XCTAssertEqual(TodoLink.parse(todoURL), .todo)
        XCTAssertEqual(TodoLink.todo.url, todoURL)

        let uuid = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        let handoffURL = URL(string: "unlirice://handoff/\(uuid.uuidString)")!
        XCTAssertEqual(TodoLink.parse(handoffURL), .handoff(uuid))
        XCTAssertEqual(TodoLink.handoff(uuid).url, handoffURL)
    }

    func testRejectQuery() {
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://todo?query=1")!))
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://handoff/\(uuid.uuidString)?x=1")!))
    }

    func testRejectFragment() {
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://todo#frag")!))
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://handoff/\(uuid.uuidString)#section")!))
    }

    func testRejectUser() {
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://user@todo")!))
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://user:pass@handoff/\(uuid.uuidString)")!))
    }

    func testRejectPort() {
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://todo:8080")!))
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://handoff:8080/\(uuid.uuidString)")!))
    }

    func testRejectTwoPathComponents() {
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://handoff/\(uuid.uuidString)/extra")!))
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://todo/extra")!))
    }

    func testRejectNonUUID() {
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://handoff/not-a-valid-uuid")!))
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://handoff/")!))
    }

    func testRejectWrongHost() {
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://unknown")!))
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://other/123")!))
    }

    func testRejectWrongScheme() {
        XCTAssertNil(TodoLink.parse(URL(string: "https://todo")!))
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "https://handoff/\(uuid.uuidString)")!))
    }

    func testRejectPrompt() {
        let uuid = UUID()
        XCTAssertNil(TodoLink.parse(URL(string: "unlirice://prompt/\(uuid.uuidString)")!))
    }
}
