import SwiftUI
import WebKit
import SumiCore

struct PreviewView: NSViewRepresentable {
    let url: URL
    let zoom: CGFloat
    var dark = false
    var onLoading: () -> Void = {}
    var onReady: () -> Void = {}
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoading: onLoading, onReady: onReady, onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "sumiPreviewReady")
        let css = """
        document.documentElement.style.background='#22262b';
        document.body.style.background='#22262b';
        // Tinymist 0.15.8 mixes off-screen canvas pages into SVG foreignObjects.
        // In WebKit these create enormous backing layers for book-length SVGs.
        // Keep its viewport SVG renderer, without the optional canvas fallback.
        const container = document.getElementById('typst-container');
        const svgOnly = doc => {
            if (doc?.impl?.renderMode === 'svg' && 'feat$canvas' in doc.impl) doc.impl.feat$canvas = false;
        };
        const watchDocuments = documents => {
            if (!Array.isArray(documents)) return documents;
            documents.forEach(svgOnly);
            const push = documents.push;
            documents.push = function(...docs) { docs.forEach(svgOnly); return push.apply(this, docs); };
            return documents;
        };
        if (container) {
            let documents = watchDocuments(container.documents);
            Object.defineProperty(container, 'documents', {
                configurable: true,
                get: () => documents,
                set: value => { documents = watchDocuments(value); }
            });
        }
        const checkReady = () => {
            if (document.querySelector('.typst-doc > g.typst-page')) {
                readyObserver.disconnect();
                window.webkit.messageHandlers.sumiPreviewReady.postMessage('ready');
            }
        };
        const readyObserver = new MutationObserver(checkReady);
        readyObserver.observe(document.body, {childList: true, subtree: true});
        checkReady();
        window.sumiSetDark = (dark) => {
            window.sumiPreviewDark = dark;
            const root = document.getElementById('typst-app');
            if (!root) return;
            if (root.classList.contains('invert-colors') !== dark) root.classList.toggle('invert-colors', dark);
            if (!root.classList.contains('normal-image')) root.classList.add('normal-image');
        };
        const root = document.getElementById('typst-app');
        if (root) new MutationObserver(() => window.sumiSetDark(!!window.sumiPreviewDark))
            .observe(root, {attributes: true, attributeFilter: ['class']});
        """
        config.userContentController.addUserScript(WKUserScript(source: css, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = NSColor(hex: 0x22262B)
        view.setAccessibilityLabel(L10n.text("Document Preview"))
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onLoading = onLoading
        context.coordinator.onReady = onReady
        view.setAccessibilityLabel(L10n.text("Document Preview"))
        context.coordinator.zoom = zoom
        context.coordinator.dark = dark
        if context.coordinator.loadedURL != url { context.coordinator.loadedURL = url; view.load(URLRequest(url: url)) }
        context.coordinator.applyZoom(to: view)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var loadedURL: URL? {
            didSet { if loadedURL != oldValue { recoveredTermination = false } }
        }
        var zoom: CGFloat = 1
        var dark = false
        private var appliedZoom: CGFloat?
        private var appliedDark: Bool?
        private var recoveredTermination = false
        let onError: (String) -> Void
        var onLoading: () -> Void
        var onReady: () -> Void
        init(onLoading: @escaping () -> Void = {}, onReady: @escaping () -> Void = {}, onError: @escaping (String) -> Void) {
            self.onLoading = onLoading; self.onReady = onReady; self.onError = onError
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "sumiPreviewReady", message.frameInfo.isMainFrame,
               message.frameInfo.request.url?.port == loadedURL?.port { onReady() }
        }
        func applyZoom(to view: WKWebView) {
            guard !view.isLoading, appliedZoom != zoom || appliedDark != dark else { return }
            // Tinymist fits pages to this container; browser pageZoom is cancelled by that fit.
            let script = """
            (() => {
                const container = document.getElementById('typst-container');
                if (!container) return false;
                container.style.width = '\(zoom * 100)%';
                if (window.sumiSetDark) window.sumiSetDark(\(dark ? "true" : "false"));
                window.dispatchEvent(new Event('resize'));
                return true;
            })()
            """
            let requestedZoom = zoom
            let requestedDark = dark
            view.evaluateJavaScript(script) { [weak self] result, _ in
                if result as? Bool == true { self?.appliedZoom = requestedZoom; self?.appliedDark = requestedDark }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            appliedZoom = nil
            appliedDark = nil
            applyZoom(to: webView)
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { onLoading() }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else { decisionHandler(.cancel); return }
            if target.host == "127.0.0.1", target.port == loadedURL?.port { decisionHandler(.allow) }
            else if target.scheme == "about" { decisionHandler(.allow) }
            else {
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(target.scheme ?? "") { NSWorkspace.shared.open(target) }
            }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            appliedZoom = nil; appliedDark = nil
            if !recoveredTermination {
                recoveredTermination = true
                webView.reload()
            } else {
                onError(L10n.text("Preview stopped unexpectedly. Reconnect typesetting to try again."))
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError(L10n.format("Preview failed to load: %@", error.localizedDescription)) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onError(L10n.format("Preview temporarily unavailable: %@", error.localizedDescription)) }
    }
}
