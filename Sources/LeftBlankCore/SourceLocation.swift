import Foundation

/// LSP source navigation, shared by the platform editors. Columns use UTF-16.
public struct SourceLocation: Equatable, Sendable {
    public let url: URL
    public let position: TextPosition

    public init?(_ params: JSONValue) {
        guard let uri = params["uri"].string, let url = URL(string: uri), url.isFileURL else {
            return nil
        }
        self.url = url
        let start = params["selection"]["start"]
        position = TextPosition(line: max(0, start["line"].int ?? 0), character: max(0, start["character"].int ?? 0))
    }
}
