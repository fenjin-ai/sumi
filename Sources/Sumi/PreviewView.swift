import SwiftUI
import WebKit
import SumiCore

struct PreviewView: NSViewRepresentable {
    let url: URL
    let zoom: CGFloat
    var dark = false
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let css = """
        document.documentElement.style.background='#22262b';
        document.body.style.background='#22262b';
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
        view.setAccessibilityLabel(L10n.text("Document Preview"))
        context.coordinator.zoom = zoom
        context.coordinator.dark = dark
        if context.coordinator.loadedURL != url { context.coordinator.loadedURL = url; view.load(URLRequest(url: url)) }
        context.coordinator.applyZoom(to: view)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var zoom: CGFloat = 1
        var dark = false
        private var appliedZoom: CGFloat?
        private var appliedDark: Bool?
        let onError: (String) -> Void
        init(onError: @escaping (String) -> Void) { self.onError = onError }
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
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else { decisionHandler(.cancel); return }
            if target.host == "127.0.0.1", target.port == loadedURL?.port { decisionHandler(.allow) }
            else if target.scheme == "about" { decisionHandler(.allow) }
            else {
                decisionHandler(.cancel)
                if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(target.scheme ?? "") { NSWorkspace.shared.open(target) }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError(L10n.format("Preview failed to load: %@", error.localizedDescription)) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onError(L10n.format("Preview temporarily unavailable: %@", error.localizedDescription)) }
    }
}
