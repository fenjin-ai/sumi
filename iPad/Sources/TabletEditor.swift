import LeftBlankCore
import SwiftUI
import UIKit
import WebKit

struct TabletEditor: UIViewRepresentable {
    @ObservedObject var workspace: TabletWorkspace

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = TabletTheme.nativeEditor
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.adjustsFontForContentSizeCategory = true
        view.isFindInteractionEnabled = true
        view.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        view.accessibilityLabel = L10n.text("Writing")
        view.accessibilityIdentifier = "manuscript"
        workspace.editor = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.workspace = workspace
        guard view.markedTextRange == nil else {
            return
        }
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for:
            .monospacedSystemFont(ofSize: workspace.fontSize, weight: .regular))
        let coordinator = context.coordinator
        let replaced = view.text != workspace.text
        if replaced {
            view.text = workspace.text
            view.selectedRange = NSRange(
                location: min(workspace.selection.location, workspace.text.utf16.count),
                length: 0,
            )
        }
        view.isEditable = !workspace.busy && workspace.layout != .preview
        view.typingAttributes = [.foregroundColor: TabletTheme.nativeText, .font: font]
        let syntaxReady = workspace.highlightedText == workspace.text
        let syntaxChanged = syntaxReady && coordinator.styledText != workspace.highlightedText
        guard replaced || coordinator.fontSize != font.pointSize || syntaxChanged else {
            return
        }
        coordinator.fontSize = font.pointSize
        if syntaxReady {
            coordinator.styledText = workspace.highlightedText
        }
        // Recolor on settled syntax revisions, never on caret movement or every
        // keystroke. UIKit preserves composition, typing attributes and undo.
        let storage = view.textStorage
        let selected = view.selectedRange
        storage.beginEditing()
        storage.addAttributes(
            [.foregroundColor: TabletTheme.nativeText, .font: font],
            range: NSRange(location: 0, length: storage.length),
        )
        for token in syntaxReady ? workspace.tokens : [] where NSMaxRange(token.range) <= storage.length {
            let color: UIColor = token.kind.lowercased().contains("comment") ? TabletTheme.nativeSecondary : TabletTheme
                .nativeAccent
            storage.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        storage.endEditing()
        view.selectedRange = selected
        view.typingAttributes = [.foregroundColor: TabletTheme.nativeText, .font: font]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var workspace: TabletWorkspace
        var styledText: String?
        var fontSize: CGFloat = 0
        init(_ workspace: TabletWorkspace) {
            self.workspace = workspace
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else {
                return
            }
            workspace.edited(textView.text, selection: textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.markedTextRange == nil, textView.text != workspace.text {
                workspace.edited(textView.text, selection: textView.selectedRange)
            } else if workspace.selection != textView.selectedRange {
                workspace.selection = textView.selectedRange
            }
        }
    }
}

struct TabletPreview: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isInspectable = false
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        view.accessibilityLabel = L10n.text("Preview")
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.url != url else {
            return
        }
        context.coordinator.url = url
        if let url {
            view.load(URLRequest(url: url))
        } else {
            view.loadHTMLString("", baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator { var url: URL? }
}

struct TabletShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
