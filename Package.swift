// swift-tools-version: 6.2
import Foundation
import PackageDescription

// App Store and direct builds never resolve or link an external updater.
let preview = ProcessInfo.processInfo.environment["LEFTBLANK_DISTRIBUTION"] == "preview"
let distributionSettings: [SwiftSetting] = preview ? [.define("LEFTBLANK_PREVIEW")] : []
let updaterPackages: [Package.Dependency] = preview ? [.package(
    url: "https://github.com/sparkle-project/Sparkle.git",
    exact: "2.10.0",
)] : []
let updaterProducts: [Target.Dependency] = preview ? [.product(name: "Sparkle", package: "Sparkle")] : []

let package = Package(
    name: "LeftBlank",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LeftBlank", targets: ["LeftBlankLauncher"]),
               .executable(name: "LeftBlankMCP", targets: ["LeftBlankMCP"])],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")] +
        updaterPackages,
    targets: [
        .target(name: "LeftBlankCore", resources: [.process("Resources")], swiftSettings: distributionSettings),
        .target(name: "LeftBlankAutomation", dependencies: ["LeftBlankCore"]),
        .target(
            name: "LeftBlankMCPServer",
            dependencies: ["LeftBlankAutomation", .product(name: "MCP", package: "swift-sdk")],
        ),
        .executableTarget(name: "LeftBlankMCP", dependencies: ["LeftBlankMCPServer"]),
        .target(
            name: "LeftBlankApp",
            dependencies: ["LeftBlankCore", "LeftBlankAutomation"] + updaterProducts,
            path: "Sources/LeftBlank",
            swiftSettings: distributionSettings,
        ),
        .executableTarget(
            name: "LeftBlankLauncher",
            dependencies: ["LeftBlankApp"],
            linkerSettings: preview ? [.unsafeFlags([
                "-Xlinker",
                "-rpath",
                "-Xlinker",
                "@executable_path/../Frameworks",
            ])] : [],
        ),
        .target(name: "LeftBlankTestSupport", path: "Tests/Support"),
        .testTarget(name: "LeftBlankCoreTests", dependencies: ["LeftBlankCore", "LeftBlankTestSupport"]),
        .testTarget(
            name: "LeftBlankAppTests",
            dependencies: ["LeftBlankApp", "LeftBlankCore", "LeftBlankAutomation", "LeftBlankTestSupport"] +
                updaterProducts,
            swiftSettings: distributionSettings,
        ),
        .testTarget(
            name: "LeftBlankAutomationTests",
            dependencies: ["LeftBlankAutomation", "LeftBlankMCPServer", "LeftBlankTestSupport"],
        ),
    ],
)
