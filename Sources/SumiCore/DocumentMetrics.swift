import Foundation

/// A single index per text revision; cursor movement never rescans the manuscript.
public struct DocumentMetrics: Sendable {
    public let wordCount: Int
    private let lines: TextLineIndex

    public init(_ text: String) {
        wordCount = text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
        lines = TextLineIndex(text)
    }

    public func position(at offset: Int) -> TextPosition {
        lines.position(at: offset)
    }

    public func offset(at position: TextPosition) -> Int { lines.offset(at: position) }
}
