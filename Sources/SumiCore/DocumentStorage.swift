import Foundation

public enum DocumentStorageError: LocalizedError {
    case externalChange
    case invalidUTF8
    public var errorDescription: String? {
        switch self {
        case .externalChange: "文件已被其他应用修改。你的内容已保留，请重新加载磁盘版本或另存为。"
        case .invalidUTF8: "无法读取此文件的文字编码，请使用 UTF-8 编码。"
        }
    }
}

public struct DiskBaseline: Sendable {
    public let data: Data?
    public init(data: Data?) { self.data = data }
}

public enum DocumentStorage {
    public static func read(_ url: URL) throws -> (String, DiskBaseline) {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw DocumentStorageError.invalidUTF8 }
        return (text, DiskBaseline(data: data))
    }

    public static func write(_ text: String, to url: URL, baseline: DiskBaseline?) throws -> DiskBaseline {
        if let baseline {
            let disk = try? Data(contentsOf: url)
            guard disk == baseline.data else { throw DocumentStorageError.externalChange }
        }
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
        return DiskBaseline(data: data)
    }
}

public struct RecoverySnapshot: Codable, Sendable {
    public let fileURL: URL?
    public let text: String
    public let savedText: String?
    public let selection: Int
    public let mainFileURL: URL?
    public init(fileURL: URL?, text: String, savedText: String?, selection: Int, mainFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.text = text
        self.savedText = savedText
        self.selection = selection
        self.mainFileURL = mainFileURL
    }
}
