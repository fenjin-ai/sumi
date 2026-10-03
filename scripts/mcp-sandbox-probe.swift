// Release-only fixture: verify real App Sandbox + App Group IPC with the signed helper.
import Darwin
import Foundation

let group = try requireGroup()
let container = try require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
let directory = container.appendingPathComponent("Agents", isDirectory: true)
try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700],
)
let socketURL = directory.appendingPathComponent("s.sock")
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let path = Array(socketURL.path.utf8CString)
guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
    throw ProbeError.failed
}

withUnsafeMutableBytes(of: &address.sun_path) { bytes in
    bytes.copyBytes(from: path.map { UInt8(bitPattern: $0) })
}

address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
guard descriptor >= 0 else {
    throw ProbeError.failed
}

defer { close(descriptor) }
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(
        descriptor,
        $0,
        socklen_t(MemoryLayout<sockaddr_un>.size),
    ) }
}

guard bound == 0 else {
    throw ProbeError.failed
}

defer { unlink(socketURL.path) }
guard chmod(socketURL.path, 0o600) == 0, listen(descriptor, 1) == 0 else {
    throw ProbeError.failed
}

let peer = accept(descriptor, nil, nil)
guard peer >= 0 else {
    throw ProbeError.failed
}

defer { close(peer) }
var uid: uid_t = 0, gid: gid_t = 0
guard getpeereid(peer, &uid, &gid) == 0, uid == getuid() else {
    throw ProbeError.failed
}

var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
while data.last != 10, data.count <= 8192 {
    let count = read(peer, &buffer, buffer.count)
    guard count > 0 else {
        throw ProbeError.failed
    }
    data.append(contentsOf: buffer.prefix(count))
}

let request = try JSONSerialization.jsonObject(with: data) as? [String: Any]
guard request?["operation"] as? String == "get_status" else {
    throw ProbeError.failed
}

let response = Data(
    "{\"result\":{\"bridge_version\":2,\"enabled\":true,\"library_home\":true,\"active_document\":null}}\n"
        .utf8,
)
try FileHandle(fileDescriptor: peer).write(contentsOf: response)

func requireGroup() throws -> String {
    try require(Bundle.main.object(forInfoDictionaryKey: "LeftBlankAgentGroup") as? String)
}

func require<T>(_ value: T?) throws -> T {
    guard let value else {
        throw ProbeError.failed
    }
    return value
}

enum ProbeError: Error { case failed }
