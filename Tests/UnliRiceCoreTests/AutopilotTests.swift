import XCTest
@testable import UnliRiceCore

final class AutopilotTests: XCTestCase {
    // MARK: - Target catalog

    /// Every built-in ships only because its format was confirmed against a real
    /// config file or this repo's own configs. If this count changes, something
    /// was added — check it was verified, not remembered.
    func testCatalogHoldsOnlyVerifiedTargets() {
        let ids = MCPTarget.builtIn.map(\.id)
        XCTAssertEqual(ids, ["claude-code", "claude-desktop", "cursor", "antigravity", "codex"])
    }

    /// Format is inferred from the extension because it's the only signal
    /// available for a tool we haven't verified.
    func testCustomTargetInfersFormatFromExtension() {
        let toml = MCPTarget.custom(name: "Grok", fileURL: URL(fileURLWithPath: "/x/config.toml"))
        XCTAssertEqual(toml.format, .codexTOML)

        let json = MCPTarget.custom(name: "OpenCode", fileURL: URL(fileURLWithPath: "/x/opencode.json"))
        XCTAssertEqual(json.format, .mcpServersJSON)
    }

    // MARK: - The server entry

    func testEntryUsesThePackagePathAndOmitsEnvByDefault() {
        let entry = MCPServerEntry.forPackage(at: URL(fileURLWithPath: "/Users/x/Unli Rice"))
        XCTAssertEqual(entry.command, "swift")
        XCTAssertEqual(
            entry.args, ["run", "--package-path", "/Users/x/Unli Rice", "--quiet", "unlirice-mcp"]
        )
        XCTAssertTrue(entry.env.isEmpty)
    }

    func testEntryFallsBackToAVisiblePlaceholderPath() {
        let entry = MCPServerEntry.forPackage(at: nil)
        XCTAssertTrue(entry.args.contains(Autopilot.packagePathPlaceholder))
    }

    func testInstalledEntryRunsTheBundledHelperWithoutSwift() {
        let entry = MCPServerEntry.forInstalledApp(
            at: URL(fileURLWithPath: "/Applications/Unli Rice.app")
        )
        XCTAssertEqual(
            entry.command,
            "/Applications/Unli Rice.app/Contents/MacOS/unlirice-mcp"
        )
        XCTAssertTrue(entry.args.isEmpty)
        XCTAssertTrue(entry.env.isEmpty)
    }

    // MARK: - Package path detection

    func testPackageRootFoundByWalkingUpwards() {
        let root = URL(fileURLWithPath: "/Users/x/Projects/Unli Rice")
        // The real build output is a bare executable in .build/xcode/..., which
        // is why the walk has to go this many levels.
        let start = root.appendingPathComponent(".build/xcode/Build/Products/Debug")

        let found = Autopilot.packageRoot(startingAt: start) {
            $0.path == root.appendingPathComponent("Package.swift").path
        }

        XCTAssertEqual(found?.path, root.path)
    }

    func testPackageRootIsNilWhenNothingMatches() {
        XCTAssertNil(
            Autopilot.packageRoot(startingAt: URL(fileURLWithPath: "/Applications/X.app")) { _ in false }
        )
    }

    // MARK: - The house-rules note

    /// Titles are permanent and wiki-links resolve by exact title, so a repeat
    /// run must not create a second note with the same name. Get Started is
    /// reachable from the sidebar at any time, so this is a normal path.
    func testNoteTitleAvoidsCollisions() {
        XCTAssertEqual(Autopilot.noteTitle(existingTitles: []), "How to use these notes")
        XCTAssertEqual(
            Autopilot.noteTitle(existingTitles: ["How to use these notes"]),
            "How to use these notes 2"
        )
        XCTAssertEqual(
            Autopilot.noteTitle(existingTitles: ["how to use these notes", "How to use these notes 2"]),
            "How to use these notes 3"
        )
    }

    /// The note is what closes the loop: it's the first thing a connected tool
    /// finds when it calls `list_notes`, and it has to state the habit and the
    /// two hard rules an agent could otherwise violate.
    func testNoteBodyStatesTheHabitAndTheHardRules() {
        let body = Autopilot.noteBody
        XCTAssertTrue(body.contains("list_notes"))
        XCTAssertTrue(body.contains("append_to_note"))
        XCTAssertTrue(body.contains("source"))
        XCTAssertTrue(body.contains("janitor"))
        XCTAssertTrue(body.contains("archive_note"))
        XCTAssertTrue(body.contains("Titles are permanent"))
    }

    func testAgentSourceForTargets() throws {
        let claudeCode = try XCTUnwrap(MCPTarget.builtIn.first { $0.id == "claude-code" })
        XCTAssertEqual(claudeCode.agentSource, "claude")

        let cursor = try XCTUnwrap(MCPTarget.builtIn.first { $0.id == "cursor" })
        XCTAssertEqual(cursor.agentSource, "cursor")

        let antigravity = try XCTUnwrap(MCPTarget.builtIn.first { $0.id == "antigravity" })
        XCTAssertEqual(antigravity.agentSource, "antigravity")

        let codex = try XCTUnwrap(MCPTarget.builtIn.first { $0.id == "codex" })
        XCTAssertEqual(codex.agentSource, "codex")

        let customTarget = MCPTarget.custom(name: "Super-Agent AI 123!", fileURL: URL(fileURLWithPath: "/x/config.json"))
        XCTAssertEqual(customTarget.agentSource, "super-agent-ai-123")

        let emptyTarget = MCPTarget.custom(name: "!!!", fileURL: URL(fileURLWithPath: "/x/config.json"))
        XCTAssertEqual(emptyTarget.agentSource, "assistant")
    }
}
