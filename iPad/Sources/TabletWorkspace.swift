import Combine
import Foundation
import LeftBlankCore
import UIKit

@MainActor
final class TabletWorkspace: ObservableObject {
    enum Layout: String, CaseIterable { case writing, split, preview }
    enum Panel: String, Identifiable { case commands, outline, checks, history, settings, universe, trash
        var id: String {
            rawValue
        }
    }

    @Published var trashedDocuments: [LibraryDocument] = []
    @Published var documents: [LibraryDocument] = []
    @Published var document: LibraryDocument?
    @Published var text = "" {
        didSet { metrics = DocumentMetrics(text) }
    }

    private(set) var metrics = DocumentMetrics("")
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var layout: Layout = .split
    @Published var panel: Panel?
    @Published var previewURL: URL?
    @Published var previewReady = false
    @Published var previewIssue: String?
    @Published var serviceReady = false
    @Published var serviceStatus = "Connecting"
    @Published var saveStatus = "Saved"
    @Published var message: String?
    @Published var busy = false
    @Published var revisions: [DocumentRevision] = []
    @Published var outline: [JSONValue] = []
    @Published var diagnostics: [JSONValue] = []
    @Published var fontSize: Double = UserDefaults.standard.object(forKey: "iPadEditorFontSize") as? Double ?? 15 {
        didSet { UserDefaults.standard.set(fontSize, forKey: "iPadEditorFontSize") }
    }

    @Published var highlightedText = ""
    @Published var tokens: [HighlightToken] = []
    @Published var shareURL: URL?
    @Published var cloudEnabled = false
    weak var editor: UITextView?
    private let library = DocumentLibrary(rootURL: AppDistribution.defaultStateDirectory
        .appendingPathComponent("Library"))
    private let history = DocumentHistory(root: AppDistribution.defaultStateDirectory.appendingPathComponent("History"))
    private let client = TinymistClient(makeTransport: { EmbeddedTinymist() })
    private var baseline: DiskBaseline?
    private var savedText = ""
    private var version = 1
    private var generation = UUID()
    private var debounce: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var started = false
    private var changing = false
    private let recoveryURL = AppDistribution.defaultStateDirectory.appendingPathComponent("iPadRecovery.json")

