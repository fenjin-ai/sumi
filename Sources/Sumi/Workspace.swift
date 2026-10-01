import AppKit
import Combine
import SumiCore
import UniformTypeIdentifiers

struct DiagnosticItem: Identifiable {
    let id = UUID()
    let message: String
    let severity: Int
    let position: TextPosition
    let url: URL
}

enum EditorLayout: String { case writing, split, preview }
enum SidePanel { case outline, diagnostics }

@MainActor
final class Workspace: ObservableObject {
    @Published var text = "" { didSet { textMetrics = nil } }
    @Published var fileURL: URL?
    @Published var mainFileURL: URL?
    @Published var savedText: String?
    @Published var saveStatus = "Draft"
    @Published var serviceStatus = "Connecting"
    @Published var serviceReady = false
    @Published var previewURL: URL?
    @Published var diagnostics: [DiagnosticItem] = []
    @Published var layout: EditorLayout = .writing {
        didSet {
            recordOperation("layout.changed", ["layout": layout.rawValue])
            editor?.isEditable = layout != .preview && !paletteOpen && !documentTransitionInProgress
            if !paletteOpen {
                editor?.window?.makeFirstResponder(layout == .preview ? nil : editor)
            }
        }
    }
    @Published var sidePanel: SidePanel? {
        didSet { recordOperation("sidebar.changed", ["panel": sidePanel == .outline ? "outline" : (sidePanel == .diagnostics ? "diagnostics" : "closed")]) }
    }
    @Published var fontSize: CGFloat = 16
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var message: String?
    @Published var paletteOpen = false
    @Published var paletteGroup: String?
    @Published var searchMode = false
    @Published var query = ""
    @Published var activeCommand: WritingCommand?
    @Published var fieldValues: [String: String] = [:]
    @Published var commandError: String?
    @Published var selectedCommandIndex = 0
    @Published var exporting = false
    @Published var previewZoom: CGFloat = 1
    @Published var previewDark = false
    @Published var styledSource = true {
        didSet { editor?.highlight() }
    }
    @Published var universeOpen = false
    @Published var libraryOpen = false
    @Published var documentTemplate: DocumentTemplate = .blank
    @Published var managedDocumentID: UUID?
    @Published var managedTitle: String?
    @Published var documentTransitionInProgress = false
    @Published var previewStale = true
    @Published var hasSuccessfulPreview = false
    @Published var outline: [OutlineItem] = []
    @Published var applyingCommand = false
    @Published var commandKey: String = UserDefaults.standard.string(forKey: "commandKey") ?? "j" {
        didSet { UserDefaults.standard.set(commandKey, forKey: "commandKey"); onShortcutChange?() }
    }
    weak var editor: ManuscriptTextView?
    var onTitleChange: ((String) -> Void)?
    var onShortcutChange: (() -> Void)?
    private let client = TinymistClient()
    private var baseline: DiskBaseline?
    private var diagnosticsByURI: [String: [DiagnosticItem]] = [:]
    private var documentVersion = 1
    private var serviceGeneration = UUID()
    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var sentVersion = 0
    let stateDirectory: URL
    lazy var library = LibraryController(workspace: self)
    private let actionLog: ActionLog?
    private var recoveryURL: URL { stateDirectory.appendingPathComponent("recovery.json") }
    var draftURL: URL { stateDirectory.appendingPathComponent("Draft.typ") }
    var documentURL: URL { fileURL ?? draftURL }
    var compilationURL: URL { mainFileURL ?? documentURL }
    var title: String { managedTitle ?? fileURL?.deletingPathExtension().lastPathComponent ?? L10n.text("Untitled") }
    var revision: Int { documentVersion }
    private var textMetrics: DocumentMetrics?
    private var metrics: DocumentMetrics {
        if let textMetrics { return textMetrics }
        let value = DocumentMetrics(text)
        textMetrics = value
        return value
    }
    var position: TextPosition { metrics.position(at: selection.location) }
    var wordCount: Int { metrics.wordCount }
    private var commandResults: (query: String, group: String?, searching: Bool, commands: [WritingCommand])?

