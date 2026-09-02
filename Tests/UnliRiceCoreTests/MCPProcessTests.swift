import XCTest
@testable import UnliRiceCore

final class MCPProcessTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-mcp-process-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func findMCPBinary() -> URL? {
        let testBundle = Bundle(for: MCPProcessTests.self)
        let buildDir = testBundle.bundleURL.deletingLastPathComponent()
        let candidate = buildDir.appendingPathComponent("unlirice-mcp")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        // Also check .build/debug or .build/arm64-apple-macosx/debug
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent(".build/debug/unlirice-mcp"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/debug/unlirice-mcp"),
            cwd.appendingPathComponent(".build/x86_64-apple-macosx/debug/unlirice-mcp")
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    // 23 & 24. Negative limit -> ping -> zero limit sequence against real unlirice-mcp process
    func testNegativeLimitPingZeroLimitProcessSequence() throws {
        guard let binary = findMCPBinary() else {
            throw XCTSkip("unlirice-mcp binary not found; skipping process-level test")
        }

        let dataFile = tempDir.appendingPathComponent("events.jsonl")
        let connectionsFile = tempDir.appendingPathComponent("connections.json")

        let process = Process()
        process.executableURL = binary
        var env = ProcessInfo.processInfo.environment
        env["UNLIRICE_DATA_PATH"] = dataFile.path
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdinHandle = stdinPipe.fileHandleForWriting
        let stdoutHandle = stdoutPipe.fileHandleForReading

        func sendLine(_ string: String) {
            let data = (string + "\n").data(using: .utf8)!
            stdinHandle.write(data)
        }

        var lineBuffer = Data()
        func readLine() -> String? {
            while true {
                if let newlineRange = lineBuffer.range(of: Data([0x0A])) {
                    let lineData = lineBuffer.subdata(in: 0..<newlineRange.lowerBound)
                    lineBuffer.removeSubrange(0..<newlineRange.upperBound)
                    return String(data: lineData, encoding: .utf8)
                }
                let chunk = stdoutHandle.availableData
                if chunk.isEmpty {
                    return nil
                }
                lineBuffer.append(chunk)
            }
        }

        // 1. Initialize
        sendLine("""
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test-client","version":"1.0"}}}
        """)
        guard let initRespLine = readLine(),
              let initResp = JSONRPC.parseLine(initRespLine) else {
            XCTFail("Failed to read initialize response")
            process.terminate()
            return
        }
        XCTAssertEqual(initResp["id"] as? Int, 1)

        // 2. transaction_log with limit: -1
        sendLine("""
        {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"transaction_log","arguments":{"limit":-1}}}
        """)
        guard let call1RespLine = readLine(),
              let call1Resp = JSONRPC.parseLine(call1RespLine) else {
            XCTFail("Failed to read limit: -1 response; process may have died")
            process.terminate()
            return
        }
        XCTAssertEqual(call1Resp["id"] as? Int, 2)
        let result1 = try XCTUnwrap(call1Resp["result"] as? [String: Any])
        XCTAssertEqual(result1["isError"] as? Bool, true)
        XCTAssertTrue(process.isRunning, "Server process must stay alive after invalid limit")

        // 24. Verify failure is recorded in connections.json with succeeded == false
        XCTAssertTrue(FileManager.default.fileExists(atPath: connectionsFile.path))
        let connData1 = try Data(contentsOf: connectionsFile)
        let connJson1 = try XCTUnwrap(JSONSerialization.jsonObject(with: connData1) as? [String: Any])
        let clients1 = try XCTUnwrap(connJson1["clients"] as? [[String: Any]])
        let testClient1 = try XCTUnwrap(clients1.first(where: { ($0["clientName"] as? String) == "test-client" }))
        XCTAssertEqual(testClient1["lastToolName"] as? String, "transaction_log")
        XCTAssertEqual(testClient1["lastToolSucceeded"] as? Bool, false)
        XCTAssertNil(testClient1["lastWriteAt"])

        // 3. ping
        sendLine("""
        {"jsonrpc":"2.0","id":3,"method":"ping","params":{}}
        """)
        guard let pingRespLine = readLine(),
              let pingResp = JSONRPC.parseLine(pingRespLine) else {
            XCTFail("Failed to read ping response")
            process.terminate()
            return
        }
        XCTAssertEqual(pingResp["id"] as? Int, 3)
        XCTAssertNotNil(pingResp["result"])
        XCTAssertTrue(process.isRunning, "Server process must stay alive after ping")

        // 4. transaction_log with limit: 0
        sendLine("""
        {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"transaction_log","arguments":{"limit":0}}}
        """)
        guard let call2RespLine = readLine(),
              let call2Resp = JSONRPC.parseLine(call2RespLine) else {
            XCTFail("Failed to read limit: 0 response")
            process.terminate()
            return
        }
        XCTAssertEqual(call2Resp["id"] as? Int, 4)
        let result2 = try XCTUnwrap(call2Resp["result"] as? [String: Any])
        XCTAssertNotEqual(result2["isError"] as? Bool, true)
        let content2 = try XCTUnwrap(result2["content"] as? [[String: Any]])
        let text2 = try XCTUnwrap(content2.first?["text"] as? String)
        XCTAssertEqual(text2, "[]")

        // Clean close
        try? stdinHandle.close()
        process.waitUntilExit()
    }
}