    func start() async {
        guard !started else {
            return
        }
        started = true
        do {
            try FileManager.default.createDirectory(
                at: AppDistribution.defaultStateDirectory,
                withIntermediateDirectories: true,
            )
            if UserDefaults.standard.object(forKey: "iPadCloudEnabled") == nil || UserDefaults.standard
                .bool(forKey: "iPadCloudEnabled")
            {
                _ = try? await library.resumeICloud()
            }
            cloudEnabled = await library.isICloud
            try await reloadLibrary()
            if documents.isEmpty {
                let item = try await library.create(
                    title: BuiltInTemplate.welcome.title,
                    text: BuiltInTemplate.welcome.source,
                )
                try await reloadLibrary()
                await open(item)
            }
            if let data = try? Data(contentsOf: recoveryURL),
               let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data),
               snapshot.text != snapshot.savedText,
               let item = documents.first(where: { $0.sourceURL == snapshot.fileURL })
            {
                await open(item)
                if text != snapshot.text {
                    // Preserve the recovery as a separate document if disk changed.
                    let recovered = try await library.create(title: L10n.text("Recovered Draft"), text: snapshot.text)
                    try await reloadLibrary()
                    await open(recovered)
                }
            }
        } catch { message = error.localizedDescription }
    }

    func reloadLibrary() async throws {
        documents = try await library.list()
    }

    func open(_ item: LibraryDocument) async {
        guard !changing else {
            return
        }
        commitComposition()
        changing = true
        defer { changing = false }
        busy = true
        defer { busy = false }
        guard await save() else {
            return
        }
        do {
            let result = try await library.read(item.id)
            generation = UUID()
            debounce?.cancel()
            client.stop()
            document = result.document
            text = result.text
            savedText = text
            baseline = result.baseline
            selection = NSRange(location: 0, length: 0)
            version = 1
            tokens = []
            outline = []
            diagnostics = []
            previewURL = nil
            previewReady = false
            previewIssue = nil
            serviceReady = false
            saveStatus = "Saved"
            editor?.undoManager?.removeAllActions()
            await connect()
        } catch { message = error.localizedDescription }
    }

    func connect() async {
        guard let document else {
            return
        }
        let session = generation
        serviceStatus = "Connecting"
        client.onShowDocument = { [weak self] params in
            guard let self, let target = SourceLocation(params) else {
                return
            }
            guard target.url.resolvingSymlinksInPath() == self.document?.sourceURL.resolvingSymlinksInPath() else {
                message = L10n
                    .text("This location is in an included file. Included-file editing is not available on iPad yet.")
                return
            }
            jump(target.position)
        }
        client.onDisconnect = { [weak self] error in
            self?.serviceReady = false
            self?.message = error
        }
        client.onNotification = { [weak self] method, params in
            guard let self else {
                return
            }
            if method == "textDocument/publishDiagnostics",
               params["uri"].string == self.document?.sourceURL.absoluteString
            {
                diagnostics = params["diagnostics"].array
            }
            if method == "tinymist/compileStatus" || method == "tinymist/status" {
                switch params["status"].string {
                case "compiling": serviceStatus = "Typesetting"
                case "compileSuccess": serviceStatus = "Preview Updated"
                case "compileError": serviceStatus = "Document Needs Attention"
                default: break
                }
            }
        }
        do {
            let exports = AppDistribution.defaultStateDirectory.appendingPathComponent("Exports")
            try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
            try await client.start(
                root: document.folderURL,
                outputDirectory: exports,
                fontPaths: [EmbeddedTinymist.fontCacheURL],
            )
            guard generation == session else {
                return
            }
            try client.open(document.sourceURL, text: text, version: version)
            serviceReady = true
            serviceStatus = "Ready"
            previewURL = try await client.startPreview(document.sourceURL)
            guard generation == session else {
                return
            }
            await refresh()
        } catch {
            guard generation == session else {
                return
            }
            serviceReady = false
            serviceStatus = "Unavailable"
            message = error.localizedDescription
        }
    }

    func edited(_ source: String, selection: NSRange) {
        self.selection = selection
        guard source != text else {
            return
        }
        let previous = text
        text = source
        version += 1
        saveStatus = "Saving"
        persistRecovery()
        if let document {
            Task {
                do { try await history.recordEdit(
                    key: document.id.uuidString,
                    previous: previous,
                    current: source,
                    at: Date(),
                    interval: .hourly,
                ) } catch { message = error.localizedDescription }
            }
            if serviceReady {
                do { try client.change(document.sourceURL, text: source, version: version) }
                catch { message = error.localizedDescription }
            }
        }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self else {
                return
            }
            await save()
            await refresh()
        }
    }

    private func commitComposition() {
        guard let editor, editor.markedTextRange != nil else {
            return
        }
        editor.unmarkText()
        edited(editor.text, selection: editor.selectedRange)
    }

    private func persistRecovery() {
        let snapshot = RecoverySnapshot(
            fileURL: document?.sourceURL,
            text: text,
            savedText: savedText,
            selection: selection.location,
        )
        do { try JSONEncoder().encode(snapshot).write(to: recoveryURL, options: .atomic) }
        catch { message = error.localizedDescription }
    }

    @discardableResult
    func save() async -> Bool {
        guard let document else {
            return true
        }
        let previousTask = saveTask
        let source = text
        let task = Task { [self] in
            _ = await previousTask?.value
            guard self.document?.id == document.id else {
                return true
            }
            guard savedText != source else {
                return true
            }
            do {
                let result = try await library.save(document.id, text: source, baseline: baseline)
                baseline = result.baseline
                savedText = source
                saveStatus = text == source ? "Saved" : "Saving"
                persistRecovery()
                try await reloadLibrary()
                return true
            } catch {
                saveStatus = "Save Needs Attention"
                message = error.localizedDescription
                return false
            }
        }
        saveTask = task
        return await task.value
    }

    private func refresh() async {
        guard let document, serviceReady else {
            return
        }
        let session = generation, revision = version, source = text
        do {
            async let symbols = client.request(
                "textDocument/documentSymbol",
                ["textDocument": ["uri": document.sourceURL.absoluteString]],
            )
            let response = try await client.request(
                "textDocument/semanticTokens/full",
                ["textDocument": ["uri": document.sourceURL.absoluteString]],
            )
            let result = SemanticHighlighting.decode(
                response["data"].array.compactMap(\.int),
                source: source,
                types: client.semanticTokenTypes,
                modifiers: client.semanticTokenModifiers,
            )
            let headings = try await symbols
            guard session == generation, revision == version else {
                return
            }
            tokens = result
            highlightedText = source
            outline = headings.array
        } catch { /* Retain the last valid outline and coloring while editing. */ }
    }

    func create(_ template: BuiltInTemplate) async {
        guard !busy else {
            return
        }
        do {
            let item = try await library.create(title: template.title, text: template.source)
            try await reloadLibrary()
            await open(item)
        } catch { message = error.localizedDescription }
    }

    func importDocument(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let item = try await library.importDocument(at: url)
            try await reloadLibrary()
            await open(item)
        } catch { message = error.localizedDescription }
    }

    func rename(_ title: String) async {
        guard let document else {
            return
        }
        do { self.document = try await library.rename(document.id, title: title)
            try await reloadLibrary()
        } catch { message = error.localizedDescription }
    }

    func exportPDF() async {
        commitComposition()
        guard let document, serviceReady, !busy else {
            return
        }
        busy = true
        defer { busy = false }
        do {
            try client.change(document.sourceURL, text: text, version: version)
            let response = try await client.command("tinymist.exportPdf", arguments: [document.sourceURL.path])
            guard let path = response["path"].string
            else {
                throw ServiceError
                    .remote(L10n.text("The document cannot be compiled. Resolve the errors before exporting."))
            }
            let url = URL(fileURLWithPath: path)
            guard try Data(contentsOf: url).starts(with: Data("%PDF".utf8))
            else {
                throw ServiceError.remote("Invalid PDF")
            }
            shareURL = url
        } catch { message = error.localizedDescription }
    }

    func showHistory() async {
        guard let document else {
            return
        }
        do { revisions = try await history.revisions(for: document.id.uuidString)
            panel = .history
        } catch { message = error.localizedDescription }
    }

    func restore(_ revision: DocumentRevision) async {
        guard let document, !busy else {
            return
        }
        do {
            let source = try await history.source(for: revision, key: document.id.uuidString)
            try await history.preserveBeforeRestore(text, key: document.id.uuidString, at: Date())
            replace(source)
            panel = nil
            await save()
        } catch { message = error.localizedDescription }
    }

    func setCloud(_ enabled: Bool) async {
        guard !busy, await save() else {
            return
        }
        busy = true
        defer { busy = false }
        do {
            let report = try await library.setICloudEnabled(enabled)
            cloudEnabled = report.isICloud
            UserDefaults.standard.set(report.isICloud, forKey: "iPadCloudEnabled")
            try await reloadLibrary()
            let oldID = document?.id
            if let id = oldID.map({ report.idMappings[$0] ?? $0 }), let item = documents.first(where: { $0.id == id }) {
                await open(item)
            }
        } catch { message = error.localizedDescription }
    }

    func jump(_ position: TextPosition) {
        let offset = metrics.offset(at: position)
        selection = NSRange(location: offset, length: 0)
        if layout == .preview {
            layout = .writing
        }
        panel = nil
        editor?.isEditable = !busy
        editor?.selectedRange = selection
        editor?.scrollRangeToVisible(selection)
        editor?.becomeFirstResponder()
    }

    func replace(_ source: String) {
        apply(TextReplacement(range: NSRange(location: 0, length: text.utf16.count), text: source))
    }

    func revisionSource(_ revision: DocumentRevision) async throws -> String {
        guard let document else {
            throw HistoryError.unavailable
        }
        return try await history.source(for: revision, key: document.id.uuidString)
    }
}

