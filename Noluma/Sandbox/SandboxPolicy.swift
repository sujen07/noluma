import Foundation
import WebKit

/// The rules that keep every mini-app offline. Each layer is independent, so a
/// gap in one is still covered by the others:
///
/// 1. the app is served from a private URL scheme that only returns its own HTML
/// 2. a Content-Security-Policy forbids every kind of outbound request
/// 3. a WebKit content rule list blocks all URLs outside that scheme
/// 4. navigation away from the app and new windows are refused
/// 5. a script removes network APIs the layers above don't govern (WebRTC etc.)
/// 6. each app gets its own isolated, persistent storage
enum SandboxPolicy {
    static let scheme = "noluma-app"

    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'unsafe-inline'",
        "style-src 'unsafe-inline'",
        "img-src data: blob:",
        "media-src data: blob:",
        "font-src data:",
        "connect-src 'none'",
        "form-action 'none'",
        "frame-src 'none'",
        "worker-src 'none'",
        "object-src 'none'",
        "base-uri 'none'",
    ].joined(separator: "; ")

    /// Block everything, then exempt the app's own scheme and inline data.
    static let contentRules = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^noluma-app://"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    /// Runs before any app code. WebRTC is not governed by CSP or content rules,
    /// so the constructors are removed outright; the rest is defense in depth.
    static let hardeningScript = """
    (function () {
      var names = ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCSessionDescription',
                   'RTCIceCandidate', 'WebSocket', 'EventSource', 'WebTransport', 'SharedWorker', 'Worker'];
      names.forEach(function (name) {
        try { Object.defineProperty(window, name, { value: undefined, writable: false, configurable: false }); } catch (e) {}
      });
      try { Object.defineProperty(Navigator.prototype, 'sendBeacon', { value: undefined, writable: false, configurable: false }); } catch (e) {}
      try { Object.defineProperty(Navigator.prototype, 'serviceWorker', { value: undefined, writable: false, configurable: false }); } catch (e) {}
      window.open = function () { return null; };
    })();
    """

    static func url(for appID: UUID) -> URL {
        URL(string: "\(scheme)://\(appID.uuidString.lowercased())/index.html")!
    }

    static func isAllowed(_ url: URL?, appID: UUID) -> Bool {
        guard let url else { return false }
        return url.scheme == scheme && url.host == appID.uuidString.lowercased()
    }

    @MainActor private static var compiledRules: WKContentRuleList?

    /// The compiled block list. Apps are never shown without it.
    @MainActor
    static func ruleList() async throws -> WKContentRuleList {
        if let compiledRules { return compiledRules }
        let list: WKContentRuleList? = try await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "noluma-sandbox-v1", encodedContentRuleList: contentRules)
        guard let list else { throw SandboxError.rulesUnavailable }
        compiledRules = list
        return list
    }

    /// Adds the policy as a meta tag too, in case a header is ever ignored.
    static func hardenedHTML(_ html: String) -> String {
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
        guard let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) else {
            return html
        }
        var html = html
        html.insert(contentsOf: meta, at: head.upperBound)
        return html
    }
}

enum SandboxError: LocalizedError {
    case rulesUnavailable

    var errorDescription: String? {
        "Noluma couldn't set up the offline sandbox, so the app was not opened."
    }
}
