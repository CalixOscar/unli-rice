import Foundation
import UnliRiceCore

func logToStderr(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// Installed helpers share the app-group container with the GUI. If the user
// chose an external corpus, the GUI also saved its security-scoped bookmark in
// AgentSettings; keep that scope open for this stdio server's lifetime.
// UNLIRICE_DATA_PATH still wins for development smoke tests.
let settings = AgentSettings.load()
var activeDataFolder: URL?
let dataURL: URL
if let override = ProcessInfo.processInfo.environment["UNLIRICE_DATA_PATH"], !override.isEmpty {
    dataURL = URL(fileURLWithPath: override)
} else if let folder = settings.dataFolderURL,
          folder.startAccessingSecurityScopedResource() {
    activeDataFolder = folder
    dataURL = DataLocation.eventLogURL(inFolder: folder)
} else {
    dataURL = DataLocation.eventLogURL(persistedFolderPath: settings.dataFolderPath)
}
defer { activeDataFolder?.stopAccessingSecurityScopedResource() }
let store: EventStore
do {
    store = try EventStore(fileURL: dataURL)
} catch {
    logToStderr("unlirice-mcp: failed to open event log at \(dataURL.path): \(error)")
    exit(1)
}
let service = NoteService(store: store)
let dispatcher = ToolDispatcher(service: service)
let connectionActivity = MCPConnectionActivityStore(besideEventLog: dataURL)
var currentClientName = "Unknown MCP client"
var currentClientVersion: String?

logToStderr("unlirice-mcp: ready, event log at \(dataURL.path)")

// MCP stdio transport: one JSON-RPC 2.0 message per line on stdin, one per
// line on stdout. Nothing else may ever be written to stdout — that would
// corrupt the protocol stream, so all diagnostics go to stderr.
while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    guard let message = JSONRPC.parseLine(line) else {
        logToStderr("unlirice-mcp: could not parse line: \(line)")
        continue
    }

    let method = message["method"] as? String
    let id = message["id"]
    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        if let clientInfo = params["clientInfo"] as? [String: Any] {
            currentClientName = (clientInfo["name"] as? String) ?? currentClientName
            currentClientVersion = clientInfo["version"] as? String
        }
        _ = try? connectionActivity.recordConnection(
            clientName: currentClientName,
            clientVersion: currentClientVersion
        )
        JSONRPC.writeLine(JSONRPC.result(id: id, [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "unlirice-mcp", "version": "0.1.0"]
        ]))

    case "notifications/initialized":
        break // no response required for notifications

    case "tools/list":
        JSONRPC.writeLine(JSONRPC.result(id: id, ["tools": ToolCatalog.all]))

    case "tools/call":
        guard let toolName = params["name"] as? String else {
            JSONRPC.writeLine(JSONRPC.error(id: id, code: -32602, message: "Missing tool name"))
            continue
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let result = dispatcher.dispatch(name: toolName, arguments: arguments)
        _ = try? connectionActivity.recordToolCall(
            clientName: currentClientName,
            clientVersion: currentClientVersion,
            toolName: toolName,
            succeeded: (result["isError"] as? Bool) != true
        )
        JSONRPC.writeLine(JSONRPC.result(id: id, result))

    case "ping":
        JSONRPC.writeLine(JSONRPC.result(id: id, [:]))

    case .some(let other):
        if id != nil {
            JSONRPC.writeLine(JSONRPC.error(id: id, code: -32601, message: "Method not found: \(other)"))
        }

    case .none:
        break
    }
}
