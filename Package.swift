// swift-tools-version: 6.2
import PackageDescription
import Foundation

// App Store and direct builds never resolve or link an external updater.
let preview = ProcessInfo.processInfo.environment["SUMI_DISTRIBUTION"] == "preview"
let distributionSettings: [SwiftSetting] = preview ? [.define("SUMI_PREVIEW")] : []
let updaterPackages: [Package.Dependency] = preview ? [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")] : []
let updaterProducts: [Target.Dependency] = preview ? [.product(name: "Sparkle", package: "Sparkle")] : []

let package = Package(
    name: "Sumi",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sumi", targets: ["SumiLauncher"]),
               .executable(name: "SumiMCP", targets: ["SumiMCP"])],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")] + updaterPackages,
    targets: [
        .target(name: "SumiCore", resources: [.process("Resources")], swiftSettings: distributionSettings),
        .target(name: "SumiAutomation", dependencies: ["SumiCore"]),
        .target(name: "SumiMCPServer", dependencies: ["SumiAutomation", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "SumiMCP", dependencies: ["SumiMCPServer"]),
        .target(name: "SumiApp", dependencies: ["SumiCore", "SumiAutomation"] + updaterProducts, path: "Sources/Sumi", swiftSettings: distributionSettings),
        .executableTarget(name: "SumiLauncher", dependencies: ["SumiApp"], linkerSettings: preview ? [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])] : []),
        .target(name: "SumiTestSupport", path: "Tests/Support"),
        .testTarget(name: "SumiCoreTests", dependencies: ["SumiCore", "SumiTestSupport"]),
        .testTarget(name: "SumiAppTests", dependencies: ["SumiApp", "SumiCore", "SumiAutomation", "SumiTestSupport"] + updaterProducts, swiftSettings: distributionSettings),
        .testTarget(name: "SumiAutomationTests", dependencies: ["SumiAutomation", "SumiMCPServer", "SumiTestSupport"])
    ]
)
