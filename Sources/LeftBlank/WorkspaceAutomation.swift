import AppKit
import LeftBlankAutomation
import LeftBlankCore

@MainActor
struct AutomationLibraryAccess {
    var currentID: () -> String
    var list: (String) async throws -> [AutomationDocument]
    var open: (String) async throws -> Void
    var create: (String, String) async throws -> Void
}

private enum AutomationAccess {
    @TaskLocal static var generation: UUID?
}

/// All agent mutations pass through the same live workspace and native undo path as typing.
@MainActor
final class WorkspaceAutomation {
    weak var workspace: Workspace?
    private let server: AutomationBridgeServer
    private let configurationFailure: AutomationFailure?
    let exportDirectory: URL
    private let session = UUID().uuidString
    private(set) var accessGeneration = UUID()
    private var projectGeneration = 0
    private(set) var enabled = false
    var library: AutomationLibraryAccess?
    var compiledPreview: AutomationCompiledPreview?

    init(workspace: Workspace, socketURL: URL? = nil) {
        self.workspace = workspace
        let group = Bundle.main.object(forInfoDictionaryKey: "LeftBlankAgentGroup") as? String
        let container = group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        configurationFailure = group != nil && container == nil ?
            AutomationFailure("bridge_unavailable", "The signed MCP group is unavailable. Reinstall LeftBlank.") : nil
        let endpoint = socketURL ?? container.map {
            AutomationContract.groupSocketURL(in: $0, preview: AppDistribution.current == .preview)
        } ?? AutomationContract.socketURL(in: workspace.stateDirectory)
        exportDirectory = (container ?? workspace.stateDirectory).appendingPathComponent(
            "AgentExports",
            isDirectory: true,
        )
        server = AutomationBridgeServer(socketURL: endpoint)
    }

    func start() throws {
        if let configurationFailure {
            throw configurationFailure
        }
        enabled = false
        let generation = UUID()
        accessGeneration = generation
        try server.start { [weak self] request in
            guard let self else {
                throw AutomationFailure("app_closed", "LeftBlank has closed.")
            }
            return try await handle(request, accessGeneration: generation)
        }
        enabled = true
        workspace?.recordOperation("agent.enabled")
    }

    func stop() {
        enabled = false
        accessGeneration = UUID()
        server.stop()
        compiledPreview = nil
        workspace?.recordOperation("agent.disabled")
    }

    var documentID: String {
        guard let workspace, !workspace.isLibraryHome else {
            return "closed"
        }
        if let id = workspace.managedDocumentID {
            return id.uuidString
        }
        if workspace.managedDocumentID == nil, workspace.mainFileURL != nil {
            return workspace.compilationURL.absoluteString
        }
        return library?.currentID() ?? workspace.compilationURL.absoluteString
    }

    func fileID(_ url: URL) -> String {
        AutomationContract.revision(documentID: session, text: url.standardizedFileURL.absoluteString)
    }

    func revision(_ workspace: Workspace) -> String {
        AutomationContract.revision(
            documentID: session + ":" + documentID + ":" + fileID(workspace.documentURL) + ":" +
                String(workspace.revision) + ":" + String(projectGeneration),
            text: workspace.text,
        )
    }

    func metadata(_ workspace: Workspace) -> [String: JSONValue] {
        ["document_id": .string(documentID), "file_id": .string(fileID(workspace.documentURL)),
         "title": .string(workspace.title), "revision": .string(revision(workspace)),
         "unsaved": .bool(workspace.text != workspace.savedText),
         "total_lines": .number(Double(TextLineIndex(workspace.text).position(at: workspace.text.utf16.count)
                 .line + 1)),
         "selection": .object(["start": .number(Double(workspace.selection.location)),
                               "end": .number(Double(NSMaxRange(workspace.selection)))])]
    }

    func snapshot(_ workspace: Workspace) throws -> JSONValue {
        guard !workspace.isLibraryHome else {
            throw AutomationFailure("no_document", "Open or create a document first.")
        }
        return .object(metadata(workspace))
    }

