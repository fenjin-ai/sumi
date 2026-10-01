import Foundation

public enum TestPaths {
    /// Keep fixtures beside the checkout. Xcode's test runner can override TMPDIR,
    /// so Foundation.temporaryDirectory is not a reliable development destination.
    public static let temporaryDirectory: URL = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/test-tmp", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()
}
