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

    func testCodexIsTheOnlyTargetWeRefuseToWrite() {
        let pasteOnly = MCPTarget.builtIn.filter { !$0.supportsAutomaticWrite }.map(\.id)
        XCTAssertEqual(pasteOnly, ["codex"])
    }

    func testUserScopedTargetResolvesAgainstHome() {
        let cursor = try! XCTUnwrap(MCPTarget.builtIn.first { $0.id == "cursor" })
        let url = cursor.configURL(
            projectFolder: nil, homeDirectory: URL(fileURLWithPath: "/Users/x")
        )
        XCTAssertEqual(url?.path, "/Users/x/.cursor/mcp.json")
    }

    /// Claude Code and Antigravity both scope MCP servers per project, so there
    /// is no correct path to guess. Returning nil is what blocks "Connect" until
    /// the user says which project they mean.
    func testProjectScopedTargetHasNoPathUntilAFolderIsChosen() throws {
        let claudeCode = try XCTUnwrap(MCPTarget.builtIn.first { $0.id == "claude-code" })
        XCTAssertTrue(claudeCode.requiresProjectFolder)
        XCTAssertNil(claudeCode.configURL(projectFolder: nil))

        let resolved = claudeCode.configURL(projectFolder: URL(fileURLWithPath: "/Users/x/Proj"))
        XCTAssertEqual(resolved?.path, "/Users/x/Proj/.mcp.json")
    }

    func testAntigravityUsesTheAgentsPathThisRepoAlreadyUses() throws {
        let antigravity = try XCTUnwrap(MCPTarget.builtIn.first { $0.id == "antigravity" })
        let url = antigravity.configURL(projectFolder: URL(fileURLWithPath: "/p"))
        XCTAssertEqual(url?.path, "/p/.agents/mcp_config.json")
    }

    /// Format is inferred from the extension because it's the only signal
    /// available for a tool we haven't verified.
    func testCustomTargetInfersFormatFromExtension() {
        let toml = MCPTarget.custom(name: "Grok", fileURL: URL(fileURLWithPath: "/x/config.toml"))
        XCTAssertEqual(toml.format, .codexTOML)
        XCTAssertFalse(toml.supportsAutomaticWrite)

        let json = MCPTarget.custom(name: "OpenCode", fileURL: URL(fileURLWithPath: "/x/opencode.json"))
        XCTAssertEqual(json.format, .mcpServersJSON)
        XCTAssertTrue(json.supportsAutomaticWrite)
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
}
