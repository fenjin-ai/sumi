import Foundation

/// Distribution identity is compiled into the app and its MCP helper together.
/// Preview builds never adopt a production library or its cloud container.
public enum AppDistribution: Sendable {
    case standard, preview

    public static var current: Self {
        #if SUMI_PREVIEW
        .preview
        #else
        .standard
        #endif
    }

    public var bundleIdentifier: String { self == .preview ? "app.sumi.writer.preview" : "app.sumi.writer" }
    public var applicationName: String { self == .preview ? L10n.text("Sumi Preview") : L10n.text("Sumi") }
    public var stateFolderName: String { self == .preview ? "Sumi Preview" : "Sumi" }
    public var agentName: String { self == .preview ? "sumi-preview" : "sumi" }
    public var supportsICloud: Bool { self == .standard }

    public func stateDirectory(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(stateFolderName, isDirectory: true)
    }

    public static var defaultStateDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SUMI_STATE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return current.stateDirectory(applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
}
