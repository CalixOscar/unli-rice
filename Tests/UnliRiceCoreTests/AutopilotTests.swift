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

    // MARK: - Enclosing project detection

    /// The regression this predicate exists for: an Xcode-only app has no
    /// `Package.swift`, so `packageRoot` reported "no project" while the
    /// assistant was working inside one.
    func testEnclosingProjectRootFindsAnXcodeProjectWithNoPackageSwift() {
        let root = URL(fileURLWithPath: "/Users/x/Projects/MyApp")
        let start = root.appendingPathComponent("MyApp/Views")

        let found = Autopilot.enclosingProjectRoot(
            startingAt: start,
            fileExists: { _ in false },
            contentsOfDirectory: { $0.path == root.path ? ["MyApp.xcodeproj", "README.md"] : [] }
        )

        XCTAssertEqual(found?.path, root.path)
        XCTAssertNil(Autopilot.packageRoot(startingAt: start) { _ in false })
    }

    /// A bare git checkout of a non-Swift codebase counts too.
    func testEnclosingProjectRootFindsABareGitDirectory() {
        let root = URL(fileURLWithPath: "/Users/x/Projects/scripts")
        let start = root.appendingPathComponent("lib/util")

        let found = Autopilot.enclosingProjectRoot(
            startingAt: start,
            fileExists: { $0.path == root.appendingPathComponent(".git").path },
            contentsOfDirectory: { _ in [] }
        )

        XCTAssertEqual(found?.path, root.path)
    }

    func testEnclosingProjectRootAcceptsAnXcworkspace() {
        let root = URL(fileURLWithPath: "/Users/x/Projects/Workspace")

        let found = Autopilot.enclosingProjectRoot(
            startingAt: root,
            fileExists: { _ in false },
            contentsOfDirectory: { $0.path == root.path ? ["Workspace.xcworkspace"] : [] }
        )

        XCTAssertEqual(found?.path, root.path)
    }

    /// Every non-Swift marker should stand on its own, so a Python or Go tree
    /// with no git dir is still a project.
    func testEnclosingProjectRootAcceptsEachNonSwiftMarker() {
        for marker in ["package.json", "pyproject.toml", "Cargo.toml", "go.mod", "CLAUDE.md"] {
            let root = URL(fileURLWithPath: "/Users/x/Projects/thing")
            let found = Autopilot.enclosingProjectRoot(
                startingAt: root.appendingPathComponent("src"),
                fileExists: { $0.path == root.appendingPathComponent(marker).path },
                contentsOfDirectory: { _ in [] }
            )
            XCTAssertEqual(found?.path, root.path, "expected \(marker) to mark a project root")
        }
    }

    /// A loose folder in Documents is genuinely not a project — the "no project"
    /// branch still has to be reachable, or the fix would just always say yes.
    func testEnclosingProjectRootIsNilOutsideAnyProject() {
        XCTAssertNil(
            Autopilot.enclosingProjectRoot(
                startingAt: URL(fileURLWithPath: "/Users/x/Documents/loose notes"),
                fileExists: { _ in false },
                contentsOfDirectory: { _ in [] }
            )
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
        XCTAssertTrue(body.contains("search_notes"))
        XCTAssertTrue(body.contains("Wiki: index"))
        XCTAssertTrue(body.contains("append_to_note"))
        XCTAssertTrue(body.contains("source"))
        XCTAssertTrue(body.contains("janitor"))
        XCTAssertTrue(body.contains("ingest"))
        XCTAssertTrue(body.contains("flag_for_review"))
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
