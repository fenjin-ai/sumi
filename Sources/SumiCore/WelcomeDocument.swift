import Foundation

/// Localized starter content is chosen only when a document is created.
/// Existing manuscripts are never retranslated when the interface changes.
public enum WelcomeDocument {
    public static func source(language: AppLanguage? = nil) -> String {
        let suffix = AppLanguage.resolve(language ?? L10n.language) == .simplifiedChinese ? ".zh-Hans" : ""
        guard let url = L10n.resourceBundle.url(forResource: "Welcome" + suffix, withExtension: "typ"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return DocumentTemplate.blank.source }
        return source
    }

    public static var thumbnailURL: URL? {
        L10n.resourceBundle.url(forResource: "welcome-cover", withExtension: "png")
    }
}
