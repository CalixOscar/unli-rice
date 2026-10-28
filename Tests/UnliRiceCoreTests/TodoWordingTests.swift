import XCTest
@testable import UnliRiceCore

final class TodoWordingTests: XCTestCase {

    func testAssistantNameEveryKnownSource() {
        XCTAssertEqual(TodoWording.assistantName(forSource: "claude"), "Claude")
        XCTAssertEqual(TodoWording.assistantName(forSource: "chatgpt"), "ChatGPT")
        XCTAssertEqual(TodoWording.assistantName(forSource: "gemini"), "Gemini")
        XCTAssertEqual(TodoWording.assistantName(forSource: "kimi"), "Kimi")
        XCTAssertEqual(TodoWording.assistantName(forSource: "codex"), "Codex")
        XCTAssertEqual(TodoWording.assistantName(forSource: "antigravity"), "Antigravity")
        XCTAssertEqual(TodoWording.assistantName(forSource: "human"), "you")
    }

    func testAssistantNameCaseInsensitive() {
        XCTAssertEqual(TodoWording.assistantName(forSource: "Claude"), "Claude")
        XCTAssertEqual(TodoWording.assistantName(forSource: "CHATGPT"), "ChatGPT")
        XCTAssertEqual(TodoWording.assistantName(forSource: "HUMAN"), "you")
    }

    func testAssistantNameUnknownSource() {
        XCTAssertEqual(TodoWording.assistantName(forSource: "copilot"), "Copilot")
        XCTAssertEqual(TodoWording.assistantName(forSource: "customAgent"), "CustomAgent")
    }

    func testAssistantNameEmptySource() {
        XCTAssertEqual(TodoWording.assistantName(forSource: ""), "")
    }

    func testSubtitleFixedNowAndZeroProjects() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoDaysAgo = now.addingTimeInterval(-172_800)
        let sub = TodoWording.subtitle(creator: "claude", createdAt: twoDaysAgo, projects: [], now: now)
        XCTAssertEqual(sub, "Suggested by Claude · 2 days ago · no project")
    }

    func testSubtitleOneProject() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoDaysAgo = now.addingTimeInterval(-172_800)
        let sub = TodoWording.subtitle(creator: "claude", createdAt: twoDaysAgo, projects: ["CalmdownOscar"], now: now)
        XCTAssertEqual(sub, "Suggested by Claude · 2 days ago · CalmdownOscar")
    }

    func testSubtitleTwoProjects() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoDaysAgo = now.addingTimeInterval(-172_800)
        let sub = TodoWording.subtitle(creator: "claude", createdAt: twoDaysAgo, projects: ["CalmdownOscar", "Nuptia"], now: now)
        XCTAssertEqual(sub, "Suggested by Claude · 2 days ago · CalmdownOscar, Nuptia")
    }
}