    var filteredCommands: [WritingCommand] {
        if let cached = commandResults, cached.query == query, cached.group == paletteGroup, cached.searching == searchMode { return cached.commands }
        let commands = searchMode ? WritingCommand.search(query) : WritingCommand.all.filter { $0.group == paletteGroup }
        commandResults = (query, paletteGroup, searchMode, commands)
        return commands
    }
    var paletteGroups: [CommandGroup] { searchMode ? [] : CommandGroup.children(of: paletteGroup) }
    var paletteEntryCount: Int { paletteGroups.count + filteredCommands.count }
    var highlightedCommand: WritingCommand? {
        let index = selectedCommandIndex - paletteGroups.count
        return filteredCommands.indices.contains(index) ? filteredCommands[index] : nil
    }
    func keyPath(for command: WritingCommand) -> String {
        command.keyPath
    }

    init(stateDirectory directory: URL? = nil) {
        if let directory { stateDirectory = directory }
        else if let override = ProcessInfo.processInfo.environment["SUMI_STATE_DIR"] { stateDirectory = URL(fileURLWithPath: override) }
        else { stateDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sumi") }
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: stateDirectory.appendingPathComponent("Exports"), withIntermediateDirectories: true)
        actionLog = try? ActionLog(directory: stateDirectory.appendingPathComponent("Logs"))
        actionLog?.record("session.start", fields: ["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development", "pid": String(ProcessInfo.processInfo.processIdentifier)])
        if let data = try? Data(contentsOf: stateDirectory.appendingPathComponent("recovery.json")), let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data) {
            fileURL = snapshot.fileURL
            mainFileURL = snapshot.mainFileURL
            text = snapshot.text
            savedText = snapshot.savedText
            selection = NSRange(location: min(snapshot.selection, text.utf16.count), length: 0)
            if let fileURL {
                baseline = DiskBaseline(data: snapshot.savedText.map { Data($0.utf8) })
                if let disk = try? DocumentStorage.read(fileURL), snapshot.text == snapshot.savedText {
                    text = disk.0; savedText = disk.0; baseline = disk.1
                }
            }
        } else {
            text = Self.welcome
        }
        saveStatus = fileURL == nil ? "Local Draft" : (text == savedText ? "Saved" : "Unsaved Work Restored")
        client.onNotification = { [weak self] method, params in self?.receive(method, params) }
        client.onDisconnect = { [weak self] message in
            self?.recordOperation("service.disconnected", ["reason": message])
            self?.serviceReady = false; self?.serviceStatus = "Disconnected"; self?.message = message
        }
        client.onShowDocument = { [weak self] params in self?.showDocument(params) }
    }

    func startService() {
        recordOperation("service.start")
        let generation = UUID()
        serviceGeneration = generation
        serviceReady = false
        serviceStatus = "Connecting"
        diagnostics = []
        diagnosticsByURI = [:]
        outline = []
        previewURL = nil
        hasSuccessfulPreview = false
        previewStale = true
        sentVersion = 0
        Task {
            do {
                if fileURL == nil { _ = try DocumentStorage.write(text, to: draftURL, baseline: nil) }
                try await client.start(root: compilationURL.deletingLastPathComponent(), outputDirectory: stateDirectory.appendingPathComponent("Exports"))
                guard serviceGeneration == generation else { return }
                try client.open(documentURL, text: text, version: documentVersion)
                if compilationURL != documentURL {
                    try client.open(compilationURL, text: DocumentStorage.read(compilationURL).0, version: 1)
                }
                sentVersion = documentVersion
                serviceReady = true
                serviceStatus = "Ready"
                let url = try await client.startPreview(compilationURL)
                guard serviceGeneration == generation else { return }
                previewURL = url
                recordOperation("service.ready")
                try flushChanges()
                await refreshOutline()
            } catch {
                guard serviceGeneration == generation else { return }
                serviceStatus = "Unavailable"
                recordOperation("service.failed", ["error": error.localizedDescription])
                showMessage(error.localizedDescription, persistent: true)
            }
        }
    }

    func edited(_ newText: String) {
        text = newText
        documentVersion += 1
        previewStale = true
        saveStatus = fileURL == nil ? "Saving Draft" : "Unsaved"
        if serviceReady { serviceStatus = "Typesetting" }
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            let recovered = saveRecovery()
            if fileURL != nil { save() } else { saveStatus = recovered ? "Draft Saved" : "Draft Save Failed" }
        }
        syncTask?.cancel()
        syncTask = Task {
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            try? flushChanges()
            await refreshOutline()
        }
    }

    private func refreshOutline() async {
        guard serviceReady else { return }
        let version = documentVersion, generation = serviceGeneration
        do {
            let symbols = try await client.request("textDocument/documentSymbol", ["textDocument": ["uri": documentURL.absoluteString]])
            guard version == documentVersion, generation == serviceGeneration else { return }
            func headings(_ nodes: [JSONValue], level: Int) -> [OutlineItem] {
                nodes.flatMap { node -> [OutlineItem] in
                    let isHeading = node["kind"].int == 3
                    let start = node["range"]["start"]
                    let position = TextPosition(line: start["line"].int ?? 0, character: start["character"].int ?? 0)
                    let current = isHeading ? [OutlineItem(title: node["name"].string ?? L10n.text("Heading"), level: level, offset: position.offset(in: text))] : []
                    return current + headings(node["children"].array, level: isHeading ? level + 1 : level)
                }
            }
            outline = headings(symbols.array, level: 1)
        } catch { /* A failed outline refresh leaves the last valid outline visible. */ }
    }

    func flushChanges() throws {
        guard serviceReady, documentVersion != sentVersion else { return }
        try client.change(documentURL, text: text, version: documentVersion)
        sentVersion = documentVersion
    }

    @discardableResult func saveRecovery() -> Bool {
        let snapshot = RecoverySnapshot(fileURL: fileURL, text: text, savedText: savedText, selection: selection.location, mainFileURL: mainFileURL)
        do { try JSONEncoder().encode(snapshot).write(to: recoveryURL, options: .atomic); return true }
        catch { recordOperation("recovery.failed", ["error": error.localizedDescription]); showMessage(L10n.format("Could not save the recovery copy: %@", error.localizedDescription), persistent: true); return false }
    }

    func save() {
        guard let fileURL else { saveAs(); return }
        do {
            baseline = try DocumentStorage.write(text, to: fileURL, baseline: baseline)
            savedText = text
            saveStatus = "Saved"
            recordOperation("save.finished")
            saveRecovery()
            try? client.notify("textDocument/didSave", ["textDocument": ["uri": fileURL.absoluteString]])
        } catch {
            saveStatus = "Save Needs Attention"
            recordOperation("save.failed", ["error": error.localizedDescription])
            saveRecovery()
            showMessage(error.localizedDescription, persistent: true)
        }
    }

    private func present(_ panel: NSSavePanel, completion: @escaping @MainActor (URL) -> Void) {
        guard let window = editor?.window, window.attachedSheet == nil else { return }
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
    }

    func saveAs() {
        recordOperation("saveAs.dialog")
        let panel = NSSavePanel()
        panel.title = L10n.text("Save Document")
        panel.nameFieldStringValue = managedTitle.map { $0.replacingOccurrences(of: "/", with: "-") + ".typ" }
            ?? fileURL?.lastPathComponent ?? L10n.text("Untitled.typ")
        panel.directoryURL = managedDocumentID == nil ? fileURL?.deletingLastPathComponent() : nil
        panel.allowedContentTypes = [UTType(filenameExtension: "typ") ?? .plainText]
        present(panel) { [weak self] url in
            guard let self else { return }
            do {
                try save(to: url)
            } catch { recordOperation("saveAs.failed", ["error": error.localizedDescription]); showMessage(error.localizedDescription, persistent: true) }
        }
    }

    func save(to url: URL) throws {
        baseline = try DocumentStorage.write(text, to: url, baseline: url == fileURL ? baseline : nil)
        fileURL = url; mainFileURL = nil; savedText = text; saveStatus = "Saved"
        library.associate(url)
        recordOperation("saveAs.finished")
        saveRecovery(); onTitleChange?(title); startService()
    }

    func openPanel(recovery: Bool = false) {
        recordOperation("open.dialog", ["recovery": String(recovery)])
        let panel = NSOpenPanel()
        panel.title = recovery ? L10n.text("Recover Draft Copy") : L10n.text("Open Document")
        panel.directoryURL = recovery ? stateDirectory : fileURL?.deletingLastPathComponent()
        panel.allowedContentTypes = [UTType(filenameExtension: "typ") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        present(panel) { [weak self] url in self?.open(url) }
    }

    private func preserveCurrent() -> Bool {
        saveTask?.cancel()
        saveRecovery()
        if fileURL != nil, text != savedText { save() }
        if text != savedText {
            let date = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
            let backup = stateDirectory.appendingPathComponent("Draft-\(date)-\(UUID().uuidString.prefix(6)).typ")
            do {
                _ = try DocumentStorage.write(text, to: backup, baseline: nil)
                showMessage(L10n.text("Your previous document is preserved. Reopen it from Documents → Recover Draft Copy."))
            } catch { showMessage(error.localizedDescription, persistent: true); return false }
        }
        return true
    }

    @discardableResult func open(_ url: URL, preservingMain: Bool = false) -> Bool {
        recordOperation("document.open", ["preservingMain": String(preservingMain)])
        do {
            guard preserveCurrent() else { return false }
            let (content, disk) = try DocumentStorage.read(url)
            let previousMain = compilationURL
            mainFileURL = preservingMain && url != previousMain ? previousMain : nil
            fileURL = url; text = content; savedText = content; baseline = disk
            library.associate(url)
            documentVersion += 1; selection = NSRange(location: 0, length: 0)
            editor?.load(content, selection: selection)
            saveStatus = "Saved"
            saveRecovery(); onTitleChange?(title); startService()
            return true
        } catch { showMessage(error.localizedDescription, persistent: true); return false }
    }

    func newDocument() {
        recordOperation("document.new")
        library.perform { try await self.library.create() }
    }

    func reload() {
        guard let fileURL else { return }
        do {
            let backup = stateDirectory.appendingPathComponent("Before-reload-\(UUID().uuidString).typ")
            _ = try DocumentStorage.write(text, to: backup, baseline: nil)
            let (content, disk) = try DocumentStorage.read(fileURL)
            text = content; savedText = content; baseline = disk; documentVersion += 1
            editor?.load(content, selection: NSRange(location: 0, length: 0))
            saveStatus = "Saved"; saveRecovery(); startService()
            showMessage(L10n.text("Loaded the disk version. Your edits are preserved in a draft copy."))
        } catch { showMessage(error.localizedDescription, persistent: true) }
    }

    /// Incorporate an external save without replacing the text view or moving the
    /// viewport. Conflicting paragraphs stay in the live buffer and recovery file.
    func refreshFromLibrary() async {
        guard managedDocumentID != nil, let url = fileURL, let base = savedText,
              !documentTransitionInProgress, editor?.hasMarkedText() != true else { return }
        let result = await Task.detached { try? DocumentStorage.read(url) }.value
        guard let (remote, disk) = result, fileURL == url, savedText == base, remote != base else { return }
        let local = text, caret = selection, version = documentVersion
        let merge = await Task.detached(priority: .utility) {
            DocumentMerge.merge(base: base, local: local, remote: remote, selection: caret)
        }.value
        guard fileURL == url, savedText == base, documentVersion == version,
              selection == caret, editor?.hasMarkedText() != true, !documentTransitionInProgress else { return }
        guard let merged = merge else {
            saveRecovery()
            showMessage(L10n.text("This paragraph changed on another device. Your writing is safe; resolve the conflict before saving."), persistent: true)
            return
        }
        let scrollView = editor?.enclosingScrollView
        let origin = scrollView?.contentView.bounds.origin
        let wasClean = text == base
        baseline = disk
        savedText = remote
        guard merged.text != text else { saveStatus = "Saved"; saveRecovery(); return }
        if let editor {
            editor.insertSnippet(Snippet(text: merged.text), replacing: NSRange(location: 0, length: text.utf16.count), focus: false)
            editor.undoManager?.setActionName(L10n.text("Sync update"))
            editor.setSelectedRange(merged.selection)
        } else { edited(merged.text); selection = merged.selection }
        if wasClean { saveStatus = "Saved" }
        if let origin {
            scrollView?.contentView.scroll(to: origin)
            if let clip = scrollView?.contentView { scrollView?.reflectScrolledClipView(clip) }
        }
        saveRecovery()
        recordOperation("document.remoteUpdate", ["merged": String(!wasClean)])
    }

    func togglePalette() {
        recordOperation("palette.toggle")
        if paletteOpen { closePalette() } else {
            guard editor?.hasMarkedText() != true else { return }
            editor?.isEditable = false
            editor?.window?.makeFirstResponder(nil)
            paletteOpen = true; paletteGroup = nil; searchMode = false; activeCommand = nil; query = ""; commandError = nil; selectedCommandIndex = 0
        }
    }
    func closePalette() {
        recordOperation("palette.close")
        paletteOpen = false; activeCommand = nil; commandError = nil
        editor?.isEditable = layout != .preview && !documentTransitionInProgress
        if layout != .preview, let editor { editor.window?.makeFirstResponder(editor) }
    }
    func backPalette() {
        commandError = nil
        if activeCommand != nil { activeCommand = nil }
        else if searchMode { searchMode = false; query = "" }
        else if let group = paletteGroup { paletteGroup = CommandGroup.all.first { $0.id == group }?.parentID }
        else { closePalette() }
        selectedCommandIndex = 0
    }
    func enterGroup(_ id: String) { paletteGroup = id; searchMode = false; activeCommand = nil; selectedCommandIndex = 0 }
    func selectCommand(_ command: WritingCommand) {
        recordOperation("command.selected", ["command": command.id, "source": searchMode ? "search" : "group"])
        commandError = nil
        fieldValues = Dictionary(uniqueKeysWithValues: command.fields.map { ($0.id, $0.initial) })
        if command.fields.isEmpty { execute(command) }
        else { activeCommand = command }
    }

    func handlePaletteKey(_ event: NSEvent) -> Bool {
        guard paletteOpen else { return false }
        if (event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        if event.keyCode == 53 { backPalette(); return true }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if activeCommand != nil { return false }
        let grid = !searchMode && paletteGroup == nil
        let step = grid ? 3 : 1
        if event.keyCode == 125 { selectedCommandIndex = min(selectedCommandIndex + step, max(0, paletteEntryCount - 1)); return true }
        if event.keyCode == 126 { selectedCommandIndex = max(0, selectedCommandIndex - step); return true }
        if grid, event.keyCode == 124 { selectedCommandIndex = min(selectedCommandIndex + 1, max(0, paletteEntryCount - 1)); return true }
        if grid, event.keyCode == 123 { selectedCommandIndex = max(0, selectedCommandIndex - 1); return true }
        if event.keyCode == 36, paletteEntryCount > 0 {
            if paletteGroups.indices.contains(selectedCommandIndex) { enterGroup(paletteGroups[selectedCommandIndex].id) }
            else if let command = highlightedCommand { selectCommand(command) }
            return true
        }
        if searchMode { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "/" { searchMode = true; paletteGroup = nil; return true }
        if let group = paletteGroup, let command = WritingCommand.all.first(where: { $0.group == group && $0.key == key }) { selectCommand(command); return true }
        if let group = paletteGroups.first(where: { $0.key == key }) { enterGroup(group.id); return true }
        return true
    }

    func execute(_ command: WritingCommand) {
        recordOperation("command.execute", ["command": command.id])
        switch command.id {
        case "undo": closePalette(); editor?.undoManager?.undo()
        case "redo": closePalette(); editor?.undoManager?.redo()
        case "cut": closePalette(); editor?.cut(nil)
        case "copy": closePalette(); editor?.copy(nil)
        case "paste": closePalette(); editor?.paste(nil)
        case "selectAll": closePalette(); editor?.selectAll(nil)
        case "find":
            closePalette()
            if layout == .preview { layout = .split }
            let sender = NSMenuItem()
            sender.tag = NSTextFinder.Action.showFindInterface.rawValue
            editor?.performFindPanelAction(sender)
        case "fontLarger": closePalette(); fontSize = min(28, fontSize + 1)
        case "fontSmaller": closePalette(); fontSize = max(12, fontSize - 1)
        case "new": closePalette(); newDocument()
        case "newCodeNotes": closePalette(); library.perform { try await self.library.create(template: .codeNotes) }
        case "open": closePalette(); libraryOpen = true
        case "importDocument": closePalette(); library.importPanel()
        case "revealSource": closePalette(); NSWorkspace.shared.activateFileViewerSelecting([documentURL])
        case "save": closePalette(); save()
        case "saveAs": closePalette(); saveAs()
        case "reload": closePalette(); reload()
        case "drafts": closePalette(); openPanel(recovery: true)
        case "export": closePalette(); exportPDF()
        case "writing": layout = .writing; closePalette()
        case "split": layout = .split; closePalette()
        case "preview": layout = .preview; closePalette()
        case "outline": sidePanel = sidePanel == .outline ? nil : .outline; closePalette()
        case "diagnostics": sidePanel = sidePanel == .diagnostics ? nil : .diagnostics; closePalette()
        case "restart": closePalette(); startService()
        case "revealPreview": closePalette(); revealPreview()
        case "logs": closePalette(); revealLogs()
        case "universe": closePalette(); universeOpen = true
        case "previewDark": previewDark.toggle(); closePalette()
        case "styledSource": styledSource.toggle(); closePalette()
        case "format": closePalette(); formatDocument()
        case "indent": closePalette(); editLines(.indent)
        case "outdent": closePalette(); editLines(.outdent)
        case "comment": closePalette(); editLines(.comment)
        case "completion": closePalette(); requestCompletion()
        default: insert(command)
        }
    }

    func editLines(_ action: LineAction) {
        guard let editor, !editor.hasMarkedText() else { return }
        let replacement = TextEditing.lines(action, text: text, selection: editor.selectedRange())
        editor.insertSnippet(Snippet(text: replacement.text), replacing: replacement.range)
        editor.setSelectedRange(NSRange(location: replacement.range.location, length: replacement.text.utf16.count))
    }

    func formatDocument() {
        guard serviceReady, let editor, !editor.hasMarkedText() else { return }
        let version = documentVersion, generation = serviceGeneration, caret = editor.selectedRange()
        Task {
            do {
                try flushChanges()
                let result = try await client.request("textDocument/formatting", ["textDocument": ["uri": documentURL.absoluteString], "options": ["tabSize": 2, "insertSpaces": true]])
                guard documentVersion == version, serviceGeneration == generation, !editor.hasMarkedText() else { return }
                let replacements = result.array.map { edit in
                    let range = edit["range"]
                    let start = TextPosition(line: range["start"]["line"].int ?? 0, character: range["start"]["character"].int ?? 0).offset(in: text)
                    let end = TextPosition(line: range["end"]["line"].int ?? 0, character: range["end"]["character"].int ?? 0).offset(in: text)
                    return TextReplacement(range: NSRange(location: start, length: end - start), text: edit["newText"].string ?? "")
                }
                let formatted = try TextEditing.applying(replacements, to: text)
                guard formatted != text else { showMessage(L10n.text("The document is already formatted.")); return }
                editor.insertSnippet(Snippet(text: formatted), replacing: NSRange(location: 0, length: text.utf16.count))
                editor.setSelectedRange(NSRange(location: min(caret.location, formatted.utf16.count), length: 0))
                recordOperation("document.formatted")
            } catch { showMessage(error.localizedDescription) }
        }
    }

    func importPackage(_ package: UniversePackage) throws {
        guard let editor, !editor.hasMarkedText() else { throw CommandError.invalid(L10n.text("Finish the current input before inserting a package.")) }
        guard package.isCompatible(with: "0.15.1") else { throw CommandError.invalid(L10n.text("This version requires a newer Typst. Check Universe for a compatible version.")) }
        let snippet = try package.pinnedImport()
        if text.contains(TypstInsertion.quoted(package.reference)) { throw CommandError.invalid(L10n.text("This package version is already imported.")) }
        if layout == .preview { layout = .split }
        editor.insertSnippet(snippet.padded(before: "", after: "\n"), replacing: NSRange(location: 0, length: 0))
        recordOperation("package.imported", ["package": package.reference])
    }

    private func insert(_ command: WritingCommand) {
        guard !applyingCommand, let editor, !editor.hasMarkedText() else { return }
        guard serviceReady else { commandError = L10n.text("The typesetting service is not ready to check the insertion position. You can still edit directly."); return }
        let range = editor.selectedRange()
        let version = documentVersion, generation = serviceGeneration
        let values = fieldValues
        applyingCommand = true
        recordOperation("insertion.begin", ["command": command.id])
        Task {
            defer { applyingCommand = false }
            do {
                try flushChanges()
                var insertionContext = InsertionContext.markup
                if command.placement != .preamble {
                    var offsets = [range.location]
                    if range.length > 0 { offsets.append((text as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(range) - 1).location) }
                    if range.location == text.utf16.count, !text.isEmpty { offsets.append((text as NSString).rangeOfComposedCharacterSequence(at: range.location - 1).location) }
                    let queries: [[String: Any]] = offsets.map { ["kind": "modeAt", "position": TextPosition(offset: $0, in: text).json] }
                    let result = try await client.command("tinymist.interactCodeContext", arguments: [["textDocument": ["uri": documentURL.absoluteString], "query": queries]])
                    let modes = result.array.compactMap { $0["mode"].string }
                    guard modes.count == queries.count, Set(modes).count == 1, modes.allSatisfy(command.acceptsContext) else {
                        throw CommandError.invalid(command.supportsMath ? L10n.text("Insert within body text or a single equation, without crossing code or comments.") : L10n.text("This command works in body text. Move out of equations, code or comments and try again. Your text is unchanged."))
                    }
                    insertionContext = modes.first == "math" ? .math : .markup
                }
                guard version == documentVersion, generation == serviceGeneration, paletteOpen, editor.selectedRange() == range else {
                    recordOperation("insertion.cancelled", ["command": command.id, "reason": "document, selection or panel changed"])
                    return
                }
                let selected = (text as NSString).substring(with: range)
                let snippet = try TypstInsertion.make(command.id, values: values, selection: selected, context: insertionContext)
                let plan = InsertionPlan(command: command, snippet: snippet, text: text, selection: range)
                closePalette()
                if layout == .preview { layout = .split }
                editor.insertSnippet(plan.snippet, replacing: plan.range)
                recordOperation("insertion.finished", ["command": command.id, "insertedUTF16": String(plan.snippet.text.utf16.count)])
            } catch { recordOperation("insertion.failed", ["command": command.id, "error": error.localizedDescription]); commandError = error.localizedDescription }
        }
    }

    func jump(to offset: Int) {
        if layout == .preview { layout = .split }
        selection = NSRange(location: min(max(0, offset), text.utf16.count), length: 0)
        editor?.setSelectedRange(selection)
        editor?.scrollRangeToVisible(selection)
        if let editor { editor.window?.makeFirstResponder(editor) }
    }

    func revealPreview() {
        if layout == .writing { layout = .split }
        let current = position
        Task {
            do { _ = try await client.command("tinymist.scrollPreview", arguments: ["sumi", ["event": "panelScrollTo", "filepath": documentURL.path, "line": current.line, "character": current.utf8Column(in: text)]]) }
            catch { showMessage(error.localizedDescription) }
        }
    }

    func exportPDF() {
        recordOperation("export.dialog")
        guard serviceReady, !exporting else { showMessage(L10n.text("Please wait for the typesetting service to be ready.")); return }
        let panel = NSSavePanel()
        panel.title = L10n.text("Export PDF")
        panel.nameFieldStringValue = (managedTitle?.replacingOccurrences(of: "/", with: "-")
            ?? compilationURL.deletingPathExtension().lastPathComponent) + ".pdf"
        panel.allowedContentTypes = [.pdf]
        present(panel) { [weak self] destination in
            Task { @MainActor in
                guard let self else { return }
                do { try await self.exportPDF(to: destination) }
                catch { self.showMessage(error.localizedDescription, persistent: true) }
            }
        }
    }

    func exportPDF(to destination: URL) async throws {
        guard serviceReady, !exporting else { throw ServiceError.remote(L10n.text("Please wait for the typesetting service to be ready.")) }
        recordOperation("export.begin")
        exporting = true
        defer { exporting = false }
            do {
                try flushChanges()
                let version = documentVersion
                let result = try await client.command("tinymist.exportPdf", arguments: [compilationURL.path])
                guard let path = result["path"].string else { throw ServiceError.remote(L10n.text("The document cannot be compiled. Resolve the errors before exporting.")) }
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard data.starts(with: Data("%PDF".utf8)) else { throw ServiceError.remote(L10n.text("The typesetting service did not produce a valid PDF.")) }
                try data.write(to: destination, options: .atomic)
                recordOperation("export.finished", ["exportedVersion": String(version)])
                showMessage(version == documentVersion ? L10n.format("PDF exported: %@", destination.lastPathComponent) : L10n.text("PDF exported using the document version from when export began."))
            } catch { recordOperation("export.failed", ["error": error.localizedDescription]); throw error }
    }

    func requestCompletion() {
        guard serviceReady, !paletteOpen, layout != .preview, editor?.hasMarkedText() != true else { return }
        let version = documentVersion
        let caret = selection
        Task {
            do {
                try flushChanges()
                let result = try await client.request("textDocument/completion", ["textDocument": ["uri": documentURL.absoluteString], "position": position.json, "context": ["triggerKind": 1]])
                guard version == documentVersion, caret == selection, !paletteOpen, layout != .preview, editor?.hasMarkedText() != true else { return }
                let candidates = result.array.isEmpty ? result["items"].array : result.array
                editor?.presentCompletions(Array(candidates.prefix(12)))
            } catch { showMessage(error.localizedDescription) }
        }
    }

    private func receive(_ method: String, _ params: JSONValue) {
        if method == "textDocument/publishDiagnostics", let uri = params["uri"].string, let url = URL(string: uri), url.isFileURL {
            if url == documentURL, let version = params["version"].int, version < documentVersion { return }
            diagnosticsByURI[uri] = params["diagnostics"].array.map { item in
                DiagnosticItem(message: item["message"].string ?? L10n.text("Unknown Issue"), severity: item["severity"].int ?? 1,
                    position: TextPosition(line: item["range"]["start"]["line"].int ?? 0, character: item["range"]["start"]["character"].int ?? 0), url: url)
            }
            diagnostics = diagnosticsByURI.keys.sorted().flatMap { diagnosticsByURI[$0] ?? [] }
            recordOperation("diagnostics.updated", ["count": String(diagnostics.count)])
            if diagnostics.contains(where: { $0.severity == 1 }) {
                previewStale = true
                serviceStatus = hasSuccessfulPreview ? "Showing Last Preview · Check Source" : "Document Needs Attention"
            }
        } else if method == "tinymist/compileStatus" || method == "tinymist/status" {
            recordOperation("compile.status", ["status": params["status"].string ?? "unknown"])
            if let status = params["status"].string {
                switch status {
                case "compiling": previewStale = true; serviceStatus = "Typesetting"
                case "compileError":
                    previewStale = true
                    serviceStatus = hasSuccessfulPreview ? "Showing Last Preview · Check Source" : "Document Needs Attention"
                case "compileSuccess":
                    hasSuccessfulPreview = true
                    previewStale = documentVersion != sentVersion
                    serviceStatus = previewStale ? "Typesetting" : "Preview Updated"
                default: break
                }
            }
        }
    }

    private func showDocument(_ params: JSONValue) {
        guard let uri = params["uri"].string, let url = URL(string: uri), url.isFileURL else { return }
        if url.standardizedFileURL != documentURL.standardizedFileURL, !open(url, preservingMain: true) { return }
        let start = params["selection"]["start"]
        jump(to: TextPosition(line: start["line"].int ?? 0, character: start["character"].int ?? 0).offset(in: text))
    }

    func showDiagnostic(_ item: DiagnosticItem) {
        if item.url != documentURL, !open(item.url, preservingMain: true) { return }
        jump(to: item.position.offset(in: text))
    }

    func showMessage(_ value: String, persistent: Bool = false) {
        messageTask?.cancel(); message = value
        if !persistent {
            messageTask = Task {
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                message = nil
            }
        }
    }

    func prepareToClose() -> Bool {
        saveTask?.cancel()
        if fileURL != nil, text != savedText { save() }
        if saveRecovery() { return true }
        let alert = NSAlert()
        alert.messageText = L10n.text("Your Document Has Not Been Saved Safely")
        alert.informativeText = L10n.text("The recovery copy could not be written. Save to a writable location before quitting.")
        alert.addButton(withTitle: L10n.text("Return to Document"))
        alert.addButton(withTitle: L10n.text("Save As…"))
        if alert.runModal() == .alertSecondButtonReturn { saveAs() }
        return false
    }

    func shutdown() { recordOperation("session.end"); saveTask?.cancel(); syncTask?.cancel(); library.stop(); client.stop() }

    func recordOperation(_ event: String, _ fields: [String: String] = [:]) {
        var context = fields
        context["documentVersion"] = String(documentVersion)
        context["selection"] = "\(selection.location):\(selection.length)"
        actionLog?.record(event, fields: context)
    }

    func recordKeyEvent(_ event: NSEvent, stage: String) {
        let special: [UInt16: String] = [36: "Return", 48: "Tab", 51: "Delete", 53: "Escape", 76: "Enter", 115: "Home", 116: "PageUp", 117: "ForwardDelete", 119: "End", 121: "PageDown", 123: "Left", 124: "Right", 125: "Down", 126: "Up"]
        let flags = event.modifierFlags
        let modifiers = [(NSEvent.ModifierFlags.command, "cmd"), (.control, "ctrl"), (.option, "option"), (.shift, "shift")].filter { flags.contains($0.0) }.map(\.1).joined(separator: "+")
        // Never retain printable input or search terms. Only shortcut chords and
        // navigation keys need their actual key identity for diagnosing routing.
        let shortcut = event.charactersIgnoringModifiers?.uppercased() ?? "keyCode:\(event.keyCode)"
        let key = special[event.keyCode] ?? (flags.intersection([.command, .control]).isEmpty ? "text" : shortcut)
        recordOperation("key.down", ["key": key, "modifiers": modifiers, "stage": stage, "panel": activeCommand != nil ? "parameters" : (searchMode && paletteOpen ? "search" : (paletteOpen ? "groups" : "editor")), "markedText": String((event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true)])
    }

    func revealLogs() {
        guard let actionLog else { showMessage(L10n.text("The diagnostic log folder is not writable."), persistent: true); return }
        recordOperation("logs.reveal")
        NSWorkspace.shared.activateFileViewerSelecting([actionLog.fileURL])
    }

    static var welcome: String { WelcomeDocument.source() }
}
