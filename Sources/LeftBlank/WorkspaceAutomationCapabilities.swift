import AppKit
import LeftBlankAutomation
import LeftBlankCore

extension WorkspaceAutomation {
    func handleCapabilities(_ operation: String, _ args: JSONValue, workspace: Workspace) async throws -> JSONValue? {
        do {
            switch operation {
            case "list_documents": return try await listDocuments(args, workspace: workspace)
            case "rename_document", "trash_document", "restore_document":
                return try await changeLibraryDocument(operation, args, workspace: workspace)
            case "list_resources": return try await listResources(args, workspace: workspace)
            case "import_resource": return try await importResource(args, workspace: workspace)
            case "export_project": return try await exportProject(args, workspace: workspace)
            case "list_history", "get_history", "restore_history":
                return try await accessHistory(operation, args, workspace: workspace)
            case "list_templates", "list_packages":
                return try await listCatalog(operation, args, workspace: workspace)
            case "create_from_template": return try await createFromTemplate(args, workspace: workspace)
            case "import_package": return try await importPackage(args, workspace: workspace)
            default: return nil
            }
        } catch let failure as AutomationFailure {
            throw failure
        } catch let error as LibraryError {
            let code = switch error {
            case .notFound: "document_not_found"
            case .invalidTitle: "invalid_arguments"
            case .libraryChanged: "document_changed"
            case .unresolvedConflict: "save_conflict"
            case .unsafeResource, .invalidProject: "unsafe_resource"
            default: "library_unavailable"
            }
            throw AutomationFailure(code, error.localizedDescription)
        } catch let error as DocumentResourceError {
            throw AutomationFailure("invalid_resource", error.localizedDescription)
        } catch let error as HistoryError {
            throw AutomationFailure("history_unavailable", error.localizedDescription)
        }
    }

    private func listDocuments(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        let query = try boundedQuery(args)
        let trashed = try booleanArgument(args, "trashed", default: false)
        let stored = try await workspace.library.store.list(query: query, includeTrashed: trashed)
            .filter { $0.isTrashed == trashed }
        var documents = stored.map(libraryMetadata)
        if !trashed {
            if let library {
                let extra = try await library.list(query)
                let known = Set(stored.map(\.id.uuidString))
                documents += extra.filter { !known.contains($0.id) }.map {
                    .object(["id": .string($0.id), "title": .string($0.title), "trashed": .bool(false)])
                }
            } else if workspace.managedDocumentID == nil, !workspace.isLibraryHome,
                      query.isEmpty || workspace.title.localizedCaseInsensitiveContains(query)
            {
                documents.append(.object([
                    "id": .string(documentID), "title": .string(workspace.title), "trashed": .bool(false),
                ]))
            }
        }
        let signature = query + ":" + String(trashed) + ":" + documents.map {
            ($0["id"].string ?? "") + ($0["modified_at"].string ?? "")
        }.joined(separator: ",")
        var result = try page(documents, key: "documents", args: args, signature: signature)
        result["active_document_id"] = workspace.isLibraryHome ? .null : .string(documentID)
        return .object(result)
    }

