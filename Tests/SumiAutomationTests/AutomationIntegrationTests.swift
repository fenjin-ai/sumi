import SumiTestSupport
import Darwin
import Foundation
import SumiAutomation
import SumiCore
import Testing

@Suite("Local agent bridge")
struct AutomationIntegrationTests {
    @Test func privateSocketRoundTripAndRevocation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = AutomationContract.socketURL(in: root)
        let server = AutomationBridgeServer(socketURL: endpoint)
        try server.start { request in
            guard request.operation == "get_document" else { throw AutomationFailure("not_allowed", "Operation denied.") }
            return .object(["text": .string("中文 ∑ 😀"), "request": request.arguments])
        }
        defer { server.stop() }
        let client = AutomationBridgeClient(socketURL: endpoint)
        #expect(try await client.send(.init("get_document"))["text"].string == "中文 ∑ 😀")
        do { _ = try await client.send(.init("shell")); Issue.record("Unexpected operation accepted") }
        catch let failure as AutomationFailure { #expect(failure.code == "not_allowed") }
        let attributes = try FileManager.default.attributesOfItem(atPath: endpoint.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let competitor = AutomationBridgeServer(socketURL: endpoint)
        #expect(throws: AutomationFailure.self) { try competitor.start { _ in .null } }
        #expect(try await client.send(.init("get_document"))["text"].string == "中文 ∑ 😀", "A competing app must not remove the active socket")
        server.stop()
        await #expect(throws: AutomationFailure.self) { try await client.send(.init("get_document")) }
        try server.start { _ in .string("re-enabled") }
        #expect(try await client.send(.init("get_document")).string == "re-enabled")
    }

    @Test func refusesUnsafeEndpointAndDoesNotOverwriteFiles() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = AutomationContract.socketURL(in: root)
        try FileManager.default.createDirectory(at: endpoint.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data("keep".utf8).write(to: endpoint)
        let server = AutomationBridgeServer(socketURL: endpoint)
        #expect(throws: AutomationFailure.self) { try server.start { _ in .null } }
        #expect(try String(contentsOf: endpoint, encoding: .utf8) == "keep")
        try FileManager.default.removeItem(at: endpoint)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: endpoint.deletingLastPathComponent().path)
        #expect(throws: AutomationFailure.self) { try server.start { _ in .null } }
    }

