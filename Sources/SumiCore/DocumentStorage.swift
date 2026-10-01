import Foundation

public enum DocumentStorageError: LocalizedError {
    case externalChange
    case invalidUTF8
    public var errorDescription: String? {
        switch self {
        case .externalChange: L10n.text("Another app changed this file. Your work is safe; reload from disk or save a copy.")
        case .invalidUTF8: L10n.text("This file's text encoding is unsupported. Please use UTF-8.")
        }
    }
}

public struct DiskBaseline: Sendable {
    public let data: Data?
    public init(data: Data?) { self.data = data }
}

public enum DocumentStorage {
    public static func read(_ url: URL) throws -> (String, DiskBaseline) {
        try LibraryCloudEnvironment.requestDownloadIfNeeded(url)
        return try CoordinatedFileAccess.read(url) { coordinatedURL in
            let data = try Data(contentsOf: coordinatedURL)
            guard let text = String(data: data, encoding: .utf8) else { throw DocumentStorageError.invalidUTF8 }
            return (text, DiskBaseline(data: data))
        }
    }

    public static func write(_ text: String, to url: URL, baseline: DiskBaseline?) throws -> DiskBaseline {
        try LibraryCloudEnvironment.requestDownloadIfNeeded(url)
        return try CoordinatedFileAccess.write(url) { coordinatedURL in
            if let baseline {
                let disk = try? Data(contentsOf: coordinatedURL)
                guard disk == baseline.data else { throw DocumentStorageError.externalChange }
            }
            let values = try? coordinatedURL.resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey])
            if values?.ubiquitousItemHasUnresolvedConflicts == true { throw LibraryError.unresolvedConflict }
            let data = Data(text.utf8)
            try data.write(to: coordinatedURL, options: .atomic)
            return DiskBaseline(data: data)
        }
    }
}

public struct RecoverySnapshot: Codable, Sendable {
    public let fileURL: URL?
    public let text: String
    public let savedText: String?
    public let selection: Int
    public let mainFileURL: URL?
    public let libraryHome: Bool?
    public init(fileURL: URL?, text: String, savedText: String?, selection: Int, mainFileURL: URL? = nil, libraryHome: Bool? = nil) {
        self.fileURL = fileURL
        self.text = text
        self.savedText = savedText
        self.selection = selection
        self.mainFileURL = mainFileURL
        self.libraryHome = libraryHome
    }
}
