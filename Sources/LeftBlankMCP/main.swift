import Foundation
import LeftBlankAutomation
import LeftBlankMCPServer
import MCP

// stdout is exclusively MCP JSON-RPC. Never write logs or banners there.
let bridge = AutomationBridgeClient()
let server = await LeftBlankMCPServer.make { try await bridge.send($0) }
do {
    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
} catch {
    FileHandle.standardError.write(Data("LeftBlank MCP: \(error.localizedDescription)\n".utf8))
    exit(1)
}
