import AppKit
import LeftBlankCore
import UniformTypeIdentifiers

enum ResourceSelection {
    case file(URL)
    case existing(DocumentResource)

    var name: String {
        switch self {
        case let .file(url): url.lastPathComponent
        case let .existing(resource): resource.name
        }
    }
}

extension Workspace {
    func loadResources(for command: WritingCommand) {
        guard let kind = command.fields.first?.resourceKind else {
            return
        }
        let document = documentURL, root = compilationURL.deletingLastPathComponent()
        Task {
            do {
                let resources = try await resourceStore.list(kind: kind, in: root, relativeTo: document)
                guard documentURL == document, activeCommand?.id == command.id else {
                    return
                }
                availableResources = resources
            } catch { commandError = error.localizedDescription }
        }
    }

    func chooseResource(for command: WritingCommand) {
        guard !applyingCommand, let kind = command.fields.first?.resourceKind,
              let owner = window ?? editor?.window, owner.attachedSheet == nil
        else {
            return
        }
        let document = documentURL
        let panel = NSOpenPanel()
        panel.title = L10n.text("Import into Document")
        panel.prompt = L10n.text("Choose")
        panel.allowedContentTypes = kind == .image ? [.image, .pdf] :
            kind.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: owner) { [weak self] response in
            guard response == .OK, let url = panel.url, let self,
                  documentURL == document, activeCommand?.id == command.id
            else {
                return
            }
            resourceSelection = .file(url)
            commandError = nil
        }
    }

    func resolveResource(
        _ selection: ResourceSelection,
        kind: DocumentResourceKind,
    ) async throws -> [DocumentResource] {
        switch selection {
        case let .existing(resource):
            guard availableResources.contains(resource),
                  FileManager.default.fileExists(atPath: resource.url.path)
            else {
                throw DocumentResourceError.invalidLocation
            }
            return [resource]
        case let .file(url):
            return try await resourceStore.importResources(
                [.file(url)], kind: kind, in: compilationURL.deletingLastPathComponent(), relativeTo: documentURL,
            )
        }
    }

    func insertResources(_ inputs: [DocumentResourceInput], kind: DocumentResourceKind, replacing range: NSRange) {
        Task {
            do { try await importAndInsertResources(inputs, kind: kind, replacing: range) }
            catch { showMessage(error.localizedDescription, persistent: true) }
        }
    }

    /// Paste and drop share the palette's syntax checks and native undo path.
    func importAndInsertResources(
        _ inputs: [DocumentResourceInput],
        kind: DocumentResourceKind,
        replacing range: NSRange,
    ) async throws {
        guard !inputs.isEmpty, !applyingCommand, !documentTransitionInProgress, !isLibraryHome, !paletteOpen,
              layout != .preview, let editor, editor.isEditable, !editor.hasMarkedText()
        else {
            return
        }
        let id = switch kind {
        case .image: "image"
        case .bibliography: "bibliography"
        case .document: "include"
        case .module: "import"
        }
        guard let command = WritingCommand.all.first(where: { $0.id == id }) else {
            return
        }
        let version = revision, document = documentURL
        applyingCommand = true
        defer { applyingCommand = false }
        _ = try await insertionContext(for: command, range: range)
        guard revision == version, documentURL == document, editor.selectedRange() == range,
              editor.isEditable, !editor.hasMarkedText()
        else {
            return
        }
        let resources = try await resourceStore.importResources(
            inputs, kind: kind, in: compilationURL.deletingLastPathComponent(), relativeTo: document,
        )
        guard revision == version, documentURL == document, editor.selectedRange() == range,
              editor.isEditable, !editor.hasMarkedText()
        else {
            try await resourceStore.discardImport(resources)
            return
        }
        do {
            let snippets = try resources.map { try TypstInsertion.make(id, values: ["path": $0.relativePath]) }
            let snippet = Snippet(text: snippets.map(\.text).joined(separator: "\n\n"))
            let plan = InsertionPlan(command: command, snippet: snippet, text: text, selection: range)
            editor.insertSnippet(plan.snippet, replacing: plan.range)
            recordOperation("resource.inserted", ["kind": id, "count": String(resources.count)])
        } catch {
            try? await resourceStore.discardImport(resources)
            throw error
        }
    }
}
