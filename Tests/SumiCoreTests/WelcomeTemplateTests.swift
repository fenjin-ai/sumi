import Foundation
import Testing
import SumiCore
import SumiTestSupport

@Test(.enabled(if: ProcessInfo.processInfo.environment["SUMI_INTEGRATION"] == "1"))
func bundledWelcomeCompilesWithFreshPackagesAndBlockedRegistry() throws {
    let root = TestPaths.temporaryDirectory.appendingPathComponent("welcome-offline-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let cache = root.appendingPathComponent("packages")
    try BundledPackages.prepare(in: cache, resources: repo.appendingPathComponent("Resources/Packages"))
    for language in [AppLanguage.english, .simplifiedChinese] {
        let input = root.appendingPathComponent("welcome-\(language.rawValue).typ")
        let output = input.deletingPathExtension().appendingPathExtension("pdf")
        let source = WelcomeDocument.source(language: language)
        #expect(source.contains("@preview/cetz:0.5.2"))
        #expect(source.contains("@preview/codly:1.3.0"))
        if language == .english {
            #expect(source == (try String(contentsOf: repo.appendingPathComponent("Examples/Welcome.typ"), encoding: .utf8)))
        }
        try Data(source.utf8).write(to: input)
        let process = Process()
        process.executableURL = repo.appendingPathComponent(".tools/tinymist")
        process.arguments = ["compile", "--package-path", root.appendingPathComponent("empty-local").path,
            "--package-cache-path", cache.path, input.path, output.path]
        var environment = ProcessInfo.processInfo.environment
        // Both the fresh cache and local package directory are isolated. A missing
        // transitive import fails rather than silently using a global cache/network.
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            environment[key] = "http://127.0.0.1:9"
        }
        environment["NO_PROXY"] = ""; environment["no_proxy"] = ""
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try Data(contentsOf: output).starts(with: Data("%PDF".utf8)))
    }
    #expect(WelcomeDocument.thumbnailURL != nil)
    #expect(BuiltInTemplate.welcome.matches("欢迎 公式"))
    #expect(BuiltInTemplate.blank.matches("空白"))
    #expect(!BuiltInTemplate.blank.matches("resume"))
}
