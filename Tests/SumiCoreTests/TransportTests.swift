import Foundation
import Testing
@testable import SumiCore

@MainActor
@Test func stalledPipeDoesNotBlockInputAndPreservesMessageOrder() async throws {
    let pipe = Pipe()
    let received = TransportResults()
    let writer = JSONRPCWriter(handle: pipe.fileHandleForWriting) { error in received.append(.failure(error)) }
    let reader = JSONRPCReader { received.append($0) }
    defer { writer.close(); pipe.fileHandleForReading.readabilityHandler = nil }
    // Larger than the kernel pipe buffer. With no reader the worker blocks,
    // but enqueueing and the main actor remain available for input events.
    let source = String(repeating: "中文😀", count: 100_000)
    let start = ContinuousClock.now
    try writer.send(JSONValue(foundation: ["method": "change", "params": ["text": source, "version": 7, "flag": true]]))
    try writer.send(JSONValue(foundation: ["method": "tokens", "id": 8]))
    let enqueue = start.duration(to: .now)
    try await Task.sleep(for: .milliseconds(30))
    #expect(enqueue < .milliseconds(200), "Enqueue must not perform JSON encoding or wait for pipe capacity")
    #expect(received.values.isEmpty)
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty { reader.append(data) }
    }
    let deadline = ContinuousClock.now + .seconds(5)
    while received.values.count < 2, .now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    let values = received.values
    #expect(values.count == 2)
    let messages = try values.map { try $0.get() }
    #expect(messages.first?["params"]["text"].string == source)
    #expect(messages.first?["params"]["version"].int == 7)
    if case .bool(let flag) = messages.first?["params"]["flag"] { #expect(flag) }
    else { Issue.record("Boolean parameters must retain their type") }
    #expect(messages.last?["method"].string == "tokens")
    #expect(messages.last?["id"].int == 8)
    writer.close()
    #expect(throws: ServiceError.self) { try writer.send(.null) }
    print("SUMI TRANSPORT: enqueue 1 MB while pipe stalled: \(enqueue)")
}

@Test func transportRejectsUnboundedSnapshotsAndInvalidFrames() async throws {
    let pipe = Pipe()
    let results = TransportResults()
    let writer = JSONRPCWriter(handle: pipe.fileHandleForWriting) { error in results.append(.failure(error)) }
    defer { writer.close() }
    #expect(throws: ServiceError.self) { try writer.send(.string(String(repeating: "x", count: 64 * 1024 * 1024))) }
    #expect(throws: EncodingError.self) { try JSONValue(foundation: URL(fileURLWithPath: "/unsupported")) }
    let reader = JSONRPCReader { results.append($0) }
    reader.append(Data("Content-Length: broken\r\n\r\n".utf8))
    let deadline = ContinuousClock.now + .seconds(2)
    while results.values.count < 2, .now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(results.values.count == 2)
    #expect(results.values.allSatisfy { if case .failure = $0 { return true }; return false })
}

@Test func exitedServiceReportsBrokenPipeWithoutTerminatingEditor() async throws {
    let pipe = Pipe()
    let results = TransportResults()
    let writer = JSONRPCWriter(handle: pipe.fileHandleForWriting) { results.append(.failure($0)) }
    defer { writer.close() }
    try pipe.fileHandleForReading.close()
    try writer.send(JSONValue(foundation: ["method": "change", "params": ["text": "Still writing"]]))
    let deadline = ContinuousClock.now + .seconds(2)
    while results.values.isEmpty, .now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(results.values.count == 1)
    #expect(results.values.allSatisfy { if case .failure = $0 { return true }; return false })
    #expect(throws: ServiceError.self) { try writer.send(.null) }
}

private final class TransportResults: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<JSONValue, Error>] = []
    var values: [Result<JSONValue, Error>] { lock.withLock { results } }
    func append(_ value: Result<JSONValue, Error>) { lock.withLock { results.append(value) } }
}
