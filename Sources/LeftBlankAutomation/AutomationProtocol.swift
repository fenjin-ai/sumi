import CryptoKit
import Foundation
import LeftBlankCore

/// Private app/helper protocol. MCP stays in the helper, not in the editor process.
public struct AutomationRequest: Codable, Sendable {
    public var operation: String
    public var arguments: JSONValue
    public init(_ operation: String, arguments: JSONValue = .object([:])) {
        self.operation = operation
        self.arguments = arguments
    }
}

public struct AutomationFailure: Error, Codable, Sendable, LocalizedError {
    public var code: String
    public var message: String
    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

public struct AutomationResponse: Codable, Sendable {
    public var result: JSONValue?
    public var error: AutomationFailure?
    public init(result: JSONValue) {
        self.result = result
    }

    public init(error: AutomationFailure) {
        self.error = error
    }

    public func value() throws -> JSONValue {
        if let error {
            throw error
        }
        return result ?? .null
    }
}

public struct AutomationDocument: Codable, Sendable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum AutomationContract {
    public static let maximumMessageBytes = 8 * 1024 * 1024
    public static let maximumSourceBytes = 2 * 1024 * 1024
    public static let maximumReadBytes = 16 * 1024
    public static func revision(documentID: String, text: String) -> String {
        let digest = SHA256.hash(data: Data((documentID + "\0" + text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func encode(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    /// Validate every edit before applying any. UTF-16 matches AppKit and the LSP.
    public static func replacing(_ edits: JSONValue, in text: String) throws -> String {
        guard case let .array(entries) = edits, !entries.isEmpty, entries.count <= 100 else {
            throw AutomationFailure("invalid_edits", "Provide between 1 and 100 edits.")
        }
        let utf16 = text.utf16
        let replacements: [(NSRange, String)] = try entries.map { entry in
            guard let start = entry["start"].int, let end = entry["end"].int,
                  let replacement = entry["text"].string,
                  start >= 0, end >= start, end <= utf16.count,
                  String.Index(utf16.index(utf16.startIndex, offsetBy: start), within: text) != nil,
                  String.Index(utf16.index(utf16.startIndex, offsetBy: end), within: text) != nil
            else {
                throw AutomationFailure(
                    "invalid_range",
                    "Edit ranges must be valid UTF-16 boundaries in the current document.",
                )
            }
            return (NSRange(location: start, length: end - start), replacement)
        }
        return try replacing(replacements, in: text)
    }

    /// Locate every replacement in the original revision before making any change.
    public static func replacingText(_ edits: JSONValue, in text: String) throws -> String {
        guard case let .array(entries) = edits, !entries.isEmpty, entries.count <= 100 else {
            throw AutomationFailure("invalid_edits", "Provide between 1 and 100 edits.")
        }
        let source = text as NSString
        let replacements: [(NSRange, String)] = try entries.map { entry in
            guard let old = entry["old_text"].string, !old.isEmpty,
                  let replacement = entry["new_text"].string
            else {
                throw AutomationFailure("invalid_edits", "Each edit requires nonempty old_text and new_text.")
            }
            let first = source.range(of: old, options: .literal)
            guard first.location != NSNotFound else {
                throw AutomationFailure(
                    "edit_not_found",
                    "old_text was not found. Search the current document and retry.",
                )
            }
            let after = first.location + 1
            let second = source.range(
                of: old,
                options: .literal,
                range: NSRange(location: after, length: source.length - after),
            )
            guard second.location == NSNotFound else {
                throw AutomationFailure(
                    "ambiguous_text",
                    "old_text matches more than once. Include unique surrounding text.",
                )
            }
            return (first, replacement)
        }
        return try replacing(replacements, in: text)
    }

    private static func replacing(_ replacements: [(NSRange, String)], in text: String) throws -> String {
        let sorted = replacements.sorted { $0.0.location < $1.0.location }
        for pair in zip(sorted, sorted.dropFirst())
            where NSMaxRange(pair.0.0) > pair.1.0.location || pair.0.0.location == pair.1.0.location
        {
            throw AutomationFailure("overlapping_edits", "Edits must not overlap or start at the same offset.")
        }
        let result = NSMutableString(string: text)
        for (range, replacement) in sorted.reversed() {
            result.replaceCharacters(in: range, with: replacement)
        }
        let value = result as String
        guard value.utf8.count <= max(maximumSourceBytes, text.utf8.count) else {
            throw AutomationFailure("document_too_large", "Agent edits cannot grow source beyond 2 MiB.")
        }
        return value
    }

    public static var defaultStateDirectory: URL {
        AppDistribution.defaultStateDirectory
    }

    public static func groupSocketURL(in container: URL, preview: Bool) -> URL {
        container.appendingPathComponent("Agents", isDirectory: true)
            .appendingPathComponent(preview ? "p.sock" : "s.sock")
    }

    public static func socketURL(in stateDirectory: URL) -> URL {
        let endpoint = stateDirectory.appendingPathComponent("Agents", isDirectory: true)
            .appendingPathComponent("bridge.sock")
        guard endpoint.path.utf8.count >= 104,
              let containers = stateDirectory.path.range(of: "/Library/Containers/"),
              let data = stateDirectory.path.range(
                  of: "/Data/",
                  range: containers.upperBound ..< stateDirectory.path.endIndex,
              )
        else {
            return endpoint
        }
        // Darwin's sockaddr_un holds 104 bytes. Keep the endpoint inside the same sandbox container.
        let container = URL(fileURLWithPath: String(stateDirectory.path[..<data.upperBound]), isDirectory: true)
        return container.appendingPathComponent("Agents", isDirectory: true).appendingPathComponent("bridge.sock")
    }
}
