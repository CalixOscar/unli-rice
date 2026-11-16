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

    // MARK: - Compact retrieval process tests (A4)

    func testToolsListContainsAllSeventeenTools() throws {
        let server = try ProcessHarness.launch(dataFile: tempDir.appendingPathComponent("events.jsonl"))
        defer { server.stop() }
        let reply = try server.call(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#)
        let result = try XCTUnwrap(reply.json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(tools.count, 17)
        XCTAssertEqual(names, Set(MCPTool.allCases.map(\.rawValue)))
        XCTAssertTrue(names.contains("search_note_summaries"))
        XCTAssertTrue(names.contains("get_notes_batch"))
    }

    func testSearchAndBatchReplyLinesStayWithinMaxBytes() throws {
        let dataFile = tempDir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: dataFile)
        let service = NoteService(store: store)
        var ids: [String] = []
        for index in 0..<25 {
            let body = "alpha " + String(repeating: "lorem ipsum dolor \(index) ", count: 150)
            ids.append(try service.createNote(title: "Alpha note \(index)", body: body, source: "human").id.uuidString)
        }
        let eventsBefore = try String(contentsOf: dataFile, encoding: .utf8)
        let requestID = String(repeating: "i", count: 90)
        let server = try ProcessHarness.launch(dataFile: dataFile)
        defer { server.stop() }

        func call(_ name: String, _ arguments: String) throws -> ProcessHarness.Reply {
            try server.call(#"{"jsonrpc":"2.0","id":"\#(requestID)","method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
        }
        func checkOne(_ reply: ProcessHarness.Reply, maxBytes: Int, label: String) throws {
            XCTAssertLessThanOrEqual(reply.lineBytes, maxBytes, label)
            XCTAssertEqual(reply.json["id"] as? String, requestID, label)
            let result = try XCTUnwrap(reply.json["result"] as? [String: Any], label)
            XCTAssertNotEqual(result["isError"] as? Bool, true, label)
            XCTAssertEqual((result["content"] as? [[String: Any]])?.count, 1, label)
        }

        for maxBytes in [2048, 16384] {
            try checkOne(try call("search_note_summaries", #"{"query":"alpha","limit":50,"max_bytes":\#(maxBytes)}"#), maxBytes: maxBytes, label: "search \(maxBytes)")
            // 20 oversized ids cannot be reported at 2048 (spec B6), so use fewer there.
            let quoted = ids.prefix(maxBytes == 2048 ? 5 : 20).map { "\"\($0)\"" }.joined(separator: ",")
            try checkOne(try call("get_notes_batch", #"{"ids":[\#(quoted)],"max_bytes":\#(maxBytes)}"#), maxBytes: maxBytes, label: "batch \(maxBytes)")
        }
        // Default max_bytes (omitted).
        try checkOne(try call("search_note_summaries", #"{"query":"alpha","limit":50}"#), maxBytes: 16384, label: "search default")
        let quoted = ids.prefix(20).map { "\"\($0)\"" }.joined(separator: ",")
        try checkOne(try call("get_notes_batch", #"{"ids":[\#(quoted)]}"#), maxBytes: 16384, label: "batch default")

        XCTAssertEqual(try String(contentsOf: dataFile, encoding: .utf8), eventsBefore, "retrieval must not append events")
    }

    func testBadArgumentIsAnErrorAndServerAnswersNextCall() throws {
        let server = try ProcessHarness.launch(dataFile: tempDir.appendingPathComponent("events.jsonl"))
        defer { server.stop() }
        let bad = try server.call(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_note_summaries","arguments":{"query":"x","limit":true}}}"#)
        let badResult = try XCTUnwrap(bad.json["result"] as? [String: Any])
        XCTAssertEqual(badResult["isError"] as? Bool, true)
        let next = try server.call(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_note_summaries","arguments":{"query":"x"}}}"#)
        let nextResult = try XCTUnwrap(next.json["result"] as? [String: Any])
        XCTAssertNotEqual(nextResult["isError"] as? Bool, true)
        XCTAssertEqual(next.json["id"] as? Int, 2)
    }

    func testConflictedStoreGivesOneContentBlockWithIncompleteDiagnostics() throws {
        let dataFile = tempDir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: dataFile)
        let service = NoteService(store: store)
        _ = try service.createNote(title: "Healthy", body: "", source: "human")
        let conflictID = UUID(), a = UUID(), b = UUID()
        let cycleA = Event(id: a, noteId: conflictID, source: "human", kind: .created, title: "Conflict", causalParents: [b])
        let cycleB = Event(id: b, noteId: conflictID, source: "human", kind: .tagged, tag: "x", causalParents: [a])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try store.appendRawBatch(try [cycleA, cycleB].map { try encoder.encode($0) })

        let server = try ProcessHarness.launch(dataFile: dataFile)
        defer { server.stop() }
        let reply = try server.call(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_note_summaries","arguments":{"query":"Healthy"}}}"#)
        let result = try XCTUnwrap(reply.json["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let diagnostics = try XCTUnwrap(payload["diagnostics"] as? [String: Any])
        XCTAssertEqual(diagnostics["incomplete"] as? Bool, true)
    }
}

/// Launches the real `unlirice-mcp` binary found beside the test bundle (no other
/// location). Stdout and stderr are drained on background threads; every reply
/// wait times out after 10 seconds.
private final class ProcessHarness {
    struct Reply {
        let json: [String: Any]
        /// Bytes of the reply line including its trailing newline.
        let lineBytes: Int
    }

    private let process = Process()
    private let stdin = Pipe()
    private let lock = NSLock()
    private let arrived = DispatchSemaphore(value: 0)
    private var buffer = Data()
    private var closed = false
    private var stopped = false

    static func launch(dataFile: URL) throws -> ProcessHarness {
        let bundle = Bundle(for: MCPProcessTests.self)
        let binary = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("unlirice-mcp")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("unlirice-mcp binary not found beside the test bundle")
        }
        let harness = ProcessHarness()
        try harness.start(binary: binary, dataFile: dataFile)
        return harness
    }

    private func start(binary: URL, dataFile: URL) throws {
        process.executableURL = binary
        var env = ProcessInfo.processInfo.environment
        env["UNLIRICE_DATA_PATH"] = dataFile.path
        process.environment = env
        let stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let outHandle = stdout.fileHandleForReading, errHandle = stderr.fileHandleForReading
        Thread.detachNewThread { [weak self] in
            while true {
                let chunk = outHandle.availableData
                guard let self else { return }
                self.lock.lock()
                if chunk.isEmpty { self.closed = true } else { self.buffer.append(chunk) }
                self.lock.unlock()
                self.arrived.signal()
                if chunk.isEmpty { return }
            }
        }
        Thread.detachNewThread { while !errHandle.availableData.isEmpty {} }
        _ = try call(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"compact-test","version":"1.0"}}}"#)
    }

    func call(_ line: String) throws -> Reply {
        stdin.fileHandleForWriting.write(Data((line + "\n").utf8))
        let deadline = Date().addingTimeInterval(10)
        while true {
            lock.lock()
            if let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                let total = buffer.distance(from: buffer.startIndex, to: newline) + 1
                buffer.removeSubrange(buffer.startIndex...newline)
                lock.unlock()
                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    throw HarnessError.badReply
                }
                return Reply(json: json, lineBytes: total)
            }
            let isClosed = closed
            lock.unlock()
            if isClosed { throw HarnessError.processEnded }
            if arrived.wait(timeout: .now() + max(0.01, deadline.timeIntervalSinceNow)) == .timedOut, Date() >= deadline {
                throw HarnessError.timeout
            }
        }
    }

    func stop() {
        lock.lock()
        if stopped { lock.unlock(); return }
        stopped = true
        lock.unlock()
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    deinit { stop() }

    enum HarnessError: Error { case timeout, processEnded, badReply }
}
