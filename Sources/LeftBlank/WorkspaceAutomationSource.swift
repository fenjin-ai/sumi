import AppKit
import LeftBlankAutomation
import LeftBlankCore

extension WorkspaceAutomation {
    func readDocument(_ args: JSONValue, workspace: Workspace) throws -> JSONValue {
        _ = try snapshot(workspace)
        if !args["document_id"].isNull {
            try requireCurrent(args, workspace: workspace)
        }
        var result = metadata(workspace)
        try result.merge(sourceSlice(workspace.text, args: args), uniquingKeysWith: { _, new in new })
        return .object(result)
    }

    func sourceSlice(_ text: String, args: JSONValue) throws -> [String: JSONValue] {
        let line = try integer(args, "start_line", default: 1, range: 1 ... Int.max)
        let count = try integer(args, "line_count", default: 100, range: 1 ... 200)
        let character = try integer(args, "start_character", default: 0, range: 0 ... Int.max)
        let source = text as NSString, index = TextLineIndex(text)
        let total = index.position(at: source.length).line + 1
        guard line <= total else {
            throw AutomationFailure("invalid_range", "start_line is beyond the document.")
        }
        let contentStart = index.offset(at: .init(line: line - 1, character: 0))
        let contentEnd = index.offset(at: .init(line: line - 1, character: Int.max))
        guard character <= contentEnd - contentStart,
              String
              .Index(text.utf16.index(text.utf16.startIndex, offsetBy: contentStart + character), within: text) != nil
        else {
            throw AutomationFailure("invalid_range", "start_character must be a valid UTF-16 boundary on start_line.")
        }
        var text = "", returned = 0, nextLine: Int?, nextCharacter: Int?
        for current in (line - 1) ..< min(total, line - 1 + count) {
            let start = index.offset(at: .init(line: current, character: current == line - 1 ? character : 0))
            let end = current + 1 < total ? index.offset(at: .init(line: current + 1, character: 0)) : source.length
            let fragment = source.substring(with: NSRange(location: start, length: end - start))
            let remaining = AutomationContract.maximumReadBytes - text.utf8.count
            if fragment.utf8.count > remaining {
                if text.isEmpty {
                    var prefix = boundedPrefix(fragment, bytes: remaining)
                    // Do not split a CRLF terminator across read calls.
                    if prefix.hasSuffix("\r") {
                        prefix.removeLast()
                    }
                    text = prefix
                    returned = 1
                    nextCharacter = character + prefix.utf16.count
                }
                nextLine = current + 1
                break
            }
            text += fragment
            returned += 1
            if current + 1 < total {
                nextLine = current + 2
            } else {
                nextLine = nil
            }
        }
        return ["text": .string(text), "start_line": .number(Double(line)),
                "start_character": .number(Double(character)), "line_count": .number(Double(returned)),
                "total_lines": .number(Double(total)),
                "next_line": nextLine.map { .number(Double($0)) } ?? .null,
                "next_character": nextCharacter.map { .number(Double($0)) } ?? .null,
                "truncated": .bool(nextLine != nil)]
    }

    func outline(_ args: JSONValue, workspace: Workspace) throws -> JSONValue {
        try requireCurrent(args, workspace: workspace)
        let page = try pagination(args, count: workspace.outline.count, defaultLimit: 50, maximum: 100)
        let index = TextLineIndex(workspace.text)
        let headings: [JSONValue] = workspace.outline[page.range].map { item in
            let position = index.position(at: item.offset)
            return .object(["title": .string(boundedPrefix(item.title, bytes: 512)),
                            "level": .number(Double(item.level)), "line": .number(Double(position.line + 1)),
                            "character": .number(Double(position.character)), "start": .number(Double(item.offset))])
        }
        var result = metadata(workspace)
        result["headings"] = .array(headings)
        result["next_cursor"] = page.next
        return .object(result)
    }

