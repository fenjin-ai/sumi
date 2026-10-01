// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sumi",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sumi", targets: ["SumiLauncher"]),
               .executable(name: "SumiMCP", targets: ["SumiMCP"])],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [
        .target(name: "SumiCore", resources: [.process("Resources")]),
        .target(name: "SumiAutomation", dependencies: ["SumiCore"]),
        .target(name: "SumiMCPServer", dependencies: ["SumiAutomation", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "SumiMCP", dependencies: ["SumiMCPServer"]),
        .target(name: "SumiApp", dependencies: ["SumiCore", "SumiAutomation"], path: "Sources/Sumi"),
        .executableTarget(name: "SumiLauncher", dependencies: ["SumiApp"]),
        .testTarget(name: "SumiCoreTests", dependencies: ["SumiCore"]),
        .testTarget(name: "SumiAppTests", dependencies: ["SumiApp", "SumiCore", "SumiAutomation"]),
        .testTarget(name: "SumiAutomationTests", dependencies: ["SumiAutomation", "SumiMCPServer"])
    ]
)
