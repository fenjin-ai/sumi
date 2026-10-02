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
        view.textContainerInset = UIEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
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
        let coordinator = context.coordinator
        coordinator.updating = true
        defer { coordinator.updating = false }
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for:
            .monospacedSystemFont(ofSize: workspace.fontSize, weight: .regular))
        let replaced = view.text != workspace.text
        if replaced {
            view.text = workspace.text
            view.selectedRange = NSRange(
                location: min(workspace.selection.location, workspace.text.utf16.count),
                length: 0,
            )
        }
        let editable = !workspace.busy && workspace.layout != .preview
        if view.isEditable != editable {
            view.isEditable = editable
        }
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
            let color = TabletTheme.color(for: token)
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
        var updating = false
        var styledText: String?
        var fontSize: CGFloat = 0
        init(_ workspace: TabletWorkspace) {
            self.workspace = workspace
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating, textView.markedTextRange == nil else {
                return
            }
            workspace.edited(textView.text, selection: textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updating else {
                return
            }
            if textView.markedTextRange == nil, textView.text != workspace.text {
                workspace.edited(textView.text, selection: textView.selectedRange)
            } else if workspace.selection != textView.selectedRange {
                workspace.selection = textView.selectedRange
            }
        }
    }
}

struct TabletPreview: UIViewRepresentable {
    @ObservedObject var workspace: TabletWorkspace
    @Environment(\.colorScheme) private var scheme

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "leftblankPreviewReady")
        config.userContentController.add(context.coordinator, name: "leftblankPreviewError")
        config.userContentController.addUserScript(WKUserScript(
            source: PreviewScripts.setup(
                canvas: scheme == .dark ? "#171a1d" : "#fafafa",
                scheme: scheme == .dark ? "dark" : "light",
            ),
            injectionTime: .atDocumentEnd, forMainFrameOnly: true,
        ))
        config.userContentController.addUserScript(WKUserScript(
            source: """
            const report = error => window.webkit.messageHandlers.leftblankPreviewError.postMessage(String(error).slice(0, 400));
            window.addEventListener('error', event => report(event.message));
            window.addEventListener('unhandledrejection', event => report(event.reason));
            """,
            injectionTime: .atDocumentStart, forMainFrameOnly: true,
        ))
        let view = TabletPreviewWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = TabletTheme.nativeEditor
        view.accessibilityLabel = L10n.text("Document Preview")
        view.accessibilityIdentifier = "document-preview"
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.workspace = workspace
        if context.coordinator.url != workspace.previewURL {
            context.coordinator.url = workspace.previewURL
            if let url = workspace.previewURL {
                view.load(URLRequest(url: url))
            } else {
                view.loadHTMLString("", baseURL: nil)
            }
        }
        if !view.isLoading {
            let dark = scheme == .dark
            view.evaluateJavaScript(
                "window.leftblankSetChrome?.('\(dark ? "#171a1d" : "#fafafa")', '\(dark ? "dark" : "light")'); window.leftblankSetDark?.(\(dark ? "true" : "false"));",
                completionHandler: nil,
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "leftblankPreviewReady")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "leftblankPreviewError")
        view.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var workspace: TabletWorkspace
        var url: URL?
        private var recovered = false
        init(_ workspace: TabletWorkspace) {
            self.workspace = workspace
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.port == url?.port else {
                return
            }
            if message.name == "leftblankPreviewReady" {
                workspace.previewReady = true
                workspace.previewIssue = nil
            } else if let error = message.body as? String {
                workspace.previewIssue = error
            }
        }

        func webView(
            _ view: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error,
        ) {
            workspace.previewIssue = error.localizedDescription
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            workspace.previewIssue = error.localizedDescription
        }

        func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
            if !recovered {
                recovered = true
                view.reload()
            } else {
                workspace.previewIssue = L10n.text("Preview stopped unexpectedly. Reconnect typesetting to try again.")
            }
        }
    }
}

@MainActor final class TabletPreviewWebView: WKWebView {
    private var lastSize = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, lastSize != bounds.size else {
            return
        }
        lastSize = bounds.size
        // Hidden panes begin with no viewport; resizing must refit the actual
        // SVG page when preview is revealed or the iPad window changes size.
        evaluateJavaScript("window.dispatchEvent(new Event('resize'));", completionHandler: nil)
    }
}

struct TabletShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
