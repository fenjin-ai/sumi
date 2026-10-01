import Foundation

public enum ServiceError: LocalizedError {
    case unavailable, disconnected, timeout, remote(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "没有找到排版服务，请重新构建应用或检查 Tinymist 路径。"
        case .disconnected: "排版服务已断开。文稿仍可编辑和保存。"
        case .timeout: "排版服务响应超时，请重试或重新连接。"
        case .remote(let message):
            if let start = message.range(of: "error: ") {
                String(message[start.upperBound...].components(separatedBy: "\\n")[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else { String(message.prefix(400)) }
        }
    }
}

@MainActor
public final class TinymistClient {
    public init() {}
    public var onNotification: ((String, JSONValue) -> Void)?
    public var onShowDocument: ((JSONValue) -> Void)?
    public var onDisconnect: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var framer = JSONRPCFramer()
    private var serial = 0
    private var generation = UUID()
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    public private(set) var initialized = false

    public static var binaryURL: URL? {
        if let override = ProcessInfo.processInfo.environment["SUMI_TINYMIST"], FileManager.default.isExecutableFile(atPath: override) { return URL(fileURLWithPath: override) }
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tinymist"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".tools/tinymist"),
            URL(fileURLWithPath: "/opt/homebrew/bin/tinymist"), URL(fileURLWithPath: "/usr/local/bin/tinymist")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func start(root: URL, outputDirectory: URL) async throws {
        stop()
        guard let binary = Self.binaryURL else { throw ServiceError.unavailable }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = binary
        process.arguments = ["lsp"]
        process.currentDirectoryURL = root
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let session = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == session else { return }
                self.consume(data)
            }
        }
        // Drain stderr without logging manuscript content.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == session else { return }
                self.stop()
                self.onDisconnect?("排版服务已退出（\(status)）。你的文字仍然保留。")
            }
        }
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.output = stdout.fileHandleForReading
        self.errorOutput = stderr.fileHandleForReading
        try process.run()
        _ = try await request("initialize", [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": root.absoluteString,
            "capabilities": [
                "general": ["positionEncodings": ["utf-16"]],
                "window": ["showDocument": ["support": true]],
                "textDocument": ["publishDiagnostics": ["versionSupport": true], "completion": ["completionItem": ["snippetSupport": false]]]
            ],
            "initializationOptions": ["exportPdf": "never", "outputPath": outputDirectory.appendingPathComponent("$name").path, "compileStatus": "enable"]
        ])
        guard generation == session else { throw ServiceError.disconnected }
        try notify("initialized", [:])
        initialized = true
    }

    public func stop() {
        generation = UUID()
        initialized = false
        output?.readabilityHandler = nil
        errorOutput?.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close()
        input = nil; output = nil; errorOutput = nil; process = nil
        framer = JSONRPCFramer()
        let waiting = pending
        pending.removeAll()
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: ServiceError.disconnected) }
    }

    public func notify(_ method: String, _ params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    public func request(_ method: String, _ params: [String: Any]) async throws -> JSONValue {
        serial += 1
        let id = serial
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.pending.removeValue(forKey: id)?.resume(throwing: ServiceError.timeout)
                self?.timeouts.removeValue(forKey: id)
            }
            do { try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params]) }
            catch {
                timeouts.removeValue(forKey: id)?.cancel()
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    public func command(_ name: String, arguments: [Any]) async throws -> JSONValue {
        try await request("workspace/executeCommand", ["command": name, "arguments": arguments])
    }

    public func open(_ url: URL, text: String, version: Int) throws {
        try notify("textDocument/didOpen", ["textDocument": ["uri": url.absoluteString, "languageId": "typst", "version": version, "text": text]])
    }

    public func change(_ url: URL, text: String, version: Int) throws {
        try notify("textDocument/didChange", ["textDocument": ["uri": url.absoluteString, "version": version], "contentChanges": [["text": text]]])
    }

    public func startPreview(_ url: URL) async throws -> URL {
        let response = try await command("tinymist.doStartPreview", arguments: [[
            "--task-id=sumi", "--data-plane-host=127.0.0.1:0", "--control-plane-host=127.0.0.1:0", "--no-open", "--partial-rendering=true", "--invert-colors=never", url.path
        ]])
        guard let port = response["staticServerPort"].int, let preview = URL(string: "http://127.0.0.1:\(port)/") else { throw ServiceError.remote("预览服务没有返回有效地址。") }
        return preview
    }

    private func write(_ object: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw ServiceError.disconnected }
        try input.write(contentsOf: JSONRPCFramer.encode(object))
    }

    private func consume(_ data: Data) {
        do {
            for frame in try framer.append(data) {
                let message = try JSONDecoder().decode(JSONValue.self, from: frame)
                if let method = message["method"].string {
                    if !message["id"].isNull {
                        let result: Any
                        if method == "window/showDocument" {
                            onShowDocument?(message["params"])
                            result = ["success": true]
                        } else if method == "workspace/configuration" {
                            result = message["params"]["items"].array.map { _ in NSNull() }
                        } else { result = NSNull() }
                        try write(["jsonrpc": "2.0", "id": message["id"].foundationValue, "result": result])
                    } else { onNotification?(method, message["params"]) }
                } else if let id = message["id"].int, let continuation = pending.removeValue(forKey: id) {
                    timeouts.removeValue(forKey: id)?.cancel()
                    if !message["error"].isNull { continuation.resume(throwing: ServiceError.remote(message["error"]["message"].string ?? "排版服务发生错误。")) }
                    else { continuation.resume(returning: message["result"]) }
                }
            }
        } catch {
            stop()
            onDisconnect?("排版服务通信中断：\(error.localizedDescription)")
        }
    }
}
