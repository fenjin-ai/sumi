import Foundation

/// Both native platforms speak the same framed LSP. Only engine startup differs.
@MainActor
public protocol TinymistTransport: AnyObject {
    var input: FileHandle { get }
    var output: FileHandle { get }
    var errorOutput: FileHandle? { get }
    var isRunning: Bool { get }
    var onExit: (@MainActor (Int32) -> Void)? { get set }
    func start(root: URL) throws
    func stop()
}

#if os(macOS)
    @MainActor
    final class ProcessTinymistTransport: TinymistTransport {
        private let process = Process()
        private let stdin = Pipe()
        private let stdout = Pipe()
        private let stderr = Pipe()
        var onExit: (@MainActor (Int32) -> Void)?
        var input: FileHandle {
            stdin.fileHandleForWriting
        }

        var output: FileHandle {
            stdout.fileHandleForReading
        }

        var errorOutput: FileHandle? {
            stderr.fileHandleForReading
        }

        var isRunning: Bool {
            process.isRunning
        }

        static var binaryURL: URL? {
            if let override = ProcessInfo.processInfo.environment["LEFTBLANK_TINYMIST"],
               FileManager.default.isExecutableFile(atPath: override)
            {
                return URL(fileURLWithPath: override)
            }
            let candidates = [
                Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/tinymist"),
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".tools/tinymist"),
                URL(fileURLWithPath: "/opt/homebrew/bin/tinymist"), URL(fileURLWithPath: "/usr/local/bin/tinymist"),
            ]
            return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }

        func start(root: URL) throws {
            guard let binary = Self.binaryURL else {
                throw ServiceError.unavailable
            }
            process.executableURL = binary
            process.arguments = ["lsp"]
            process.currentDirectoryURL = root
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { [weak self] process in
                let status = process.terminationStatus
                Task { @MainActor [weak self] in self?.onExit?(status) }
            }
            try process.run()
        }

        func stop() {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
    }
#endif