    func search(_ args: JSONValue, workspace: Workspace) throws -> JSONValue {
        try requireCurrent(args, workspace: workspace)
        guard let query = args["query"].string, !query.isEmpty, query.utf8.count <= 1024 else {
            throw AutomationFailure("invalid_arguments", "query must contain between 1 and 1024 UTF-8 bytes.")
        }
        let sensitive: Bool
        if args["case_sensitive"].isNull {
            sensitive = false
        } else if case let .bool(value) = args["case_sensitive"] {
            sensitive = value
        } else {
            throw AutomationFailure("invalid_arguments", "case_sensitive must be a boolean.")
        }
        let limit = try integer(args, "limit", default: 20, range: 1 ... 50)
        let cursor = try cursorOffset(args)
        let source = workspace.text as NSString, index = TextLineIndex(workspace.text)
        let options: NSString.CompareOptions = sensitive ? [.literal] : [.literal, .caseInsensitive]
        var offset = 0, skipped = 0, matches: [JSONValue] = [], next: JSONValue = .null
        while offset < source.length {
            let match = source.range(
                of: query,
                options: options,
                range: NSRange(location: offset, length: source.length - offset),
            )
            guard match.location != NSNotFound else {
                break
            }
            offset = NSMaxRange(match)
            if skipped < cursor {
                skipped += 1
                continue
            }
            if matches.count == limit {
                next = .string(String(cursor + limit))
                break
            }
            let position = index.position(at: match.location)
            let lineStart = index.offset(at: .init(line: position.line, character: 0))
            let lineEnd = index.offset(at: .init(line: position.line, character: Int.max))
            var snippetStart = max(lineStart, match.location - 80)
            while String.Index(
                workspace.text.utf16.index(workspace.text.utf16.startIndex, offsetBy: snippetStart),
                within: workspace.text,
            ) == nil {
                snippetStart += 1
            }
            let snippet = source.substring(with: NSRange(location: snippetStart, length: lineEnd - snippetStart))
            matches.append(.object(["line": .number(Double(position.line + 1)),
                                    "character": .number(Double(position.character)),
                                    "start": .number(Double(match.location)), "end": .number(Double(NSMaxRange(match))),
                                    "text": .string(boundedPrefix(snippet, bytes: 256))]))
        }
        guard skipped == cursor else {
            throw AutomationFailure(
                "invalid_cursor",
                "The search cursor is beyond the results.",
            )
        }
        var result = metadata(workspace)
        result["matches"] = .array(matches)
        result["next_cursor"] = next
        return .object(result)
    }

    func listFiles(_ args: JSONValue, workspace: Workspace) throws -> JSONValue {
        try requireCurrent(args, workspace: workspace)
        let files = try projectFiles(workspace)
        let page = try pagination(args, count: files.count, defaultLimit: 50, maximum: 100)
        return try .object(["document_id": .string(documentID), "revision": .string(revision(workspace)),
                            "files": .array(files[page.range].map { url in
                                let root = workspace.resourceRoot.standardizedFileURL
                                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                                return .object(["file_id": .string(fileID(url)),
                                                "path": .string(String(url.path.dropFirst(root.path.count + 1))),
                                                "kind": .string(url.pathExtension
                                                    .lowercased() == "typ" ? "source" : "resource"),
                                                "size": .number(Double(values.fileSize ?? 0)),
                                                "active": .bool(url == workspace.documentURL.standardizedFileURL),
                                                "main": .bool(url == workspace.compilationURL.standardizedFileURL)])
                            }), "next_cursor": page.next])
    }

    func openFile(_ args: JSONValue, workspace: Workspace) throws -> JSONValue {
        try requireEditable(workspace)
        try requireCurrent(args, workspace: workspace)
        guard let id = args["file_id"].string,
              let url = try projectFiles(workspace).first(where: { fileID($0) == id }),
              url.pathExtension.lowercased() == "typ"
        else {
            throw AutomationFailure("file_not_found", "Choose a source file_id from list_files.")
        }
        if url != workspace.documentURL.standardizedFileURL, !workspace.open(url, preservingMain: true) {
            throw AutomationFailure(
                "open_failed",
                "The source file could not be opened or the current buffer preserved.",
            )
        }
        return try snapshot(workspace)
    }

    func createFile(_ args: JSONValue, workspace: Workspace) throws -> JSONValue {
        try requireEditable(workspace)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        guard let path = args["path"].string, let text = args["text"].string,
              text.utf8.count <= AutomationContract.maximumSourceBytes,
              (path as NSString).pathExtension.lowercased() == "typ"
        else {
            throw AutomationFailure("invalid_arguments", "Provide a relative .typ path and source up to 2 MiB.")
        }
        let url = try projectURL(path, workspace: workspace)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw AutomationFailure("file_exists", "That project file already exists.")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Recheck existing components after directory creation before writing.
        _ = try projectURL(path, workspace: workspace)
        try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        projectChanged(workspace)
        return .object(["document_id": .string(documentID), "revision": .string(revision(workspace)),
                        "file_id": .string(fileID(url)), "path": .string(path)])
    }

