import Foundation

/// A scripted stand-in for Claude, used when the app is launched with `-mockAI`
/// so the chat flow can be exercised without an API key or any network access.
struct MockAIClient: AIClient {
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let afterTool = request.messages.last?["content"]?.arrayValue?
            .contains { $0["type"]?.stringValue == "tool_result" } ?? false
        let builds = request.messages.filter { message in
            message["content"]?.arrayValue?.contains { $0["type"]?.stringValue == "tool_use" } ?? false
        }.count

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if afterTool {
                        let text = builds > 1
                            ? "Updated. Open the card above to see the new version; your count is still there."
                            : "Your tap counter is ready. Open it from the card above, tap the big button to count, and it remembers the number between launches."
                        try await Self.type(text, into: continuation)
                        continuation.yield(.completed(AIResponse(blocks: [.text(text)], stopReason: "end_turn")))
                    } else {
                        let text = "Here's a simple counter to start with."
                        try await Self.type(text, into: continuation)
                        continuation.yield(.toolStarted(name: AppBuilderPrompt.toolName))
                        for step in 1...8 {
                            try await Task.sleep(for: .milliseconds(150))
                            continuation.yield(.toolProgress(characters: step * 400))
                        }
                        let toolUse: JSONValue = .object([
                            "type": .string("tool_use"),
                            "id": .string("toolu_mock_\(builds + 1)"),
                            "name": .string(AppBuilderPrompt.toolName),
                            "input": .object([
                                "name": .string("Tap Counter"),
                                "summary": .string("Counts taps and remembers the total."),
                                "icon": .string("hand.tap.fill"),
                                "tint": .string(builds > 0 ? "pink" : "teal"),
                                "html": .string(Self.html(accent: builds > 0 ? "#ff2d55" : "#30b0c7")),
                            ]),
                        ])
                        continuation.yield(.completed(AIResponse(blocks: [.text(text), toolUse], stopReason: "tool_use")))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func type(_ text: String, into continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation) async throws {
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            try await Task.sleep(for: .milliseconds(35))
            continuation.yield(.textDelta(String(word) + " "))
        }
    }

    private static func html(accent: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; min-height: 100vh; display: flex; flex-direction: column; align-items: center;
                 justify-content: center; gap: 32px; font-family: -apple-system, system-ui; }
          #count { font-size: 96px; font-weight: 700; font-variant-numeric: tabular-nums; }
          button { font: inherit; border: 0; border-radius: 999px; }
          #tap { width: 200px; height: 200px; background: \(accent); color: #fff; font-size: 28px; font-weight: 600; }
          #tap:active { transform: scale(.96); }
          #reset { padding: 12px 24px; background: rgba(127,127,127,.2); color: inherit; }
        </style></head>
        <body>
          <div id="count">0</div>
          <button id="tap">Tap</button>
          <button id="reset">Reset</button>
          <script>
            let n = Number(localStorage.getItem('count') || 0);
            const el = document.getElementById('count');
            const show = () => { el.textContent = n; localStorage.setItem('count', n); };
            document.getElementById('tap').onclick = () => { n++; show(); };
            document.getElementById('reset').onclick = () => { n = 0; show(); };
            show();
          </script>
        </body></html>
        """
    }
}
