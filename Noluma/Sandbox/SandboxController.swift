import UIKit
import WebKit

/// Serves exactly one document: the app's own `index.html`.
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    private let appID: UUID
    private let html: () -> String?

    init(appID: UUID, html: @escaping () -> String?) {
        self.appID = appID
        self.html = html
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              SandboxPolicy.isAllowed(url, appID: appID),
              url.path == "/index.html" || url.path == "/" || url.path.isEmpty,
              let html = html() else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let data = Data(SandboxPolicy.hardenedHTML(html).utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": String(data.count),
                "Content-Security-Policy": SandboxPolicy.contentSecurityPolicy,
                "Cache-Control": "no-store",
                "Referrer-Policy": "no-referrer",
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

/// Owns the locked-down web view one mini-app runs in.
@MainActor
final class SandboxController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let appID: UUID
    let webView: WKWebView

    init(appID: UUID, ruleList: WKContentRuleList, html: @escaping () -> String?) {
        self.appID = appID

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AppSchemeHandler(appID: appID, html: html), forURLScheme: SandboxPolicy.scheme)
        // Storage that belongs to this app alone and survives relaunches.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: appID)
        config.userContentController.add(ruleList)
        config.userContentController.addUserScript(
            WKUserScript(source: SandboxPolicy.hardeningScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.dataDetectorTypes = []
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = false

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        #if DEBUG
        webView.isInspectable = true
        #endif
    }

    func load() {
        webView.load(URLRequest(url: SandboxPolicy.url(for: appID)))
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        SandboxPolicy.isAllowed(navigationAction.request.url, appID: appID) ? .allow : .cancel
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            present(alert) { continuation.resume() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
            present(alert) { continuation.resume(returning: false) }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                continuation.resume(returning: alert?.textFields?.first?.text ?? "")
            })
            present(alert) { continuation.resume(returning: nil) }
        }
    }

    /// Presents from whatever is on top of the web view, or calls `unavailable`
    /// when the web view is not on screen.
    private func present(_ alert: UIAlertController, unavailable: () -> Void) {
        guard var presenter = webView.window?.rootViewController else {
            unavailable()
            return
        }
        while let next = presenter.presentedViewController, !next.isBeingDismissed {
            presenter = next
        }
        presenter.present(alert, animated: true)
    }
}
