import Foundation
import MCP
import SumiAutomation
import SumiMCPServer

// stdout is exclusively MCP JSON-RPC. Never write logs or banners there.
let bridge = AutomationBridgeClient()
let server = await SumiMCPServer.make { try await bridge.send($0) }
do {
    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
} catch {
    FileHandle.standardError.write(Data("Sumi MCP: \(error.localizedDescription)\n".utf8))
    exit(1)
}
