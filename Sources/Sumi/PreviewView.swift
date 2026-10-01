import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let url: URL
    let zoom: CGFloat
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let css = "document.documentElement.style.background='#22262b';document.body.style.background='#22262b';"
        config.userContentController.addUserScript(WKUserScript(source: css, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = NSColor(hex: 0x22262B)
        view.setAccessibilityLabel("Typst 成稿预览")
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.zoom = zoom
        if context.coordinator.loadedURL != url { context.coordinator.loadedURL = url; view.load(URLRequest(url: url)) }
        context.coordinator.applyZoom(to: view)
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?
        var zoom: CGFloat = 1
        private var appliedZoom: CGFloat?
        let onError: (String) -> Void
        init(onError: @escaping (String) -> Void) { self.onError = onError }
        func applyZoom(to view: WKWebView) {
            guard !view.isLoading, appliedZoom != zoom else { return }
            // Tinymist fits pages to this container; browser pageZoom is cancelled by that fit.
            let script = """
            (() => {
                const container = document.getElementById('typst-container');
                if (!container) return false;
                container.style.width = '\(zoom * 100)%';
                window.dispatchEvent(new Event('resize'));
                return true;
            })()
            """
            let requestedZoom = zoom
            view.evaluateJavaScript(script) { [weak self] result, _ in
                if result as? Bool == true { self?.appliedZoom = requestedZoom }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            appliedZoom = nil
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
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError("预览加载失败：\(error.localizedDescription)") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onError("预览暂时不可用：\(error.localizedDescription)") }
    }
}
