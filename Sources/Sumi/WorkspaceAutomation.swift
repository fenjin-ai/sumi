import AppKit
import PDFKit
import SumiAutomation
import SumiCore

@MainActor
struct AutomationLibraryAccess {
    var currentID: () -> String
    var list: (String) async throws -> [AutomationDocument]
    var open: (String) async throws -> Void
    var create: (String, String) async throws -> Void
}

/// All agent mutations pass through the same live workspace and native undo path as typing.
@MainActor
final class WorkspaceAutomation {
    private weak var workspace: Workspace?
    private let server: AutomationBridgeServer
    private let session = UUID().uuidString
    private var accessGeneration = UUID()
    private(set) var enabled = false
    var library: AutomationLibraryAccess?

    init(workspace: Workspace, socketURL: URL? = nil) {
        self.workspace = workspace
        server = AutomationBridgeServer(socketURL: socketURL ?? AutomationContract.socketURL(in: workspace.stateDirectory))
    }

    func start() throws {
        enabled = false
        let generation = UUID()
        accessGeneration = generation
        try server.start { [weak self] request in
            guard let self else { throw AutomationFailure("app_closed", "Sumi has closed.") }
            return try await self.handle(request, accessGeneration: generation)
        }
        enabled = true
        workspace?.recordOperation("agent.enabled")
    }

    func stop() {
        enabled = false
        accessGeneration = UUID()
        server.stop()
        workspace?.recordOperation("agent.disabled")
    }

    private var documentID: String {
        library?.currentID() ?? workspace?.documentURL.absoluteString ?? "closed"
    }
    private func revision(_ workspace: Workspace) -> String {
        AutomationContract.revision(documentID: session + ":" + documentID + ":" + String(workspace.revision), text: workspace.text)
    }
    private func snapshot(_ workspace: Workspace) throws -> JSONValue {
        guard workspace.text.utf8.count <= AutomationContract.maximumSourceBytes else {
            throw AutomationFailure("document_too_large", "Agent reads are limited to 2 MiB of source.")
        }
        return .object([
            "document_id": .string(documentID), "title": .string(workspace.title),
            "revision": .string(revision(workspace)), "text": .string(workspace.text),
            "unsaved": .bool(workspace.text != workspace.savedText),
            "selection": .object(["start": .number(Double(workspace.selection.location)), "end": .number(Double(NSMaxRange(workspace.selection)))])
        ])
    }
    private func requireCurrent(_ arguments: JSONValue, workspace: Workspace, revisionRequired: Bool = false) throws {
        guard let id = arguments["document_id"].string, id == documentID else {
            throw AutomationFailure("document_changed", "The active document changed. Read the current document before continuing.")
        }
        if revisionRequired, arguments["expected_revision"].string != revision(workspace) {
            throw AutomationFailure("revision_conflict", "The document changed since your last read. Re-read and merge your edits.")
        }
    }
    private func requireEditable(_ workspace: Workspace) throws {
        guard !workspace.documentTransitionInProgress, !workspace.applyingCommand,
              workspace.editor?.hasMarkedText() != true, workspace.editor?.window?.attachedSheet == nil else {
            throw AutomationFailure("editor_busy", "Finish the current input or document operation in Sumi, then retry.")
        }
    }

