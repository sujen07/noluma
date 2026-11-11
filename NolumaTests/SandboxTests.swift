import Network
import WebKit
import XCTest
@testable import Noluma

/// Counts every TCP connection made to a local port, and answers like a web server.
private final class ConnectionCounter: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return connections
    }

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock()
            self.connections += 1
            self.lock.unlock()
            connection.start(queue: .global())
            let reply = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { _, _, _, _ in
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    func start() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    self.listener.stateUpdateHandler = nil
                    continuation.resume()
                }
            }
            listener.start(queue: .global())
        }
    }

    func stop() { listener.cancel() }
}

@MainActor
final class SandboxTests: XCTestCase {
    /// A page that tries every way of reaching the network it can think of.
    private func probeHTML(port: UInt16) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"></head><body>
        <form id="f" method="post" action="http://127.0.0.1:\(port)/form"><input name="a" value="b"></form>
        <script>
        const base = 'http://127.0.0.1:\(port)';
        window.__r = {};
        (async function () {
          try { await fetch(base + '/fetch'); __r.fetch = 'reached'; } catch (e) { __r.fetch = 'blocked'; }
          await new Promise(done => {
            try {
              const x = new XMLHttpRequest();
              x.onload = () => { __r.xhr = 'reached'; done(); };
              x.onerror = () => { __r.xhr = 'blocked'; done(); };
              x.open('GET', base + '/xhr'); x.send();
            } catch (e) { __r.xhr = 'blocked'; done(); }
          });
          await new Promise(done => {
            const i = new Image();
            i.onload = () => { __r.img = 'reached'; done(); };
            i.onerror = () => { __r.img = 'blocked'; done(); };
            i.src = base + '/img.png';
            setTimeout(done, 1500);
          });
          const s = document.createElement('script'); s.src = base + '/s.js'; document.head.appendChild(s);
          const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = base + '/c.css'; document.head.appendChild(l);
          const fr = document.createElement('iframe'); fr.src = base + '/frame'; document.body.appendChild(fr);
          try { navigator.sendBeacon(base + '/beacon', 'x'); __r.beacon = 'called'; } catch (e) { __r.beacon = 'blocked'; }
          __r.ws = typeof WebSocket;
          __r.rtc = typeof RTCPeerConnection;
          __r.es = typeof EventSource;
          try { __r.open = window.open(base + '/popup') ? 'opened' : 'blocked'; } catch (e) { __r.open = 'blocked'; }
          await new Promise(done => setTimeout(done, 700));
          window.__done = true;
        })();
        </script></body></html>
        """
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func js(_ webView: WKWebView, _ script: String) async -> Any? {
        try? await webView.evaluateJavaScript(script)
    }

    private func makeSandbox(appID: UUID = UUID(), html: String) async throws -> SandboxController {
        let rules = try await SandboxPolicy.ruleList()
        let controller = SandboxController(appID: appID, ruleList: rules) { html }
        controller.load()
        return controller
    }

    /// Without the sandbox the probe page does reach the listener. This proves
    /// the next test would notice a leak.
    func testProbeReachesNetworkWithoutSandbox() async throws {
        let counter = try ConnectionCounter()
        await counter.start()
        defer { counter.stop() }

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        webView.loadHTMLString(probeHTML(port: counter.port), baseURL: URL(string: "http://127.0.0.1:\(counter.port)/"))
        let done = await waitUntil { (await self.js(webView, "window.__done === true")) as? Bool == true }
        XCTAssertTrue(done, "probe did not finish")
        XCTAssertGreaterThan(counter.count, 0, "control page should be able to reach the local listener")
    }

    func testSandboxBlocksEveryNetworkRoute() async throws {
        let counter = try ConnectionCounter()
        await counter.start()
        defer { counter.stop() }

        let controller = try await makeSandbox(html: probeHTML(port: counter.port))
        let webView = controller.webView
        let done = await waitUntil { (await self.js(webView, "window.__done === true")) as? Bool == true }
        XCTAssertTrue(done, "probe did not run inside the sandbox")

        let results = (await js(webView, "JSON.stringify(window.__r)")) as? String ?? ""
        let parsed = try JSONValue.parse(results)
        XCTAssertEqual(parsed["fetch"]?.stringValue, "blocked")
        XCTAssertEqual(parsed["xhr"]?.stringValue, "blocked")
        XCTAssertNotEqual(parsed["img"]?.stringValue, "reached")
        XCTAssertEqual(parsed["beacon"]?.stringValue, "blocked")
        XCTAssertEqual(parsed["ws"]?.stringValue, "undefined")
        XCTAssertEqual(parsed["rtc"]?.stringValue, "undefined")
        XCTAssertEqual(parsed["es"]?.stringValue, "undefined")
        XCTAssertEqual(parsed["open"]?.stringValue, "blocked")

        // Now try to leave the page entirely: a form post, then a navigation.
        _ = await js(webView, "document.getElementById('f').submit(); 0")
        try await Task.sleep(for: .milliseconds(600))
        _ = await js(webView, "location.href = 'http://127.0.0.1:\(counter.port)/nav'; 0")
        try await Task.sleep(for: .milliseconds(900))

        XCTAssertEqual(webView.url?.scheme, SandboxPolicy.scheme, "the app must stay on its own page")
        XCTAssertEqual(counter.count, 0, "a sandboxed app opened a network connection")
    }

    func testStoragePersistsPerAppAndIsIsolatedBetweenApps() async throws {
        let page = "<!doctype html><html><head></head><body><script>window.__done = true;</script></body></html>"
        let appA = UUID()
        let appB = UUID()
        addTeardownBlock {
            try? await WKWebsiteDataStore.remove(forIdentifier: appA)
            try? await WKWebsiteDataStore.remove(forIdentifier: appB)
        }

        var first: SandboxController? = try await makeSandbox(appID: appA, html: page)
        var ready = await waitUntil { (await self.js(first!.webView, "window.__done === true")) as? Bool == true }
        XCTAssertTrue(ready)
        _ = await js(first!.webView, "localStorage.setItem('secret', 'from-a'); 0")
        let written = await js(first!.webView, "localStorage.getItem('secret')") as? String
        XCTAssertEqual(written, "from-a")
        first = nil

        let again = try await makeSandbox(appID: appA, html: page)
        ready = await waitUntil { (await self.js(again.webView, "window.__done === true")) as? Bool == true }
        XCTAssertTrue(ready)
        let kept = await js(again.webView, "localStorage.getItem('secret')") as? String
        XCTAssertEqual(kept, "from-a", "an app's data should survive being reopened")

        let other = try await makeSandbox(appID: appB, html: page)
        ready = await waitUntil { (await self.js(other.webView, "window.__done === true")) as? Bool == true }
        XCTAssertTrue(ready)
        let leaked = await js(other.webView, "localStorage.getItem('secret')")
        XCTAssertFalse(leaked is String, "one app must not read another app's data")
    }

    func testPolicyIsInjectedIntoServedHTML() {
        let html = SandboxPolicy.hardenedHTML("<!doctype html><html><HEAD lang=\"en\"><title>x</title></head></html>")
        XCTAssertTrue(html.contains("<HEAD lang=\"en\"><meta http-equiv=\"Content-Security-Policy\""))
        XCTAssertTrue(SandboxPolicy.contentSecurityPolicy.contains("connect-src 'none'"))
        XCTAssertTrue(SandboxPolicy.contentSecurityPolicy.contains("default-src 'none'"))
    }

    func testOnlyTheAppsOwnURLIsAllowed() {
        let id = UUID()
        XCTAssertTrue(SandboxPolicy.isAllowed(SandboxPolicy.url(for: id), appID: id))
        XCTAssertFalse(SandboxPolicy.isAllowed(SandboxPolicy.url(for: UUID()), appID: id))
        XCTAssertFalse(SandboxPolicy.isAllowed(URL(string: "https://example.com"), appID: id))
        XCTAssertFalse(SandboxPolicy.isAllowed(nil, appID: id))
    }
}