    func formatSource(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        try requireEditable(workspace)
        guard workspace.serviceReady, let editor = workspace.editor else {
            throw AutomationFailure("editor_busy", "Wait for the typesetting service to be ready.")
        }
        let generation = accessGeneration
        let formatted: String
        do { formatted = try await workspace.formattedSource() }
        catch {
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            throw AutomationFailure("format_failed", error.localizedDescription)
        }
        try requireAccess(generation)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        try requireEditable(workspace)
        guard formatted.utf8.count <= max(AutomationContract.maximumSourceBytes, workspace.text.utf8.count) else {
            throw AutomationFailure("document_too_large", "Agent formatting cannot grow source beyond 2 MiB.")
        }
        if formatted != workspace.text {
            workspace.closePalette()
            if workspace.layout == .preview {
                workspace.layout = .split
            }
            editor.insertSnippet(
                Snippet(text: formatted),
                replacing: NSRange(location: 0, length: workspace.text.utf16.count),
            )
            editor.undoManager?.setActionName(L10n.text("Agent Edit"))
            guard workspace.text == formatted else {
                throw AutomationFailure("edit_rejected", "The editor did not accept the formatted source.")
            }
        }
        return try snapshot(workspace)
    }

    func projectURL(_ path: String, workspace: Workspace) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 512, !path.hasPrefix("/"),
              !path.contains("\\"), !path.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") })
        else {
            throw AutomationFailure(
                "invalid_path",
                "Use a relative project path without hidden, empty, . or .. components.",
            )
        }
        let root = workspace.resourceRoot.standardizedFileURL
        guard root.resolvingSymlinksInPath() == root else {
            throw AutomationFailure("invalid_path", "The project root must not traverse symbolic links.")
        }
        var candidate = root
        for component in components {
            candidate.appendPathComponent(String(component))
            if let type = try? FileManager.default.attributesOfItem(atPath: candidate.path)[.type],
               type as? FileAttributeType == .typeSymbolicLink
            {
                throw AutomationFailure("invalid_path", "Project paths must not traverse symbolic links.")
            }
        }
        return candidate.standardizedFileURL
    }

    func projectFiles(_ workspace: Workspace) throws -> [URL] {
        let root = workspace.resourceRoot.standardizedFileURL
        guard root.resolvingSymlinksInPath() == root else {
            throw AutomationFailure("invalid_path", "The project root must not traverse symbolic links.")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        )
        else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true || url.standardizedFileURL == workspace.stateDirectory
                .standardizedFileURL
            {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                let path = String(url.path.dropFirst(root.path.count + 1))
                _ = try projectURL(path, workspace: workspace)
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    func integer(_ args: JSONValue, _ key: String, default value: Int, range: ClosedRange<Int>) throws -> Int {
        if args[key].isNull {
            return value
        }
        guard let result = args[key].int, range.contains(result) else {
            throw AutomationFailure(
                "invalid_arguments",
                "\(key) must be an integer from \(range.lowerBound) to \(range.upperBound).",
            )
        }
        return result
    }

    func cursorOffset(_ args: JSONValue) throws -> Int {
        if args["cursor"].isNull {
            return 0
        }
        guard let value = args["cursor"].string, let cursor = Int(value), cursor >= 0 else {
            throw AutomationFailure("invalid_cursor", "cursor must be a nonnegative offset from the previous result.")
        }
        return cursor
    }

    func pagination(_ args: JSONValue, count: Int, defaultLimit: Int, maximum: Int) throws
        -> (range: Range<Int>, next: JSONValue)
    {
        let cursor = try cursorOffset(args), limit = try integer(
            args,
            "limit",
            default: defaultLimit,
            range: 1 ... maximum,
        )
        guard cursor <= count else {
            throw AutomationFailure("invalid_cursor", "The cursor is beyond the results.")
        }
        let end = cursor + min(limit, count - cursor)
        return (cursor ..< end, end < count ? .string(String(end)) : .null)
    }

    func boundedPrefix(_ text: String, bytes: Int) -> String {
        var end = text.startIndex, used = 0
        for scalar in text.unicodeScalars {
            let count = scalar.utf8.count
            guard used + count <= bytes else {
                break
            }
            used += count
            end = text.unicodeScalars.index(after: end)
        }
        return String(text[..<end])
    }
}
