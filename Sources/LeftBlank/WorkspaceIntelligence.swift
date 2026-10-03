import AppKit
import LeftBlankCore
import UniformTypeIdentifiers

extension Workspace {
    static let referencePageCommand = WritingCommand(
        "reconstructPage", "file", "p", "Reconstruct Page",
        "Create an editable draft from one image or the first PDF page.",
        "reconstruct image pdf typst source reverse 图片 PDF 反向 识别",
        isInsertion: false,
    )

    var typesettingRequestHelp: String {
        let description = L10n.text("Describe one change. Review its parameters before applying it.")
        if case let .unavailable(reason) = LocalIntelligence.status {
            return description + "\n" + reason + "\n" + L10n.text("Simple requests still work with local rules.")
        }
        return description
    }

    func cancelTypesettingRequest() {
        typesettingRequestGeneration = UUID()
        typesettingRequestTask?.cancel()
        typesettingRequestTask = nil
        understandingRequest = false
    }

    /// Resolving only prepares the existing command form. Insertion still needs
    /// the person's confirmation and uses the editor's normal undo path.
    func understandTypesettingRequest() {
        guard paletteOpen, searchMode, activeCommand == nil, !understandingRequest else {
            return
        }
        let request = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            return
        }
        cancelTypesettingRequest()
        let generation = typesettingRequestGeneration
        let sourceURL = documentURL, version = revision, caret = selection
        let resolver = typesettingResolver
        understandingRequest = true
        commandError = nil
        typesettingRequestTask = Task { [weak self] in
            do {
                let suggestion = try await resolver(request)
                try Task.checkCancellation()
                guard let self, typesettingRequestGeneration == generation else {
                    return
                }
                defer { understandingRequest = false
                    typesettingRequestTask = nil
                }
                guard paletteOpen, searchMode, activeCommand == nil,
                      documentURL == sourceURL, revision == version, selection == caret
                else {
                    return
                }
                guard let suggestion = try suggestion?.validated(), let command = suggestion.command else {
                    commandError = L10n.text(TypesettingIntelligence.requiresNumberedCode(request)
                        ? "Numbered code blocks are not supported yet."
                        : "No supported action found. Describe one change, such as a three-column table.")
                    return
                }
                fieldValues = Dictionary(uniqueKeysWithValues: command.fields.map { ($0.id, $0.initial) })
                    .merging(suggestion.values) { _, suggested in suggested }
                activeCommand = command
                recordOperation("intelligence.suggested", ["command": command.id])
            } catch {
                guard let self, typesettingRequestGeneration == generation else {
                    return
                }
                understandingRequest = false
                typesettingRequestTask = nil
                if !(error is CancellationError) {
                    commandError = error.localizedDescription
                }
            }
        }
    }

    func cancelPageReconstruction() {
        reconstructionGeneration = UUID()
        reconstructionTask?.cancel()
        reconstructionTask = nil
        reconstructingPage = false
    }

    func chooseReferencePage() {
        if reconstructingPage {
            cancelPageReconstruction()
            showMessage(L10n.text("Page reconstruction cancelled."))
            return
        }
        guard !library.busy, !documentTransitionInProgress,
              let window = window ?? editor?.window, window.attachedSheet == nil
        else {
            return
        }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Reconstruct from Image or PDF")
        panel.message = L10n.text("Creates an editable draft. PDFs use the first page; check the recognized text.")
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            self?.reconstructPage(from: url)
        }
    }

    func reconstructPage(from url: URL) {
        guard !reconstructingPage, !library.busy, !documentTransitionInProgress else {
            return
        }
        cancelPageReconstruction()
        closePalette()
        let generation = reconstructionGeneration
        let sourceURL = documentURL, version = revision
        reconstructingPage = true
        showMessage(L10n.text("Recognizing the first page on this Mac…"), persistent: true)
        reconstructionTask = Task { [weak self] in
            do {
                let result = try await ReferencePageImporter.importPage(from: url)
                try Task.checkCancellation()
                guard let self, reconstructionGeneration == generation else {
                    return
                }
                defer {
                    if reconstructionGeneration == generation {
                        reconstructingPage = false
                        reconstructionTask = nil
                    }
                }
                let document = try await library.store.create(
                    title: L10n.format("%@ — reconstructed", url.deletingPathExtension().lastPathComponent),
                    text: result.source,
                )
                await library.refresh()
                guard !Task.isCancelled, reconstructionGeneration == generation else {
                    return
                }
                // Keep a completed draft in the library if writing changed while
                // OCR or storage was running, without interrupting that writing.
                guard documentURL == sourceURL, revision == version, !documentTransitionInProgress else {
                    showMessage(L10n.text("Reconstructed draft saved in Your writing."), persistent: true)
                    return
                }
                guard try await library.open(document.id, ifCurrent: (sourceURL, version)) else {
                    showMessage(L10n.text("Reconstructed draft saved in Your writing."), persistent: true)
                    return
                }
                layout = .split
                showMessage(result.warning ?? L10n.text("Reconstructed draft saved in Your writing."), persistent: true)
                recordOperation("intelligence.reconstructed", ["mode": String(describing: result.extractionMode)])
            } catch {
                guard let self, reconstructionGeneration == generation else {
                    return
                }
                reconstructingPage = false
                reconstructionTask = nil
                if !(error is CancellationError) {
                    showMessage(error.localizedDescription, persistent: true)
                }
            }
        }
    }
}
