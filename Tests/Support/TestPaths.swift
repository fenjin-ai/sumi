import CryptoKit
import Foundation

public enum TestPaths {
    /// Local fixtures live on the SSD even when Xcode overrides TMPDIR. A short,
    /// per-checkout directory also fits Darwin's 104-byte Unix socket path limit.
    /// Hosted CI keeps its fixtures inside the disposable checkout.
    public static let temporaryDirectory: URL = {
        #if os(iOS)
            // Device tests can write only inside their application sandbox.
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "leftblank-tests",
                isDirectory: true,
            )
        #else
            let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            let root: URL
            if checkout.path.hasPrefix("/Volumes/SSD/Developer/") {
                let fingerprint = SHA256.hash(data: Data(checkout.path.utf8)).prefix(8)
                    .map { String(format: "%02x", $0) }
                    .joined()
                root = URL(fileURLWithPath: "/Volumes/SSD/Developer/Codex/tmp", isDirectory: true)
                    .appendingPathComponent("leftblank-tests-" + fingerprint, isDirectory: true)
            } else {
                root = checkout.appendingPathComponent("build/test-tmp", isDirectory: true)
            }
        #endif
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()
}