    @Test func atomicUTF16EditsRejectStaleBoundariesAndOverlap() throws {
        let text = "A😀B\n中文"
        let edits: JSONValue = .array([
            .object(["start": .number(1), "end": .number(3), "text": .string("Σ")]),
            .object(["start": .number(5), "end": .number(7), "text": .string("Writing")])
        ])
        #expect(try AutomationContract.replacing(edits, in: text) == "AΣB\nWriting")
        for range in [(2, 3), (-1, 2), (0, 100), (4, 1)] {
            let invalid: JSONValue = .array([.object(["start": .number(Double(range.0)), "end": .number(Double(range.1)), "text": .string("bad")])])
            #expect(throws: AutomationFailure.self) { try AutomationContract.replacing(invalid, in: text) }
        }
        #expect(throws: AutomationFailure.self) {
            try AutomationContract.replacing(.array(edits.array + edits.array), in: text)
        }
        #expect(throws: AutomationFailure.self) { try AutomationContract.replacing(.array([]), in: text) }
        #expect(AutomationContract.revision(documentID: "a", text: text) != AutomationContract.revision(documentID: "b", text: text))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUMI_MCP_HELPER"] != nil))
    func actualStdioHelperNegotiatesDiscoversAndReachesAppBridge() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = AutomationBridgeServer(socketURL: AutomationContract.socketURL(in: root))
        try server.start { request in
            switch request.operation {
            case "get_document": return .object(["document_id": .string("test-doc"), "revision": .string("revision-1"), "text": .string("= Live unsaved source")])
            case "get_settings": return .object(["layout": .string("writing")])
            case "export_pdf": return .object(["path": .string("test.pdf"), "image_png": .string("aW1hZ2U=")])
            default: throw AutomationFailure("revision_conflict", "Read the document again.")
            }
        }
        defer { server.stop() }
        try await Task.detached {
            let session = try MCPWireSession(stateDirectory: root)
            defer { session.close() }
            let initialization = try session.request("initialize", ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "Sumi integration test", "version": "1"]])
            #expect(initialization["result"]["serverInfo"]["name"].string == "Sumi")
            try session.notify("notifications/initialized")
            let tools = try session.request("tools/list")["result"]["tools"].array
            #expect(tools.count == 9)
            #expect(tools.contains { $0["name"].string == "sumi_apply_edits" })
            let read = try session.request("tools/call", ["name": "sumi_get_document"])
            #expect(read["result"]["structuredContent"]["text"].string == "= Live unsaved source")
            let conflict = try session.request("tools/call", ["name": "sumi_apply_edits", "arguments": [:]])
            #expect(conflict["result"]["structuredContent"]["code"].string == "revision_conflict")
            #expect(try session.request("resources/list")["result"]["resources"].array.count == 2)
            let resource = try session.request("resources/read", ["uri": "sumi://settings"])
            #expect(resource["result"]["contents"].array.first?["text"].string?.contains("writing") == true)
            #expect(try session.request("prompts/list")["result"]["prompts"].array.count == 1)
            let prompt = try session.request("prompts/get", ["name": "write_in_sumi", "arguments": ["task": "Write a note"]])
            #expect(prompt["result"]["messages"].array.first?["content"]["text"].string?.contains("Write a note") == true)
            let export = try session.request("tools/call", ["name": "sumi_export_pdf"])
            #expect(export["result"]["content"].array.count == 2)
            #expect(export["result"]["content"].array.last?["type"].string == "image")
            #expect(export["result"]["structuredContent"]["image_png"].isNull)
            server.stop()
            let disabled = try session.request("tools/call", ["name": "sumi_get_document"])
            #expect(disabled["result"]["structuredContent"]["code"].string == "access_unavailable")
            #expect(try session.request("tools/call", ["name": "sumi_shell"])["error"]["code"].int == -32602)
        }.value
    }

    private func directory() throws -> URL {
        // TMPDIR is set by scripts/environment.sh; short names fit Darwin's Unix socket limit.
        let root = TestPaths.temporaryDirectory.appendingPathComponent("m" + UUID().uuidString.prefix(8))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private final class MCPWireSession {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private var buffer = Data()
    private var id = 0

    init(stateDirectory: URL) throws {
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUMI_MCP_HELPER"]!)
        var environment = ProcessInfo.processInfo.environment.merging(["SUMI_STATE_DIR": stateDirectory.path], uniquingKeysWith: { _, new in new })
        if let coverage = environment["SUMI_MCP_COVERAGE_DIR"] {
            environment["LLVM_PROFILE_FILE"] = URL(fileURLWithPath: coverage).appendingPathComponent("mcp-%p.profraw").path
        }
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        try process.run()
    }
    func request(_ method: String, _ params: [String: Any] = [:]) throws -> JSONValue {
        id += 1
        try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        while true {
            let response = try JSONDecoder().decode(JSONValue.self, from: line())
            if response["id"].int == id { return response }
        }
    }
    func notify(_ method: String) throws { try write(["jsonrpc": "2.0", "method": method]) }
    private func write(_ value: [String: Any]) throws {
        try input.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10]))
    }
    private func line() throws -> Data {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline); return line
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 10_000) > 0 else { throw AutomationFailure("test_timeout", "MCP response timed out.") }
            let data = output.fileHandleForReading.availableData
            guard !data.isEmpty else { throw AutomationFailure("helper_closed", "MCP helper exited without a response.") }
            buffer.append(data)
        }
    }
    func close() {
        try? input.fileHandleForWriting.close()
        // EOF lets the helper flush its LLVM coverage profile before exit.
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}
