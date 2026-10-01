import Foundation

/// A single index per text revision; cursor movement never rescans the manuscript.
public struct DocumentMetrics: Sendable {
    public let wordCount: Int
    private let lineStarts: [Int]
    private let length: Int

    public init(_ text: String) {
        wordCount = text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
        var starts = [0]
        var count = 0
        for unit in text.utf16 {
            count += 1
            if unit == 10 { starts.append(count) }
        }
        lineStarts = starts
        length = count
    }

    public func position(at offset: Int) -> TextPosition {
        let offset = min(max(0, offset), length)
        var low = 0, high = lineStarts.count
        while low + 1 < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid }
        }
        return TextPosition(line: low, character: offset - lineStarts[low])
    }
}