    func handle(_ request: AutomationRequest, accessGeneration expectedGeneration: UUID? = nil) async throws -> JSONValue {
        guard enabled, expectedGeneration == nil || expectedGeneration == accessGeneration, let workspace else {
            throw AutomationFailure("access_disabled", "Agent Access is disabled in Sumi.")
        }
        guard ["get_document", "list_documents", "open_document", "create_document", "apply_edits", "get_preview", "export_pdf", "get_settings", "set_settings"].contains(request.operation) else {
            throw AutomationFailure("unknown_operation", "This operation is not available in Sumi.")
        }
        let args = request.arguments
        workspace.recordOperation("agent.request", ["operation": request.operation])
        switch request.operation {
        case "get_document": return try snapshot(workspace)
        case "list_documents":
            let query = args["query"].string ?? ""
            let documents: [AutomationDocument]
            if let library { documents = try await library.list(query) }
            else { documents = query.isEmpty || workspace.title.localizedCaseInsensitiveContains(query) ? [.init(id: documentID, title: workspace.title)] : [] }
            return .object(["documents": try AutomationContract.encode(documents), "active_document_id": .string(documentID)])
        case "open_document":
            try requireEditable(workspace)
            guard let id = args["document_id"].string else { throw AutomationFailure("invalid_arguments", "document_id is required.") }
            if id != documentID {
                guard let library else { throw AutomationFailure("document_not_found", "That document is not available in Sumi's library.") }
                try await library.open(id)
            }
            return try snapshot(workspace)
        case "create_document":
            try requireEditable(workspace)
            guard let library else { throw AutomationFailure("library_unavailable", "Sumi's document library is not ready.") }
            guard let title = args["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
                  let source = args["text"].string, source.utf8.count <= AutomationContract.maximumSourceBytes else {
                throw AutomationFailure("invalid_arguments", "Provide a title (1–200 characters) and text (up to 2 MiB).")
            }
            try await library.create(title, source)
            return try snapshot(workspace)
        case "apply_edits":
            try requireEditable(workspace)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            guard let editor = workspace.editor else { throw AutomationFailure("editor_unavailable", "The editor is not ready.") }
            let changed = try AutomationContract.replacing(args["edits"], in: workspace.text)
            if changed != workspace.text {
                workspace.closePalette()
                if workspace.layout == .preview { workspace.layout = .split }
                editor.insertSnippet(Snippet(text: changed), replacing: NSRange(location: 0, length: workspace.text.utf16.count))
                editor.undoManager?.setActionName(L10n.text("Agent Edit"))
                guard workspace.text == changed else { throw AutomationFailure("edit_rejected", "The editor did not accept this change.") }
            }
            return try snapshot(workspace)
        case "get_preview":
            try requireCurrent(args, workspace: workspace)
            return .object([
                "document_id": .string(documentID), "revision": .string(revision(workspace)),
                "ready": .bool(workspace.serviceReady), "stale": .bool(workspace.previewStale),
                "has_successful_preview": .bool(workspace.hasSuccessfulPreview),
                "diagnostics": .array(workspace.diagnostics.map {
                    .object(["message": .string($0.message), "severity": .number(Double($0.severity)),
                             "line": .number(Double($0.position.line)), "character": .number(Double($0.position.character)),
                             "uri": .string($0.url.absoluteString)])
                })
            ])
        case "export_pdf":
            try requireEditable(workspace)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            let expected = revision(workspace), id = documentID
            let directory = workspace.stateDirectory.appendingPathComponent("AgentExports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = directory.appendingPathComponent(UUID().uuidString + ".pdf")
            do {
                try await workspace.exportPDF(to: destination)
                guard enabled, expected == revision(workspace), documentID == id else {
                    throw AutomationFailure("revision_conflict", "The document changed during export. Re-read and export again.")
                }
                guard let pdf = PDFDocument(url: destination) else { throw AutomationFailure("preview_unavailable", "The exported preview could not be read.") }
                let number = args["page"].int ?? 1
                guard number >= 1, number <= pdf.pageCount, let page = pdf.page(at: number - 1) else {
                    throw AutomationFailure("invalid_page", "The requested page is outside the exported PDF.")
                }
                let thumbnail = page.thumbnail(of: NSSize(width: 1000, height: 1400), for: .mediaBox)
                guard let tiff = thumbnail.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw AutomationFailure("preview_unavailable", "The preview image could not be rendered.")
                }
                return .object(["document_id": .string(id), "revision": .string(expected),
                                "path": .string(destination.path), "uri": .string(destination.absoluteString),
                                "page_count": .number(Double(pdf.pageCount)), "page": .number(Double(number)),
                                "image_png": .string(png.base64EncodedString())])
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        case "get_settings": return settings(workspace)
        case "set_settings":
            try requireEditable(workspace)
            guard case .object(let values) = args,
                  Set(values.keys).isSubset(of: ["layout", "font_size", "preview_dark", "styled_source"]) else {
                throw AutomationFailure("invalid_settings", "Only layout, font_size, preview_dark and styled_source can be changed by an agent.")
            }
            if let value = values["layout"], value.string.flatMap(EditorLayout.init(rawValue:)) == nil {
                throw AutomationFailure("invalid_settings", "layout must be writing, split or preview.")
            }
            if let value = values["font_size"], value.int == nil || !(12...28).contains(value.int ?? 0) {
                throw AutomationFailure("invalid_settings", "font_size must be an integer from 12 to 28.")
            }
            for key in ["preview_dark", "styled_source"] {
                if let value = values[key], case .bool = value {} else if values[key] != nil {
                    throw AutomationFailure("invalid_settings", "\(key) must be a boolean.")
                }
            }
            if let value = values["layout"]?.string, let layout = EditorLayout(rawValue: value) { workspace.layout = layout }
            if let value = values["font_size"]?.int { workspace.fontSize = CGFloat(value) }
            if case .bool(let value) = values["preview_dark"] { workspace.previewDark = value }
            if case .bool(let value) = values["styled_source"] { workspace.styledSource = value }
            return settings(workspace)
        default: throw AutomationFailure("unknown_operation", "This operation is not available in Sumi.")
        }
    }

    private func settings(_ workspace: Workspace) -> JSONValue {
        .object(["layout": .string(workspace.layout.rawValue), "font_size": .number(Double(workspace.fontSize)),
                 "preview_dark": .bool(workspace.previewDark), "styled_source": .bool(workspace.styledSource)])
    }
}