    /// Project writes invalidate both agent CAS and the compiler, without creating a text undo step.
    func projectChanged(_ workspace: Workspace) {
        projectGeneration += 1
        compiledPreview = nil
        workspace.previewStale = true
        workspace.startService()
    }

    func requireCurrent(_ arguments: JSONValue, workspace: Workspace, revisionRequired: Bool = false) throws {
        try requireAccess(AutomationAccess.generation ?? accessGeneration)
        guard !workspace.isLibraryHome
        else {
            throw AutomationFailure("no_document", "Open or create a document first.")
        }
        guard let id = arguments["document_id"].string, id == documentID else {
            throw AutomationFailure(
                "document_changed",
                "The active document changed. Read the current document before continuing.",
            )
        }
        if revisionRequired, arguments["expected_revision"].string != revision(workspace) {
            throw AutomationFailure(
                "revision_conflict",
                "The document changed since your last read. Re-read and merge your edits.",
            )
        }
    }

    func requireAccess(_ generation: UUID) throws {
        guard enabled, generation == accessGeneration else {
            throw AutomationFailure("access_disabled", "Agent Access was disabled during this operation.")
        }
    }

    func requireEditable(_ workspace: Workspace) throws {
        try requireAccess(AutomationAccess.generation ?? accessGeneration)
        guard !workspace.documentTransitionInProgress, !workspace.applyingCommand,
              workspace.editor?.hasMarkedText() != true, workspace.editor?.window?.attachedSheet == nil
        else {
            throw AutomationFailure(
                "editor_busy",
                "Finish the current input or document operation in LeftBlank, then retry.",
            )
        }
    }

    func handle(
        _ request: AutomationRequest,
        accessGeneration expectedGeneration: UUID? = nil,
    ) async throws -> JSONValue {
        guard enabled, expectedGeneration == nil || expectedGeneration == accessGeneration, let workspace else {
            throw AutomationFailure("access_disabled", "Agent Access is disabled in LeftBlank.")
        }
        let generation = accessGeneration
        return try await AutomationAccess.$generation.withValue(generation) {
            let result = try await dispatch(request, workspace: workspace)
            try requireAccess(generation)
            return result
        }
    }

