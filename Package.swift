// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sumi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sumi", targets: ["Sumi"])],
    targets: [
        .target(name: "SumiCore"),
        .executableTarget(name: "Sumi", dependencies: ["SumiCore"]),
        .testTarget(name: "SumiCoreTests", dependencies: ["SumiCore"])
    ]
)