extension TabletWorkspace {
    func insert(_ command: WritingCommand, values: [String: String]) {
        guard let editor, editor.markedTextRange == nil else {
            return
        }
        do {
            let selected = (text as NSString).substring(with: selection)
            let snippet = try TypstInsertion.make(command.id, values: values, selection: selected)
            let plan = InsertionPlan(command: command, snippet: snippet, text: text, selection: selection)
            apply(TextReplacement(range: plan.range, text: plan.snippet.text))
            if let placeholder = plan.snippet.selections.first {
                editor.selectedRange = NSRange(
                    location: plan.range.location + placeholder.location,
                    length: placeholder.length,
                )
            }
            panel = nil
            editor.becomeFirstResponder()
        } catch { message = error.localizedDescription }
    }

    func lineAction(_ action: LineAction) {
        apply(TextEditing.lines(action, text: text, selection: selection))
    }

    private func apply(_ edit: TextReplacement, restoringSelection: NSRange? = nil) {
        guard let editor, editor.markedTextRange == nil,
              edit.range.location >= 0, edit.range.length >= 0,
              edit.range.location <= editor.textStorage.length,
              edit.range.length <= editor.textStorage.length - edit.range.location
        else {
            return
        }
        let previousSelection = editor.selectedRange
        let inverse = TextReplacement(
            range: NSRange(location: edit.range.location, length: edit.text.utf16.count),
            text: (editor.text as NSString).substring(with: edit.range),
        )
        editor.undoManager?.registerUndo(withTarget: self) { workspace in
            workspace.apply(inverse, restoringSelection: previousSelection)
        }
        // UITextInput replacement can apply typographic quote substitutions even
        // to programmatic code. Edit storage verbatim and retain native undo.
        editor.textStorage.replaceCharacters(in: edit.range, with: edit.text)
        editor.selectedRange = restoringSelection ?? NSRange(
            location: edit.range.location + edit.text.utf16.count,
            length: 0,
        )
        edited(editor.text, selection: editor.selectedRange)
    }

