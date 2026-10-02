import Darwin
import Foundation
import LeftBlankCore

private enum LocalSocket {
    /// Blocking POSIX I/O must not occupy Swift's cooperative executor. A small
    /// runner (or several clients) otherwise leaves no worker to answer requests.
    static func io<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try continuation.resume(returning: operation()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func address(_ url: URL) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(url.path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw AutomationFailure(
                "socket_path_too_long",
                "LeftBlank's app support path is too long for local agent access.",
            )
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func withAddress<T>(_ url: URL, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var value = try address(url)
        return withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func configure(_ fd: Int32, timeout: Int = 30) {
        // Darwin's accepted socket inherits O_NONBLOCK from the dispatch listener.
        // Per-connection I/O runs off the main actor and uses bounded blocking reads.
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        }
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout.size(ofValue: enabled)))
        var value = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout.size(ofValue: value)))
    }

    static func sameUser(_ fd: Int32) -> Bool {
        var user: uid_t = 0, group: gid_t = 0
        return getpeereid(fd, &user, &group) == 0 && user == getuid()
    }

    static func readMessage(_ fd: Int32) throws -> Data {
        var result = Data(), bytes = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = recv(fd, &bytes, bytes.count, 0)
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else {
                throw AutomationFailure(
                    "connection_closed",
                    "The local LeftBlank connection closed or timed out.",
                )
            }
            if let end = bytes[..<count].firstIndex(of: 10) {
                result.append(contentsOf: bytes[..<end])
                guard result.count <= AutomationContract.maximumMessageBytes else {
                    throw oversized()
                }
                return result
            }
            result.append(contentsOf: bytes[..<count])
            guard result.count <= AutomationContract.maximumMessageBytes else {
                throw oversized()
            }
        }
    }

    static func writeMessage(_ data: Data, to fd: Int32) throws {
        guard data.count <= AutomationContract.maximumMessageBytes else {
            throw oversized()
        }
        let framed = data + Data([10])
        try framed.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw oversized()
            }
            var sent = 0
            while sent < bytes.count {
                let count = send(fd, baseAddress.advanced(by: sent), bytes.count - sent, MSG_NOSIGNAL)
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    throw AutomationFailure(
                        "connection_closed",
                        "LeftBlank could not send the local response.",
                    )
                }
                sent += count
            }
        }
    }

    static func oversized() -> AutomationFailure {
        .init("message_too_large", "The agent message exceeds 8 MiB.")
    }

    static func verifyPrivateDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0
        else {
            throw AutomationFailure(
                "unsafe_socket_directory",
                "The agent bridge directory must belong to you and have private permissions (0700).",
            )
        }
    }
}

/// A local, same-user bridge. One bounded request per connection; no TCP listener.
/// Only lifecycle counters are shared across queues; application work runs in the supplied handler.
public final class AutomationBridgeServer: @unchecked Sendable {
    public typealias Handler = @Sendable (AutomationRequest) async throws -> JSONValue
    public let socketURL: URL
    private let lock = NSLock()
    private var source: (any DispatchSourceRead)?
    private var generation = UUID()
    private var connections = 0

    public init(socketURL: URL) {
        self.socketURL = socketURL
    }

    deinit { stop() }