    private func dispatch(_ request: AutomationRequest, workspace: Workspace) async throws -> JSONValue {
        let args = request.arguments
        workspace.recordOperation("agent.request", ["operation": request.operation])
        switch request.operation {
        case "get_status":
            return .object([
                "bridge_version": .number(2),
                "enabled": .bool(enabled),
                "library_home": .bool(workspace.isLibraryHome),
                "active_document": workspace.isLibraryHome ? .null : .object(metadata(workspace)),
            ])
        case "get_document": return try readDocument(args, workspace: workspace)
        case "get_outline": return try outline(args, workspace: workspace)
        case "search_document": return try search(args, workspace: workspace)
        case "list_files": return try listFiles(args, workspace: workspace)
        case "open_file": return try openFile(args, workspace: workspace)
        case "create_file": return try createFile(args, workspace: workspace)
        case "open_document":
            try requireEditable(workspace)
            guard let id = args["document_id"].string else {
                throw AutomationFailure(
                    "invalid_arguments",
                    "document_id is required.",
                )
            }
            if id != documentID {
                guard let library else {
                    throw AutomationFailure(
                        "document_not_found",
                        "That document is not available in LeftBlank's library.",
                    )
                }
                try await library.open(id)
            }
            return try snapshot(workspace)
        case "create_document":
            try requireEditable(workspace)
            guard let library else {
                throw AutomationFailure(
                    "library_unavailable",
                    "LeftBlank's document library is not ready.",
                )
            }
            guard let title = args["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 200,
                  let source = args["text"].string, source.utf8.count <= AutomationContract.maximumSourceBytes
            else {
                throw AutomationFailure(
                    "invalid_arguments",
                    "Provide a title (1–200 characters) and text (up to 2 MiB).",
                )
            }
            try await library.create(title, source)
            return try snapshot(workspace)
        case "apply_edits", "edit_document":
            try requireEditable(workspace)
            try requireCurrent(args, workspace: workspace, revisionRequired: true)
            guard let editor = workspace.editor else {
                throw AutomationFailure(
                    "editor_unavailable",
                    "The editor is not ready.",
                )
            }
            let changed = try request.operation == "edit_document" ?
                AutomationContract.replacingText(args["edits"], in: workspace.text) :
                AutomationContract.replacing(args["edits"], in: workspace.text)
            if changed != workspace.text {
                workspace.closePalette()
                if workspace.layout == .preview {
                    workspace.layout = .split
                }
                editor.insertSnippet(
                    Snippet(text: changed),
                    replacing: NSRange(location: 0, length: workspace.text.utf16.count),
                )
                editor.undoManager?.setActionName(L10n.text("Agent Edit"))
                guard workspace.text == changed else {
                    throw AutomationFailure(
                        "edit_rejected",
                        "The editor did not accept this change.",
                    )
                }
            }
            var result = metadata(workspace)
            result["changed_edits"] = .number(Double(args["edits"].array.filter {
                request.operation == "edit_document" ? $0["old_text"].string != $0["new_text"].string : true
            }.count))
            return .object(result)
        case "format_document": return try await formatSource(args, workspace: workspace)
        case "get_settings": return settings(workspace)
        case "set_settings":
            try requireEditable(workspace)
            guard case let .object(values) = args,
                  Set(values.keys).isSubset(of: ["layout", "font_size", "preview_dark", "styled_source", "appearance"])
            else {
                throw AutomationFailure(
                    "invalid_settings",
                    "Only layout, font_size, preview_dark, styled_source and appearance can be changed by an agent.",
                )
            }
            if let value = values["layout"], value.string.flatMap(EditorLayout.init(rawValue:)) == nil {
                throw AutomationFailure("invalid_settings", "layout must be writing, split or preview.")
            }
            if let value = values["font_size"], value.int == nil || !(12 ... 28).contains(value.int ?? 0) {
                throw AutomationFailure("invalid_settings", "font_size must be an integer from 12 to 28.")
            }
            if let value = values["appearance"], value.string.flatMap(AppAppearance.init(rawValue:)) == nil {
                throw AutomationFailure("invalid_settings", "appearance must be system, light or dark.")
            }
            for key in ["preview_dark", "styled_source"] {
                if let value = values[key], case .bool = value {} else if values[key] != nil {
                    throw AutomationFailure("invalid_settings", "\(key) must be a boolean.")
                }
            }
            if let value = values["layout"]?.string,
               let layout = EditorLayout(rawValue: value)
            {
                workspace.layout = layout
            }
            if let value = values["font_size"]?.int {
                workspace.fontSize = CGFloat(value)
            }
            if case let .bool(value) = values["preview_dark"] {
                workspace.previewDark = value
            }
            if case let .bool(value) = values["styled_source"] {
                workspace.styledSource = value
            }
            if let value = values["appearance"]?.string,
               let appearance = AppAppearance(rawValue: value)
            {
                workspace.appearance = appearance
            }
            return settings(workspace)
        default:
            if let result = try await handleCapabilities(request.operation, args, workspace: workspace) {
                return result
            }
            if let result = try await handlePreview(request.operation, args, workspace: workspace) {
                return result
            }
            throw AutomationFailure("unknown_operation", "This operation is not available in LeftBlank.")
        }
    }

    private func settings(_ workspace: Workspace) -> JSONValue {
        .object(["layout": .string(workspace.layout.rawValue), "font_size": .number(Double(workspace.fontSize)),
                 "preview_dark": .bool(workspace.previewDark), "styled_source": .bool(workspace.styledSource),
                 "appearance": .string(workspace.appearance.rawValue)])
    }
}
