// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sumi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sumi", targets: ["SumiLauncher"])],
    targets: [
        .target(name: "SumiCore"),
        .target(name: "SumiApp", dependencies: ["SumiCore"], path: "Sources/Sumi"),
        .executableTarget(name: "SumiLauncher", dependencies: ["SumiApp"]),
        .testTarget(name: "SumiCoreTests", dependencies: ["SumiCore"]),
        .testTarget(name: "SumiAppTests", dependencies: ["SumiApp", "SumiCore"])
    ]
)
