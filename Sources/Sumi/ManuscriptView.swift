import AppKit
import SwiftUI
import SumiCore

struct ManuscriptView: NSViewRepresentable {
    @ObservedObject var workspace: Workspace

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = NSColor(hex: 0x1C1F23)
        let editor = ManuscriptTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        editor.workspace = workspace
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.backgroundColor = NSColor(hex: 0x1C1F23)
        editor.textColor = NSColor(hex: 0xE0E2E5)
        editor.insertionPointColor = NSColor(hex: 0xD9B97C)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(hex: 0x3B4651), .foregroundColor: NSColor(hex: 0xF2F3F4)]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineFragmentPadding = 0
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel(L10n.text("Document Editor"))
        scroll.documentView = editor
        workspace.editor = editor
        editor.load(workspace.text, selection: workspace.selection)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? ManuscriptTextView else { return }
        workspace.editor = editor
        editor.setAccessibilityLabel(L10n.text("Document Editor"))
        if editor.string != workspace.text, !editor.hasMarkedText() { editor.load(workspace.text, selection: workspace.selection) }
        if editor.appliedFontSize != workspace.fontSize { editor.highlight() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(workspace) }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let workspace: Workspace
        init(_ workspace: Workspace) { self.workspace = workspace }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? ManuscriptTextView else { return }
            workspace.edited(editor.string)
            editor.scheduleHighlight()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? ManuscriptTextView else { return }
            workspace.selection = editor.selectedRange()
            editor.scheduleHighlight()
        }
    }
}