    public func start(handler: @escaping Handler) throws {
        stop()
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )
        try LocalSocket.verifyPrivateDirectory(directory)
        var old = stat()
        if lstat(socketURL.path, &old) == 0 {
            guard old.st_uid == getuid(), old.st_mode & S_IFMT == S_IFSOCK else {
                throw AutomationFailure("unsafe_socket", "The agent bridge path is occupied by an unexpected file.")
            }
            let probe = socket(AF_UNIX, SOCK_STREAM, 0)
            guard probe >= 0 else {
                throw AutomationFailure("socket_failed", "Cannot create a local socket.")
            }
            let connected = try LocalSocket.withAddress(socketURL) { connect(probe, $0, $1) }
            let reason = errno
            close(probe)
            guard connected != 0, reason == ECONNREFUSED else {
                throw AutomationFailure("already_running", "Another LeftBlank window already owns agent access.")
            }
            guard unlink(socketURL.path) == 0 else {
                throw AutomationFailure(
                    "socket_failed",
                    "Cannot clear the previous agent socket.",
                )
            }
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AutomationFailure("socket_failed", "Cannot create a local socket.")
        }
        var bound = false
        do {
            guard try LocalSocket.withAddress(socketURL, { bind(fd, $0, $1) }) == 0 else {
                throw AutomationFailure("socket_failed", "Cannot bind LeftBlank's local agent socket.")
            }
            bound = true
            guard chmod(socketURL.path, 0o600) == 0, listen(fd, 8) == 0 else {
                throw AutomationFailure("socket_failed", "Cannot secure LeftBlank's local agent socket.")
            }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
            let token = UUID()
            listener.setCancelHandler { close(fd) }
            listener.setEventHandler { [weak self] in self?.acceptConnections(fd, token: token, handler: handler) }
            lock.withLock { generation = token
                source = listener
            }
            listener.resume()
        } catch {
            close(fd)
            if bound {
                unlink(socketURL.path)
            }
            throw error
        }
    }

    public func stop() {
        let previous = lock.withLock { () -> (any DispatchSourceRead)? in
            let previous = source
            source = nil
            generation = UUID()
            return previous
        }
        if let previous {
            previous.cancel()
            unlink(socketURL.path)
        }
    }

    private func acceptConnections(_ fd: Int32, token: UUID, handler: @escaping Handler) {
        while true {
            let connection = accept(fd, nil, nil)
            guard connection >= 0 else {
                return
            }
            let allowed = lock.withLock { () -> Bool in
                guard source != nil, token == generation, connections < 8 else {
                    return false
                }
                connections += 1
                return true
            }
            guard allowed else {
                close(connection)
                continue
            }
            guard LocalSocket.sameUser(connection) else {
                close(connection)
                lock.withLock { connections -= 1 }
                continue
            }
            LocalSocket.configure(connection, timeout: 5)
            Task.detached { [weak self] in
                defer { close(connection)
                    self?.lock.withLock { self?.connections -= 1 }
                }
                let response: AutomationResponse
                do {
                    let request = try await LocalSocket.io {
                        try JSONDecoder().decode(AutomationRequest.self, from: LocalSocket.readMessage(connection))
                    }
                    guard let self, lock.withLock({ self.source != nil && self.generation == token }) else {
                        throw AutomationFailure("access_disabled", "Agent access has been disabled in LeftBlank.")
                    }
                    response = try await AutomationResponse(result: handler(request))
                } catch let error as AutomationFailure { response = AutomationResponse(error: error) }
                catch { response = AutomationResponse(error: .init("operation_failed", error.localizedDescription)) }
                do { try await LocalSocket.io { try LocalSocket.writeMessage(
                    JSONEncoder().encode(response),
                    to: connection,
                ) } } catch { /* A disconnected caller does not undo an already committed app operation. */ }
            }
        }
    }
}

public struct AutomationBridgeClient: Sendable {
    public let socketURL: URL
    public init(socketURL: URL = AutomationContract.socketURL(in: AutomationContract.defaultStateDirectory)) {
        self.socketURL = socketURL
    }

    public func send(_ request: AutomationRequest) async throws -> JSONValue {
        try await LocalSocket.io {
            do { try LocalSocket.verifyPrivateDirectory(socketURL.deletingLastPathComponent()) }
            catch { throw AutomationFailure(
                "access_unavailable",
                "Open LeftBlank and enable Agent Access in its settings.",
            ) }
            var info = stat()
            guard lstat(socketURL.path, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & S_IFMT == S_IFSOCK, info.st_mode & 0o077 == 0
            else {
                throw AutomationFailure("access_unavailable", "Open LeftBlank and enable Agent Access in its settings.")
            }
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw AutomationFailure("socket_failed", "Cannot create a local socket.")
            }
            defer { close(fd) }
            LocalSocket.configure(fd)
            guard try LocalSocket.withAddress(socketURL, { connect(fd, $0, $1) }) == 0, LocalSocket.sameUser(fd) else {
                throw AutomationFailure(
                    "access_unavailable",
                    "LeftBlank is not accepting agent connections. Re-enable Agent Access in LeftBlank.",
                )
            }
            try LocalSocket.writeMessage(JSONEncoder().encode(request), to: fd)
            return try JSONDecoder().decode(AutomationResponse.self, from: LocalSocket.readMessage(fd)).value()
        }
    }
}
