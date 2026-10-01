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
    @Published var text = ""
    @Published var fileURL: URL?
    @Published var mainFileURL: URL?
    @Published var savedText: String?
    @Published var saveStatus = "草稿"
    @Published var serviceStatus = "正在连接"
    @Published var serviceReady = false
    @Published var previewURL: URL?
    @Published var diagnostics: [DiagnosticItem] = []
    @Published var layout: EditorLayout = .writing {
        didSet {
            recordOperation("layout.changed", ["layout": layout.rawValue])
            editor?.isEditable = layout != .preview && !paletteOpen
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
    private let actionLog: ActionLog?
    private var recoveryURL: URL { stateDirectory.appendingPathComponent("recovery.json") }
    var draftURL: URL { stateDirectory.appendingPathComponent("Draft.typ") }
    var documentURL: URL { fileURL ?? draftURL }
    var compilationURL: URL { mainFileURL ?? documentURL }
    var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? "未命名文稿" }
    var position: TextPosition { TextPosition(offset: selection.location, in: text) }
    var wordCount: Int { text.filter { !$0.isWhitespace }.count }
    var filteredCommands: [WritingCommand] {
        searchMode ? WritingCommand.search(query) : WritingCommand.all.filter { $0.group == paletteGroup }
    }

    init() {
        if let override = ProcessInfo.processInfo.environment["SUMI_STATE_DIR"] { stateDirectory = URL(fileURLWithPath: override) }
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
        saveStatus = fileURL == nil ? "本地草稿" : (text == savedText ? "已保存" : "已恢复未保存内容")
        client.onNotification = { [weak self] method, params in self?.receive(method, params) }
        client.onDisconnect = { [weak self] message in
            self?.recordOperation("service.disconnected", ["reason": message])
            self?.serviceReady = false; self?.serviceStatus = "连接中断"; self?.message = message
        }
        client.onShowDocument = { [weak self] params in self?.showDocument(params) }
    }

    func startService() {
        recordOperation("service.start")
        let generation = UUID()
        serviceGeneration = generation
        serviceReady = false
        serviceStatus = "正在连接"
        diagnostics = []
        diagnosticsByURI = [:]
        outline = []
        previewURL = nil
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
                serviceStatus = "准备就绪"
                let url = try await client.startPreview(compilationURL)
                guard serviceGeneration == generation else { return }
                previewURL = url
                recordOperation("service.ready")
                try flushChanges()
                await refreshOutline()
            } catch {
                guard serviceGeneration == generation else { return }
                serviceStatus = "暂不可用"
                recordOperation("service.failed", ["error": error.localizedDescription])
                showMessage(error.localizedDescription, persistent: true)
            }
        }
    }

    func edited(_ newText: String) {
        text = newText
        documentVersion += 1
        saveStatus = fileURL == nil ? "正在保存草稿" : "尚未保存"
        if serviceReady { serviceStatus = "正在排版" }
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            let recovered = saveRecovery()
            if fileURL != nil { save() } else { saveStatus = recovered ? "草稿已保存" : "草稿保存失败" }
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
                    let current = isHeading ? [OutlineItem(title: node["name"].string ?? "标题", level: level, offset: position.offset(in: text))] : []
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
        catch { recordOperation("recovery.failed", ["error": error.localizedDescription]); showMessage("无法保存恢复副本：\(error.localizedDescription)", persistent: true); return false }
    }

    func save() {
        guard let fileURL else { saveAs(); return }
        do {
            baseline = try DocumentStorage.write(text, to: fileURL, baseline: baseline)
            savedText = text
            saveStatus = "已保存"
            recordOperation("save.finished")
            saveRecovery()
            try? client.notify("textDocument/didSave", ["textDocument": ["uri": fileURL.absoluteString]])
        } catch {
            saveStatus = "保存需要处理"
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
        panel.title = "保存文稿"
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "未命名.typ"
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.allowedContentTypes = [UTType(filenameExtension: "typ") ?? .plainText]
        present(panel) { [weak self] url in
            guard let self else { return }
            do {
                baseline = try DocumentStorage.write(text, to: url, baseline: nil)
                fileURL = url; mainFileURL = nil; savedText = text; saveStatus = "已保存"
                recordOperation("saveAs.finished")
                saveRecovery(); onTitleChange?(title); startService()
            } catch { recordOperation("saveAs.failed", ["error": error.localizedDescription]); showMessage(error.localizedDescription, persistent: true) }
        }
    }

    func openPanel(recovery: Bool = false) {
        recordOperation("open.dialog", ["recovery": String(recovery)])
        let panel = NSOpenPanel()
        panel.title = recovery ? "恢复草稿副本" : "打开 Typst 文稿"
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
                showMessage("原文稿已保留。通过「文件 → 恢复草稿副本」可重新打开。")
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
            documentVersion += 1; selection = NSRange(location: 0, length: 0)
            editor?.load(content, selection: selection)
            saveStatus = "已保存"
            saveRecovery(); onTitleChange?(title); startService()
            return true
        } catch { showMessage(error.localizedDescription, persistent: true); return false }
    }

    func newDocument() {
        recordOperation("document.new")
        guard preserveCurrent() else { return }
        fileURL = nil; mainFileURL = nil; baseline = nil; savedText = nil
        text = "#set text(font: (\"New York\", \"PingFang SC\"), size: 11pt)\n#set page(margin: 24mm)\n#set heading(numbering: \"1.\")\n\n= 新的开始\n\n"
        documentVersion += 1; selection = NSRange(location: text.utf16.count, length: 0)
        editor?.load(text, selection: selection)
        saveStatus = saveRecovery() ? "草稿已保存" : "草稿保存失败"
        onTitleChange?(title); startService()
    }

    func reload() {
        guard let fileURL else { return }
        do {
            let backup = stateDirectory.appendingPathComponent("Before-reload-\(UUID().uuidString).typ")
            _ = try DocumentStorage.write(text, to: backup, baseline: nil)
            let (content, disk) = try DocumentStorage.read(fileURL)
            text = content; savedText = content; baseline = disk; documentVersion += 1
            editor?.load(content, selection: NSRange(location: 0, length: 0))
            saveStatus = "已保存"; saveRecovery(); startService()
            showMessage("已读取磁盘版本，原编辑内容已保留为草稿副本。")
        } catch { showMessage(error.localizedDescription, persistent: true) }
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
        editor?.isEditable = layout != .preview
        if layout != .preview, let editor { editor.window?.makeFirstResponder(editor) }
    }
    func backPalette() {
        commandError = nil
        if activeCommand != nil { activeCommand = nil }
        else if paletteGroup != nil || searchMode { paletteGroup = nil; searchMode = false; query = "" }
        else { closePalette() }
        selectedCommandIndex = 0
    }
    func enterGroup(_ id: String) { paletteGroup = id; searchMode = false; activeCommand = nil; selectedCommandIndex = 0 }
    func selectCommand(_ command: WritingCommand) {
        recordOperation("command.selected", ["command": command.id, "source": searchMode ? "search" : "group"])
        commandError = nil
        if command.fields.isEmpty { execute(command) }
        else { activeCommand = command; fieldValues = Dictionary(uniqueKeysWithValues: command.fields.map { ($0.id, $0.initial) }) }
    }

    func handlePaletteKey(_ event: NSEvent) -> Bool {
        guard paletteOpen else { return false }
        if (event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        if event.keyCode == 53 { backPalette(); return true }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if activeCommand != nil { return false }
        if event.keyCode == 125 { selectedCommandIndex = min(selectedCommandIndex + 1, max(0, filteredCommands.count - 1)); return true }
        if event.keyCode == 126 { selectedCommandIndex = max(0, selectedCommandIndex - 1); return true }
        if event.keyCode == 36, !filteredCommands.isEmpty { selectCommand(filteredCommands[min(selectedCommandIndex, filteredCommands.count - 1)]); return true }
        if searchMode { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if key == "/" { searchMode = true; paletteGroup = nil; return true }
        if let group = paletteGroup, let command = WritingCommand.all.first(where: { $0.group == group && $0.key == key }) { selectCommand(command); return true }
        if paletteGroup == nil, let group = CommandGroup.all.first(where: { $0.key == key }) { enterGroup(group.id); return true }
        return true
    }

    func execute(_ command: WritingCommand) {
        recordOperation("command.execute", ["command": command.id])
        switch command.id {
        case "new": closePalette(); newDocument()
        case "open": closePalette(); openPanel()
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
        default: insert(command)
        }
    }

    private func insert(_ command: WritingCommand) {
        guard !applyingCommand, let editor, !editor.hasMarkedText() else { return }
        guard serviceReady else { commandError = "排版服务尚未就绪，暂时无法判断插入位置。你仍可直接编辑文字。"; return }
        let range = editor.selectedRange()
        let version = documentVersion, generation = serviceGeneration
        let values = fieldValues
        applyingCommand = true
        recordOperation("insertion.begin", ["command": command.id])
        Task {
            defer { applyingCommand = false }
            do {
                try flushChanges()
                if command.group != "page" {
                    var offsets = [range.location]
                    if range.length > 0 { offsets.append((text as NSString).rangeOfComposedCharacterSequence(at: NSMaxRange(range) - 1).location) }
                    if range.location == text.utf16.count, !text.isEmpty { offsets.append((text as NSString).rangeOfComposedCharacterSequence(at: range.location - 1).location) }
                    let queries: [[String: Any]] = offsets.map { ["kind": "modeAt", "position": TextPosition(offset: $0, in: text).json] }
                    let result = try await client.command("tinymist.interactCodeContext", arguments: [["textDocument": ["uri": documentURL.absoluteString], "query": queries]])
                    guard result.array.count == queries.count, result.array.allSatisfy({ $0["mode"].string == "markup" }) else {
                        throw CommandError.invalid("这个命令用于正文。当前位置属于公式、代码或注释，请回到正文后插入；现有内容未被修改。")
                    }
                }
                guard version == documentVersion, generation == serviceGeneration, paletteOpen, editor.selectedRange() == range else {
                    recordOperation("insertion.cancelled", ["command": command.id, "reason": "document, selection or panel changed"])
                    return
                }
                let selected = (text as NSString).substring(with: range)
                let snippet = try TypstInsertion.make(command.id, values: values, selection: selected)
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
        guard serviceReady, !exporting else { showMessage("请等待排版服务准备就绪。"); return }
        let panel = NSSavePanel()
        panel.title = "导出 PDF"
        panel.nameFieldStringValue = compilationURL.deletingPathExtension().lastPathComponent + ".pdf"
        panel.allowedContentTypes = [.pdf]
        present(panel) { [weak self] destination in self?.exportPDF(to: destination) }
    }

    private func exportPDF(to destination: URL) {
        recordOperation("export.begin")
        exporting = true
        Task {
            defer { exporting = false }
            do {
                try flushChanges()
                let version = documentVersion
                let result = try await client.command("tinymist.exportPdf", arguments: [compilationURL.path])
                guard let path = result["path"].string else { throw ServiceError.remote("文稿无法编译，请先处理错误后再导出。") }
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard data.starts(with: Data("%PDF".utf8)) else { throw ServiceError.remote("排版服务未生成有效 PDF。") }
                try data.write(to: destination, options: .atomic)
                recordOperation("export.finished", ["exportedVersion": String(version)])
                showMessage(version == documentVersion ? "PDF 已导出：\(destination.lastPathComponent)" : "PDF 已导出（导出开始时的文稿版本）。")
            } catch { recordOperation("export.failed", ["error": error.localizedDescription]); showMessage(error.localizedDescription, persistent: true) }
        }
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
                DiagnosticItem(message: item["message"].string ?? "未知问题", severity: item["severity"].int ?? 1,
                    position: TextPosition(line: item["range"]["start"]["line"].int ?? 0, character: item["range"]["start"]["character"].int ?? 0), url: url)
            }
            diagnostics = diagnosticsByURI.keys.sorted().flatMap { diagnosticsByURI[$0] ?? [] }
            recordOperation("diagnostics.updated", ["count": String(diagnostics.count)])
            serviceStatus = diagnostics.contains { $0.severity == 1 } ? "文稿需要检查" : "排版已更新"
        } else if method == "tinymist/compileStatus" || method == "tinymist/status" {
            recordOperation("compile.status", ["status": params["status"].string ?? "unknown"])
            if let status = params["status"].string { serviceStatus = status == "compiling" ? "正在排版" : (status == "compileError" ? "文稿需要检查" : "排版已更新") }
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
        alert.messageText = "文稿尚未安全保存"
        alert.informativeText = "无法写入恢复副本。请保存到一个可写的位置后再退出。"
        alert.addButton(withTitle: "返回文稿")
        alert.addButton(withTitle: "另存为…")
        if alert.runModal() == .alertSecondButtonReturn { saveAs() }
        return false
    }

    func shutdown() { recordOperation("session.end"); saveTask?.cancel(); syncTask?.cancel(); client.stop() }

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
        guard let actionLog else { showMessage("诊断日志目录暂时不可写。", persistent: true); return }
        recordOperation("logs.reveal")
        NSWorkspace.shared.activateFileViewerSelecting([actionLog.fileURL])
    }

    static let welcome = """
    #set page(paper: "a4", margin: 24mm)
    #set text(font: ("New York", "PingFang SC"), size: 11pt)
    #set par(leading: 0.8em)
    #set heading(numbering: "1.")

    = 给想法一点留白

    好的文字，始于一个安静的地方。

    Sumi 是你的 Typst 写作空间。在这里，文字保留原本的样子，
    排版自然发生。把注意力交给想法，剩下的慢慢来。

    == 从一句话开始

    写下你正在思考的事情。不必急着整理，也不必记住所有语法。
    按下 *⌘J*，发现此刻用得上的工具。

    - 用标题梳理思路
    - 用图片和表格解释细节
    - 用一个公式，表达一个简洁的关系

    $ E = m c^2 $

    == 看见文字的另一面

    切换到并排预览，看看文字在纸面上如何呼吸。
    每一处修改，都会成为成稿的一部分。

    #quote(block: true)[
      简洁，是让重要的东西清晰可见。
    ]

    // 你的下一段，从这里开始。

    """
}