    private func changeLibraryDocument(
        _ operation: String, _ args: JSONValue, workspace: Workspace,
    ) async throws -> JSONValue {
        try requireEditable(workspace)
        guard !workspace.library.busy else {
            throw AutomationFailure("editor_busy", "Another library operation is in progress.")
        }
        let id = try managedID(args)
        switch operation {
        case "rename_document":
            guard let title = args["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 200
            else {
                throw AutomationFailure("invalid_arguments", "Provide a title between 1 and 200 characters.")
            }
            try await workspace.library.rename(id, title: title)
        case "trash_document":
            if workspace.managedDocumentID == id {
                try requireCurrent(args, workspace: workspace, revisionRequired: true)
            }
            try await workspace.library.moveToTrash(id)
        default: try await workspace.library.restore(id)
        }
        let result = try await workspace.library.store.read(id)
        var metadata: [String: JSONValue] = [
            "document_id": .string(id.uuidString), "title": .string(result.document.title),
            "trashed": .bool(result.document.isTrashed),
            "active_document_id": workspace.isLibraryHome ? .null : .string(documentID),
        ]
        if workspace.managedDocumentID == id, !workspace.isLibraryHome {
            metadata["revision"] = .string(revision(workspace))
        }
        return .object(metadata)
    }

    private func listResources(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireCurrent(args, workspace: workspace)
        let expected = revision(workspace)
        let resources = try await workspace.resourceStore.list(
            kind: resourceKind(args), in: workspace.resourceRoot, relativeTo: workspace.documentURL,
        )
        try requireCurrent(args, workspace: workspace)
        guard revision(workspace) == expected else {
            throw AutomationFailure("revision_conflict", "The document changed while listing resources. Read it again.")
        }
        var result = try page(
            resources.map { resourceMetadata($0) }, key: "resources", args: args,
            signature: expected + (args["kind"].string ?? "") + resources.map(\.relativePath).joined(separator: ","),
        )
        result["document_id"] = .string(documentID)
        result["revision"] = .string(expected)
        return .object(result)
    }

    private func importResource(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireEditable(workspace)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        let kind = try resourceKind(args)
        guard let name = args["name"].string, let encoded = args["data_base64"].string,
              encoded.utf8.count <= 5_592_408, let bytes = Data(base64Encoded: encoded),
              !bytes.isEmpty, bytes.count <= 4 * 1024 * 1024
        else {
            throw AutomationFailure("invalid_resource", "Provide a named resource containing between 1 byte and 4 MiB.")
        }
        if kind != .image, String(data: bytes, encoding: .utf8) == nil {
            throw AutomationFailure("invalid_resource", "Bibliography and Typst resources must contain UTF-8 text.")
        }
        if kind == .document || kind == .module, bytes.count > AutomationContract.maximumSourceBytes {
            throw AutomationFailure("document_too_large", "Typst source imports are limited to 2 MiB.")
        }
        let generation = accessGeneration
        let resources = try await workspace.resourceStore.importResources(
            [.data(name: name, bytes: bytes)], kind: kind, in: workspace.resourceRoot,
            relativeTo: workspace.documentURL,
        )
        do {
            try requireAccess(generation)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            try requireEditable(workspace)
            guard enabled else {
                throw AutomationFailure("access_disabled", "Agent Access was disabled during import.")
            }
        } catch {
            try? await workspace.resourceStore.discardImport(resources)
            throw error
        }
        guard let resource = resources.first else {
            throw AutomationFailure("invalid_resource", "The resource could not be imported.")
        }
        projectChanged(workspace)
        workspace.recordOperation("agent.resourceImported", ["kind": args["kind"].string ?? ""])
        var result = resourceFields(resource)
        result["document_id"] = .string(documentID)
        result["revision"] = .string(revision(workspace))
        return .object(result)
    }

    private func exportProject(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireEditable(workspace)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        let id = try managedID(args)
        guard workspace.managedDocumentID == id else {
            throw AutomationFailure("document_changed", "Open this library document before exporting its project.")
        }
        let directory = exportDirectory.standardizedFileURL
        guard directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path else {
            throw AutomationFailure("unsafe_resource", "The export directory must not be a symbolic link.")
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700],
        )
        let destination = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try await workspace.library.exportProject(id, to: destination)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            guard enabled else {
                throw AutomationFailure("access_disabled", "Agent Access was disabled during export.")
            }
            return .object([
                "document_id": .string(documentID), "revision": .string(revision(workspace)),
                "path": .string(destination.path), "uri": .string(destination.absoluteString),
            ])
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func accessHistory(_ operation: String, _ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireCurrent(args, workspace: workspace, revisionRequired: operation == "restore_history")
        let key = workspace.historyKey, expected = revision(workspace)
        if operation == "restore_history" {
            try requireEditable(workspace)
            guard workspace.editor != nil else {
                throw AutomationFailure("editor_unavailable", "The editor is not ready.")
            }
        }
        workspace.history.flush(current: workspace.text)
        await workspace.history.drain()
        let revisions = try await workspace.history.store.revisions(for: key)
        try requireCurrent(args, workspace: workspace)
        guard workspace.historyKey == key, revision(workspace) == expected else {
            throw AutomationFailure("revision_conflict", "The document changed while reading history. Read it again.")
        }
        if operation == "list_history" {
            var result = try page(revisions.map { entry in
                .object([
                    "revision_id": .string(entry.id.uuidString), "created_at": .string(dateString(entry.createdAt)),
                    "bytes": .number(Double(entry.bytes)), "reason": .string(entry.reason.rawValue),
                ])
            }, key: "revisions", args: args, signature: expected + revisions.map(\.id.uuidString).joined())
            result["document_id"] = .string(documentID)
            result["revision"] = .string(expected)
            return .object(result)
        }
        guard let requested = args["revision_id"].string.flatMap(UUID.init(uuidString:)),
              let entry = revisions.first(where: { $0.id == requested })
        else {
            throw AutomationFailure("history_unavailable", "Choose a revision_id from this document's history.")
        }
        if operation == "restore_history" {
            return try await restoreHistory(entry, args, workspace: workspace)
        }
        let source = try await workspace.history.store.source(for: entry, key: key)
        try requireCurrent(args, workspace: workspace)
        guard workspace.historyKey == key, revision(workspace) == expected else {
            throw AutomationFailure("revision_conflict", "The document changed while reading history. Read it again.")
        }
        var result = try sourceSlice(source, args: args)
        result["document_id"] = .string(documentID)
        result["revision"] = .string(expected)
        result["revision_id"] = .string(entry.id.uuidString)
        return .object(result)
    }

    private func restoreHistory(
        _ entry: DocumentRevision, _ args: JSONValue, workspace: Workspace,
    ) async throws -> JSONValue {
        let generation = accessGeneration
        let key = workspace.historyKey, previous = workspace.text
        let restored = try await workspace.history.store.source(for: entry, key: key)
        guard restored.utf8.count <= AutomationContract.maximumSourceBytes else {
            throw AutomationFailure("document_too_large", "Agent history restores are limited to 2 MiB of source.")
        }
        if restored != previous {
            try await workspace.history.store.preserveBeforeRestore(previous, key: key, at: workspace.history.now())
        }
        try requireAccess(generation)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        try requireEditable(workspace)
        guard enabled, workspace.historyKey == key, let editor = workspace.editor else {
            throw AutomationFailure("access_disabled", "Agent Access or the document changed during restoration.")
        }
        if restored != previous {
            workspace.closePalette()
            if workspace.layout == .preview {
                workspace.layout = .split
            }
            editor.insertSnippet(Snippet(text: restored), replacing: NSRange(location: 0, length: previous.utf16.count))
            editor.undoManager?.setActionName(L10n.text("Restore Snapshot"))
            guard workspace.text == restored else {
                throw AutomationFailure("edit_rejected", "The editor did not accept this history snapshot.")
            }
            workspace.historyOpen = false
            workspace.recordOperation("history.restored")
        }
        return try snapshot(workspace)
    }

    private func listCatalog(_ operation: String, _ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        let query = try boundedQuery(args)
        let catalog = await offlineCatalog(workspace)
        let templates = operation == "list_templates"
        var items: [JSONValue] = templates ? BuiltInTemplate.allCases.filter { $0.matches(query) }.map {
            .object(["template_id": .string("builtin:" + $0.rawValue), "title": .string($0.title),
                     "kind": .string("builtin")])
        } : []
        let packages = catalog?.discover(query, mode: templates ? .templates : .packages) ?? []
        items += packages.map { package in
            .object([
                templates ? "template_id" : "package_id": .string(package.reference),
                "title": .string(package.name), "version": .string(package.version), "kind": .string("universe"),
                "description": .string(String(package.description.prefix(300))),
                "reference": .string(package.reference),
                "documentation_url": .string(package.documentationURL.absoluteString),
                "compatible": .bool(package.isCompatible(with: "0.15.1")),
            ])
        }
        let key = templates ? "templates" : "packages"
        return try .object(page(items, key: key, args: args, signature: operation + query + items.map {
            $0[templates ? "template_id" : "package_id"].string ?? ""
        }.joined(separator: ",")))
    }

    private func createFromTemplate(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireEditable(workspace)
        guard !workspace.library.busy, let id = args["template_id"].string else {
            throw AutomationFailure("invalid_arguments", "Choose a template_id from list_templates.")
        }
        if !args["title"].isNull {
            guard let title = args["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 200
            else {
                throw AutomationFailure("invalid_arguments", "Provide a title between 1 and 200 characters.")
            }
        }
        if id.hasPrefix("builtin:"), let template = BuiltInTemplate(rawValue: String(id.dropFirst(8))) {
            try await workspace.library.create(builtIn: template)
        } else {
            let package = try await catalogPackage(id, workspace: workspace)
            try requireEditable(workspace)
            guard package.isTemplate else {
                throw AutomationFailure("invalid_template", "This package does not provide a document template.")
            }
            try await workspace.library.create(from: package)
        }
        try requireEditable(workspace)
        if let title = args["title"].string, let id = workspace.managedDocumentID {
            try await workspace.library.rename(id, title: title)
        }
        return try snapshot(workspace)
    }

    private func importPackage(_ args: JSONValue, workspace: Workspace) async throws -> JSONValue {
        try requireEditable(workspace)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        guard let id = args["package_id"].string else {
            throw AutomationFailure("invalid_arguments", "Choose a package_id from list_packages.")
        }
        let generation = accessGeneration
        let package = try await catalogPackage(id, workspace: workspace)
        try requireAccess(generation)
        try requireCurrent(args, workspace: workspace, revisionRequired: true)
        try requireEditable(workspace)
        guard package.isCompatible(with: "0.15.1") else {
            throw AutomationFailure("incompatible_package", "This package requires a newer Typst version.")
        }
        guard !workspace.text.contains(TypstInsertion.quoted(package.reference)) else {
            throw AutomationFailure("package_already_imported", "This package version is already imported.")
        }
        guard workspace.editor != nil else {
            throw AutomationFailure("editor_unavailable", "The editor is not ready.")
        }
        try workspace.importPackage(package)
        workspace.editor?.undoManager?.setActionName(L10n.text("Agent Edit"))
        return try snapshot(workspace)
    }

    private func offlineCatalog(_ workspace: Workspace) async -> UniverseCatalogSnapshot? {
        let store = UniverseCatalogStore(cacheURL: workspace.stateDirectory
            .appendingPathComponent("universe-index.json"))
        if let cached = await store.cached() {
            return cached
        }
        return await store.bundled()
    }

    private func catalogPackage(_ id: String, workspace: Workspace) async throws -> UniversePackage {
        guard let catalog = await offlineCatalog(workspace),
              let package = catalog.packages.first(where: { $0.reference == id })
        else {
            throw AutomationFailure("package_not_found", "Choose a pinned package or template ID from the catalog.")
        }
        return package
    }

    private func resourceKind(_ args: JSONValue) throws -> DocumentResourceKind {
        switch args["kind"].string {
        case "image": .image
        case "bibliography": .bibliography
        case "document": .document
        case "module": .module
        default: throw AutomationFailure("invalid_arguments", "kind must be image, bibliography, document or module.")
        }
    }

    private func managedID(_ args: JSONValue) throws -> UUID {
        guard let id = args["document_id"].string.flatMap(UUID.init(uuidString:)) else {
            throw AutomationFailure("document_not_found", "Choose a managed document ID from list_documents.")
        }
        return id
    }

    private func libraryMetadata(_ document: LibraryDocument) -> JSONValue {
        .object([
            "id": .string(document.id.uuidString), "title": .string(document.title),
            "snippet": .string(String(document.snippet.prefix(200))),
            "modified_at": .string(dateString(document.modifiedAt)),
            "trashed": .bool(document.isTrashed), "has_conflicts": .bool(document.hasUnresolvedConflicts),
        ])
    }

    private func resourceMetadata(_ resource: DocumentResource) -> JSONValue {
        .object(resourceFields(resource))
    }

    private func resourceFields(_ resource: DocumentResource) -> [String: JSONValue] {
        [
            "file_id": .string(fileID(resource.url)),
            "name": .string(resource.name),
            "relative_path": .string(resource.relativePath),
        ]
    }

    private func dateString(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private func boundedQuery(_ args: JSONValue) throws -> String {
        guard args["query"].isNull || args["query"].string != nil, (args["query"].string ?? "").count <= 200 else {
            throw AutomationFailure("invalid_arguments", "query must be a string of at most 200 characters.")
        }
        return args["query"].string ?? ""
    }

    private func booleanArgument(_ args: JSONValue, _ key: String, default fallback: Bool) throws -> Bool {
        if args[key].isNull {
            return fallback
        }
        guard case let .bool(value) = args[key] else {
            throw AutomationFailure("invalid_arguments", "\(key) must be a boolean.")
        }
        return value
    }

    private func page(
        _ items: [JSONValue], key: String, args: JSONValue, signature: String,
    ) throws -> [String: JSONValue] {
        let limit = try integer(args, "limit", default: 20, range: 1 ... 50)
        let digest = AutomationContract.revision(documentID: key, text: signature)
        var offset = 0
        if !args["cursor"].isNull {
            guard let cursor = args["cursor"].string, let data = Data(base64Encoded: cursor),
                  let value = String(data: data, encoding: .utf8),
                  value.hasPrefix(digest + ":"), let index = Int(value.dropFirst(digest.count + 1)),
                  (0 ... items.count).contains(index)
            else {
                throw AutomationFailure(
                    "invalid_cursor",
                    "This list changed or the cursor is invalid. Start listing again.",
                )
            }
            offset = index
        }
        let end = min(items.count, offset + limit)
        let next = Data((digest + ":" + String(end)).utf8).base64EncodedString()
        return [key: .array(Array(items[offset ..< end])), "total": .number(Double(items.count)),
                "next_cursor": end < items.count ? .string(next) : .null]
    }
}
