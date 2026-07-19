import XCTest
@testable import UnliRiceCore

/// This is the only code in the app that edits a file the user owns and this
/// app did not create, so the tests here are mostly about what it *refuses* to
/// do.
final class MCPConfigWriterTests: XCTestCase {
    private var directory: URL!
    private let entry = MCPServerEntry(
        command: "swift",
        args: ["run", "--package-path", "/Users/x/Unli Rice", "--quiet", "unlirice-mcp"]
    )

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-mcp-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ json: String, to name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: - Creating

    func testCreatesConfigAndMissingDirectories() throws {
        let url = directory
            .appendingPathComponent("nested/deeper")
            .appendingPathComponent("mcp.json")

        let outcome = try MCPConfigWriter.merge(entry: entry, intoJSONAt: url)

        XCTAssertEqual(outcome, .created(url))
        let servers = try XCTUnwrap(read(url)["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["unlirice"])
    }

    // MARK: - Merging

    /// The real `claude_desktop_config.json` on a working machine carries
    /// `coworkUserFilesPath` and `preferences` alongside `mcpServers`, and
    /// `mcpServers` itself holds other servers. Losing any of it would break
    /// tooling the user relies on.
    func testMergePreservesUnrelatedKeysAndOtherServers() throws {
        let url = try write("""
        {
          "coworkUserFilesPath": "/Users/x/files",
          "preferences": { "theme": "dark" },
          "mcpServers": {
            "Roblox_Studio": { "command": "/usr/local/bin/roblox-mcp" }
          }
        }
        """, to: "claude_desktop_config.json")

        _ = try MCPConfigWriter.merge(entry: entry, intoJSONAt: url)

        let root = try read(url)
        XCTAssertEqual(root["coworkUserFilesPath"] as? String, "/Users/x/files")
        XCTAssertEqual((root["preferences"] as? [String: Any])?["theme"] as? String, "dark")

        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertEqual((servers["Roblox_Studio"] as? [String: Any])?["command"] as? String,
                       "/usr/local/bin/roblox-mcp")
        XCTAssertNotNil(servers["unlirice"])
    }

    func testUpdateLeavesABackupOfTheOriginal() throws {
        let original = """
        {"mcpServers":{"other":{"command":"x"}}}
        """
        let url = try write(original, to: "mcp.json")

        guard case .updated(_, let backup) = try MCPConfigWriter.merge(entry: entry, intoJSONAt: url) else {
            return XCTFail("expected an update")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
    }

    /// Re-running Get Started shouldn't churn the user's config or litter it
    /// with backups of an unchanged file.
    func testIdenticalEntryIsLeftAloneWithNoNewBackup() throws {
        let url = try write("{}", to: "mcp.json")
        // The first merge does change the file, so it legitimately backs up.
        _ = try MCPConfigWriter.merge(entry: entry, intoJSONAt: url)
        let afterFirst = try backupCount()

        let second = try MCPConfigWriter.merge(entry: entry, intoJSONAt: url)

        XCTAssertEqual(second, .unchanged(url))
        XCTAssertEqual(try backupCount(), afterFirst, "a no-op merge should not add a backup")
    }

    private func backupCount() throws -> Int {
        try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains("unlirice-backup") }
            .count
    }

    func testExistingUnliriceEntryIsOverwrittenNotDuplicated() throws {
        let url = try write("""
        {"mcpServers":{"unlirice":{"command":"swift","args":["stale"]}}}
        """, to: "mcp.json")

        _ = try MCPConfigWriter.merge(entry: entry, intoJSONAt: url)

        let servers = try XCTUnwrap(read(url)["mcpServers"] as? [String: Any])
        let unlirice = try XCTUnwrap(servers["unlirice"] as? [String: Any])
        XCTAssertEqual(unlirice["args"] as? [String], entry.args)
    }

    // MARK: - Refusing

    /// A config we can't parse is one we'd be replacing wholesale — and the tool
    /// that config belongs to is very often the tool the user would use to fix
    /// it. The file must come out byte-identical.
    func testRefusesToTouchAConfigItCannotParse() throws {
        let malformed = "{ this is not json at all"
        let url = try write(malformed, to: "mcp.json")

        XCTAssertThrowsError(try MCPConfigWriter.merge(entry: entry, intoJSONAt: url)) { error in
            guard case MCPConfigWriter.WriteError.unreadableJSON = error else {
                return XCTFail("expected unreadableJSON, got \(error)")
            }
        }

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), malformed)
        XCTAssertEqual(try backupCount(), 0, "a refused write should not leave a backup behind")
    }

    // MARK: - Snippets

    func testJSONSnippetOmitsEnvWhenThereIsNoOverride() throws {
        let snippet = MCPConfigWriter.jsonSnippet(entry: entry)
        let servers = try XCTUnwrap(
            (try XCTUnwrap(JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any]))["mcpServers"] as? [String: Any]
        )
        XCTAssertNil((servers["unlirice"] as? [String: Any])?["env"])
    }

    func testJSONSnippetCarriesTheDataPathOverride() throws {
        let withEnv = MCPServerEntry.forPackage(
            at: URL(fileURLWithPath: "/Users/x/Unli Rice"),
            dataPathOverride: URL(fileURLWithPath: "/Users/x/Vault/events.jsonl")
        )
        let snippet = MCPConfigWriter.jsonSnippet(entry: withEnv)
        XCTAssertTrue(snippet.contains("UNLIRICE_DATA_PATH"))
        XCTAssertTrue(snippet.contains("/Users/x/Vault/events.jsonl"))
        // withoutEscapingSlashes: a human may need to read this file afterward.
        XCTAssertFalse(snippet.contains("\\/"))
    }

    /// Shape matches the `[mcp_servers.x]` tables a real `~/.codex/config.toml`
    /// already uses — checked against one, not written from memory.
    func testTOMLSnippetMatchesCodexTableShape() {
        let snippet = MCPConfigWriter.tomlSnippet(entry: entry)
        XCTAssertTrue(snippet.hasPrefix("[mcp_servers.unlirice]"))
        XCTAssertTrue(snippet.contains("command = \"swift\""))
        XCTAssertTrue(snippet.contains("args = ["))
        XCTAssertTrue(snippet.contains("    \"unlirice-mcp\","))
    }

    func testTOMLSnippetAddsAnEnvTableOnlyWhenNeeded() {
        XCTAssertFalse(MCPConfigWriter.tomlSnippet(entry: entry).contains(".env]"))

        let withEnv = MCPServerEntry(command: "swift", args: [], env: ["UNLIRICE_DATA_PATH": "/v/e.jsonl"])
        let snippet = MCPConfigWriter.tomlSnippet(entry: withEnv)
        XCTAssertTrue(snippet.contains("[mcp_servers.unlirice.env]"))
        XCTAssertTrue(snippet.contains("UNLIRICE_DATA_PATH = \"/v/e.jsonl\""))
    }

    /// A path containing a quote or backslash is legal on macOS, and a silently
    /// malformed config is the hardest kind of failure to diagnose from the
    /// tool's side.
    func testTOMLStringsEscapeQuotesAndBackslashes() {
        let awkward = MCPServerEntry(command: "swift", args: ["/tmp/a\"b\\c"])
        XCTAssertTrue(MCPConfigWriter.tomlSnippet(entry: awkward).contains(#"\"b\\c"#))
    }
}