    func format() async {
        guard let document, serviceReady, editor?.markedTextRange == nil else {
            return
        }
        let revision = version, session = generation, original = text
        do {
            let response = try await client.request("textDocument/formatting", [
                "textDocument": ["uri": document.sourceURL.absoluteString],
                "options": ["tabSize": 2, "insertSpaces": true],
            ])
            guard revision == version, session == generation else {
                return
            }
            let index = TextLineIndex(original)
            let edits = response.array.map { edit in
                let start = edit["range"]["start"], end = edit["range"]["end"]
                let lower = index.offset(at: TextPosition(
                    line: start["line"].int ?? 0,
                    character: start["character"].int ?? 0,
                ))
                let upper = index.offset(at: TextPosition(
                    line: end["line"].int ?? 0,
                    character: end["character"].int ?? 0,
                ))
                return TextReplacement(
                    range: NSRange(location: lower, length: max(0, upper - lower)),
                    text: edit["newText"].string ?? "",
                )
            }
            try replace(TextEditing.applying(edits, to: original))
            panel = nil
        } catch { message = error.localizedDescription }
    }
}

extension TabletWorkspace {
    func showUniverse() {
        panel = .universe
    }

    func addPackage(_ package: UniversePackage) {
        guard let editor, editor.markedTextRange == nil else {
            return
        }
        do {
            let snippet = try package.pinnedImport()
            let offset = InsertionPlan.preambleEnd(text)
            let prefix = (text as NSString).substring(to: offset)
            apply(TextReplacement(
                range: NSRange(location: offset, length: 0),
                text: (prefix.isEmpty || prefix.hasSuffix("\n") ? "" : "\n") + snippet.text + "\n",
            ))
            panel = nil
        } catch { message = error.localizedDescription }
    }

    func createTemplate(_ package: UniversePackage) async {
        guard !busy else {
            return
        }
        busy = true
        let staging = AppDistribution.defaultStateDirectory.appendingPathComponent("TemplateStaging")
        do {
            let installer = TinymistClient(makeTransport: { EmbeddedTinymist() })
            defer { installer.stop() }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try await installer.start(root: staging, outputDirectory: staging)
            let project = try await UniverseTemplateInstaller.materialize(package, using: installer, in: staging)
            defer { try? FileManager.default.removeItem(at: project.directoryURL) }
            let item = try await library.importProject(
                at: project.directoryURL,
                mainFile: project.mainFileURL,
                title: package.name,
            )
            try await reloadLibrary()
            busy = false
            panel = nil
            await open(item)
        } catch { busy = false
            message = error.localizedDescription
        }
    }

    func addSampleBook() async {
        guard !busy else {
            return
        }
        busy = true
        let store = SampleBookStore(cacheURL: AppDistribution.defaultStateDirectory.appendingPathComponent("BookCache"))
        do {
            let project = try await store.materialize(
                .sicp,
                in: AppDistribution.defaultStateDirectory.appendingPathComponent("BookStaging"),
            )
            defer { try? FileManager.default.removeItem(at: project.directoryURL) }
            let item = try await library.importProject(
                at: project.directoryURL,
                mainFile: project.mainFileURL,
                title: SampleBook.sicp.title,
            )
            try await reloadLibrary()
            busy = false
            await open(item)
        } catch { busy = false
            message = error.localizedDescription
        }
    }

    func importProject(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let main = url.appendingPathComponent("main.typ")
            let item = try await library.importProject(at: url, mainFile: main)
            try await reloadLibrary()
            await open(item)
        } catch { message = error.localizedDescription }
    }

    func trash(_ item: LibraryDocument) async {
        guard !busy else {
            return
        }
        if item.id == document?.id, await !save() {
            return
        }
        do {
            _ = try await library.trash(item.id)
            if item.id == document?.id {
                generation = UUID()
                client.stop()
                document = nil
                previewURL = nil
                previewReady = false
                previewIssue = nil
                serviceReady = false
                text = ""
                savedText = ""
                baseline = nil
                try? FileManager.default.removeItem(at: recoveryURL)
            }
            try await reloadLibrary()
        } catch { message = error.localizedDescription }
    }

    func showTrash() async {
        do {
            trashedDocuments = try await library.list(includeTrashed: true).filter(\.isTrashed)
            panel = .trash
        } catch { message = error.localizedDescription }
    }

    func restoreDocument(_ item: LibraryDocument) async {
        do {
            _ = try await library.restore(item.id)
            try await reloadLibrary()
            await showTrash()
        } catch { message = error.localizedDescription }
    }
}

extension TabletWorkspace {
    func saveInBackground() {
        commitComposition()
        guard backgroundTask == .invalid else {
            return
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save writing") { [weak self] in
            Task { @MainActor [weak self] in self?.finishBackgroundSave() }
        }
        Task { [weak self] in
            guard let self else {
                return
            }
            await save()
            finishBackgroundSave()
        }
    }

    private func finishBackgroundSave() {
        guard backgroundTask != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
