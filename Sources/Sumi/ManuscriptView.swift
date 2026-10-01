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
        editor.setAccessibilityLabel("Typst 文稿编辑区")
        scroll.documentView = editor
        workspace.editor = editor
        editor.load(workspace.text, selection: workspace.selection)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? ManuscriptTextView else { return }
        workspace.editor = editor
        if editor.string != workspace.text, !editor.hasMarkedText() { editor.load(workspace.text, selection: workspace.selection) }
        if editor.font?.pointSize != workspace.fontSize { editor.highlight() }
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
        guard !hasMarkedText(), let storage = textStorage else { return }
        let size = workspace?.fontSize ?? 16
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        paragraph.paragraphSpacing = 2
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(hex: 0xD5D9DE), .paragraphStyle: paragraph]
        typingAttributes = base
        self.font = font
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
        func paint(_ pattern: String, _ attributes: [NSAttributedString.Key: Any]) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: string, range: NSRange(location: 0, length: storage.length)) { storage.addAttributes(attributes, range: match.range) }
        }
        paint("(?m)^={1,6}[ \\t]+.*$", [.foregroundColor: NSColor(hex: 0xEEE8DA), .font: NSFont.monospacedSystemFont(ofSize: size + 2, weight: .semibold)])
        paint("#[A-Za-z][A-Za-z0-9_.-]*", [.foregroundColor: NSColor(hex: 0xA5B8C8)])
        paint("\"(?:[^\"\\\\]|\\\\.)*\"", [.foregroundColor: NSColor(hex: 0xA8B89A)])
        paint("\\$[^$]*\\$", [.foregroundColor: NSColor(hex: 0xD9B97C)])
        paint("\\*[^*\\n]+\\*", [.foregroundColor: NSColor(hex: 0xEEE8DA), .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)])
        paint("(?m)^//.*$", [.foregroundColor: NSColor(hex: 0x7C8793)])
        storage.endEditing()
        typingAttributes = base
    }

    func insertSnippet(_ snippet: Snippet, replacing range: NSRange) {
        guard shouldChangeText(in: range, replacementString: snippet.text) else { return }
        undoManager?.beginUndoGrouping()
        textStorage?.replaceCharacters(in: range, with: snippet.text)
        didChangeText()
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("插入 Typst 内容")
        placeholders = snippet.selections.map { NSRange(location: range.location + $0.location, length: $0.length) }
        placeholderIndex = 0
        setSelectedRange(placeholders.first ?? NSRange(location: range.location + snippet.text.utf16.count, length: 0))
        scrollRangeToVisible(selectedRange())
        highlight()
        window?.makeFirstResponder(self)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let accepted = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
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
        guard !items.isEmpty else { workspace?.showMessage("当前位置没有补全建议。"); return }
        completionItems = items
        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let entry = NSMenuItem(title: item["label"].string ?? "补全", action: #selector(applyCompletion(_:)), keyEquivalent: "")
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
