import XCTest
@testable import UnliRiceCore

final class MCPConfigRendererTests: XCTestCase {
    private let entry = MCPServerEntry(
        command: "swift",
        args: ["run", "--package-path", "/Users/x/Unli Rice", "--quiet", "unlirice-mcp"]
    )

    func testJSONSnippetOmitsEnvWhenThereIsNoOverride() throws {
        let snippet = MCPConfigRenderer.jsonSnippet(entry: entry)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any]
        )
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNil((servers["unlirice"] as? [String: Any])?["env"])
    }

    func testJSONSnippetCarriesTheDataPathOverride() {
        let withEnv = MCPServerEntry.forPackage(
            at: URL(fileURLWithPath: "/Users/x/Unli Rice"),
            dataPathOverride: URL(fileURLWithPath: "/Users/x/Vault/events.jsonl")
        )
        let snippet = MCPConfigRenderer.jsonSnippet(entry: withEnv)
        XCTAssertTrue(snippet.contains("UNLIRICE_DATA_PATH"))
        XCTAssertTrue(snippet.contains("/Users/x/Vault/events.jsonl"))
        XCTAssertFalse(snippet.contains("\\/"))
    }

    func testTOMLSnippetMatchesCodexTableShape() {
        let snippet = MCPConfigRenderer.tomlSnippet(entry: entry)
        XCTAssertTrue(snippet.hasPrefix("[mcp_servers.unlirice]"))
        XCTAssertTrue(snippet.contains("command = \"swift\""))
        XCTAssertTrue(snippet.contains("args = ["))
        XCTAssertTrue(snippet.contains("    \"unlirice-mcp\","))
    }

    func testTOMLSnippetAddsAnEnvTableOnlyWhenNeeded() {
        XCTAssertFalse(MCPConfigRenderer.tomlSnippet(entry: entry).contains(".env]"))

        let withEnv = MCPServerEntry(
            command: "swift",
            args: [],
            env: ["UNLIRICE_DATA_PATH": "/v/e.jsonl"]
        )
        let snippet = MCPConfigRenderer.tomlSnippet(entry: withEnv)
        XCTAssertTrue(snippet.contains("[mcp_servers.unlirice.env]"))
        XCTAssertTrue(snippet.contains("UNLIRICE_DATA_PATH = \"/v/e.jsonl\""))
    }

    func testTOMLStringsEscapeQuotesAndBackslashes() {
        let awkward = MCPServerEntry(command: "swift", args: ["/tmp/a\"b\\c"])
        XCTAssertTrue(MCPConfigRenderer.tomlSnippet(entry: awkward).contains(#"\"b\\c"#))
    }
}
