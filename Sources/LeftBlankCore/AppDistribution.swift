import Foundation

/// Distribution identity is compiled into the app and its MCP helper together.
/// Local state stays separate; both distributions can use the shared iCloud library.
public enum AppDistribution: Sendable {
    case standard, preview

    public static var current: Self {
        #if LEFTBLANK_PREVIEW
        .preview
        #else
        .standard
        #endif
    }

    public var bundleIdentifier: String { self == .preview ? "app.leftblank.writer.preview" : "app.leftblank.writer" }
    public var applicationName: String { self == .preview ? L10n.text("LeftBlank Preview") : L10n.text("LeftBlank") }
    public var stateFolderName: String { self == .preview ? "LeftBlank Preview" : "LeftBlank" }
    public var agentName: String { self == .preview ? "leftblank-preview" : "leftblank" }

    public func stateDirectory(applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(stateFolderName, isDirectory: true)
    }

    public static var defaultStateDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["LEFTBLANK_STATE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return current.stateDirectory(applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }
}