@MainActor
final class ManuscriptTextView: NSTextView {
    weak var workspace: Workspace?
    private var highlightTask: Task<Void, Never>?
    private var placeholders: [NSRange] = []
    private var placeholderIndex = 0
    private var completionItems: [JSONValue] = []
    private var highlighting = false
    private(set) var appliedFontSize: CGFloat = 0
    private var styledSource = false
    private var highlightedText: String?
    private var sourceAttributes: NSAttributedString?
    private var readingAttributes: NSAttributedString?
    private var activeParagraph: NSRange?
    private static let syntaxPatterns = [
        "(?m)^={1,6}[ \t]+.*$", "#[A-Za-z][A-Za-z0-9_.-]*",
        #""(?:[^"\\]|\\.)*""#, #"\$[^$]*\$"#, #"\*[^*\n]+\*"#, "(?m)^//.*$"
    ].map { try! NSRegularExpression(pattern: $0) }
    private weak var observedUndoManager: UndoManager?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeUndoManager()
    }

    private func observeUndoManager() {
        let manager = window == nil ? nil : undoManager
        guard observedUndoManager !== manager else { return }
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSUndoManagerDidUndoChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSUndoManagerDidRedoChange, object: nil)
        observedUndoManager = manager
        if let undoManager = manager {
            NotificationCenter.default.addObserver(self, selector: #selector(undoOrRedoCompleted), name: NSNotification.Name.NSUndoManagerDidUndoChange, object: undoManager)
            NotificationCenter.default.addObserver(self, selector: #selector(undoOrRedoCompleted), name: NSNotification.Name.NSUndoManagerDidRedoChange, object: undoManager)
        }
    }

    @objc private func undoOrRedoCompleted(_ notification: Notification) {
        // AppKit can restore the text storage without a delegate textDidChange
        // after grouped programmatic edits. Reconcile only after the whole group.
        placeholders = []
        if let workspace, workspace.text != string { workspace.edited(string) }
        workspace?.selection = selectedRange()
        scheduleHighlight()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainerInset = NSSize(width: max(36, (newSize.width - 740) / 2), height: 42)
    }

    func load(_ content: String, selection: NSRange) {
        string = content
        placeholders = []
        undoManager?.removeAllActions()
        setSelectedRange(NSRange(location: min(selection.location, (content as NSString).length), length: 0))
        highlight()
        scrollRangeToVisible(selectedRange())
    }

    func scheduleHighlight() {
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            self?.highlight()
        }
    }

    func highlight() {
        guard !highlighting, !hasMarkedText(), let storage = textStorage else { return }
        highlighting = true
        defer { highlighting = false }
        let size = workspace?.fontSize ?? 16
        let styled = workspace?.styledSource == true
        let content = string
        let active = SourcePresentation.activeParagraph(in: content, selection: selectedRange())
        let rebuild = highlightedText != content || appliedFontSize != size || styledSource != styled
        if !rebuild, activeParagraph == active { return }
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 2
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(hex: 0xD5D9DE), .paragraphStyle: paragraph]
        if rebuild {
            let source = NSMutableAttributedString(string: content, attributes: base)
            let styles: [[NSAttributedString.Key: Any]] = [
                [.foregroundColor: NSColor(hex: 0xEEE8DA), .font: NSFont.monospacedSystemFont(ofSize: size + 2, weight: .semibold)],
                [.foregroundColor: NSColor(hex: 0xA5B8C8)], [.foregroundColor: NSColor(hex: 0xA8B89A)],
                [.foregroundColor: NSColor(hex: 0xD9B97C)],
                [.foregroundColor: NSColor(hex: 0xEEE8DA), .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)],
                [.foregroundColor: NSColor(hex: 0x7C8793)]
            ]
            let whole = NSRange(location: 0, length: source.length)
            for (regex, attributes) in zip(Self.syntaxPatterns, styles) {
                for match in regex.matches(in: content, range: whole) { source.addAttributes(attributes, range: match.range) }
            }
            sourceAttributes = source
            let reading = NSMutableAttributedString(attributedString: source)
            if styled {
                for decoration in SourcePresentation.decorations(in: content) {
                    switch decoration.kind {
                    case .heading(let level):
                        reading.addAttributes([.font: NSFont.systemFont(ofSize: size + CGFloat(max(2, 8 - level * 2)), weight: .semibold), .foregroundColor: NSColor(hex: 0xEEE8DA)], range: decoration.range)
                    case .strong:
                        reading.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor(hex: 0xEEE8DA)], range: decoration.range)
                    case .emphasis:
                        reading.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: decoration.range)
                    case .code:
                        reading.addAttributes([.foregroundColor: NSColor(hex: 0xA8B89A), .backgroundColor: NSColor(hex: 0x272D32)], range: decoration.range)
                    }
                    for marker in decoration.markers {
                        reading.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear], range: marker)
                    }
                }
            }
            readingAttributes = reading
            highlightedText = content
            appliedFontSize = size
            styledSource = styled
        }
        storage.beginEditing()
        func apply(_ snapshot: NSAttributedString?, range: NSRange) {
            guard let snapshot, range.length > 0 else { return }
            snapshot.enumerateAttributes(in: range) { attributes, span, _ in
                storage.setAttributes(attributes, range: span)
            }
        }
        if rebuild { apply(readingAttributes, range: NSRange(location: 0, length: storage.length)) }
        else if let previous = activeParagraph { apply(readingAttributes, range: previous) }
        apply(sourceAttributes, range: active)
        storage.endEditing()
        activeParagraph = active
        typingAttributes = base
    }

    func insertSnippet(_ snippet: Snippet, replacing range: NSRange, focus: Bool = true) {
        guard range.location >= 0, range.location <= string.utf16.count,
              range.length >= 0, range.length <= string.utf16.count - range.location else { return }
        observeUndoManager()
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        // Use the native editing path so undo/redo also delivers textDidChange.
        // Direct NSTextStorage mutation only undid the buffer, leaving the model stale.
        insertText(snippet.text, replacementRange: range)
        observeUndoManager()
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(L10n.text("Insert Content"))
        placeholders = snippet.selections.map { NSRange(location: range.location + $0.location, length: $0.length) }
        placeholderIndex = 0
        setSelectedRange(placeholders.first ?? NSRange(location: range.location + snippet.text.utf16.count, length: 0))
        if focus { scrollRangeToVisible(selectedRange()) }
        highlight()
        if focus { window?.makeFirstResponder(self) }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let accepted = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if accepted { observeUndoManager() }
        if accepted, !placeholders.isEmpty {
            let delta = (replacementString ?? "").utf16.count - affectedCharRange.length
            if placeholderIndex < placeholders.count, affectedCharRange.location >= placeholders[placeholderIndex].location,
               NSMaxRange(affectedCharRange) <= NSMaxRange(placeholders[placeholderIndex]) {
                placeholders[placeholderIndex].length += delta
                for index in (placeholderIndex + 1)..<placeholders.count { placeholders[index].location += delta }
            } else { placeholders = [] }
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText(), event.keyCode == 48, !placeholders.isEmpty {
            placeholderIndex += event.modifierFlags.contains(.shift) ? -1 : 1
            if placeholderIndex >= 0, placeholderIndex < placeholders.count {
                setSelectedRange(placeholders[placeholderIndex]); scrollRangeToVisible(selectedRange())
            } else {
                let end = placeholders.last.map(NSMaxRange) ?? selectedRange().location
                placeholders = []; setSelectedRange(NSRange(location: end, length: 0))
            }
            return
        }
        if event.keyCode == 53, !placeholders.isEmpty { placeholders = []; setSelectedRange(NSRange(location: NSMaxRange(selectedRange()), length: 0)); return }
        if event.modifierFlags.contains(.control), event.charactersIgnoringModifiers == "." { workspace?.requestCompletion(); return }
        super.keyDown(with: event)
    }

    func presentCompletions(_ items: [JSONValue]) {
        guard !items.isEmpty else { workspace?.showMessage(L10n.text("No completions are available here.")); return }
        completionItems = items
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let entry = NSMenuItem(title: item["label"].string ?? L10n.text("Complete"), action: #selector(applyCompletion(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = index; menu.addItem(entry)
        }
        let rect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let windowRect = window?.convertFromScreen(rect) ?? .zero
        let point = convert(windowRect.origin, from: nil)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func applyCompletion(_ sender: NSMenuItem) {
        guard completionItems.indices.contains(sender.tag) else { return }
        let item = completionItems[sender.tag]
        let edit = item["textEdit"]
        let content = edit["newText"].string ?? item["insertText"].string ?? item["label"].string ?? ""
        var range = selectedRange()
        let sourceRange = edit["range"].isNull ? edit["replace"] : edit["range"]
        if !sourceRange.isNull {
            let start = TextPosition(line: sourceRange["start"]["line"].int ?? 0, character: sourceRange["start"]["character"].int ?? 0).offset(in: string)
            let end = TextPosition(line: sourceRange["end"]["line"].int ?? 0, character: sourceRange["end"]["character"].int ?? 0).offset(in: string)
            range = NSRange(location: start, length: max(0, end - start))
        }
        insertSnippet(Snippet(text: content), replacing: range)
    }
}
