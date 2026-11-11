import Foundation

/// Talks to the Claude Messages API directly with the user's own key.
/// This is the only place in Noluma that opens a network connection.
struct ClaudeClient: AIClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that support server-side refusal fallbacks.
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-fable-5-2", "claude-sonnet-5-5"]

    let apiKey: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func makeURLRequest(_ request: AIRequest, apiKey: String) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(request.model),
            "max_tokens": .number(Double(request.maxTokens)),
            "stream": .bool(true),
            "system": .string(request.system),
            "tools": .array(request.tools),
            "messages": .array(request.messages),
            "output_config": .object(["effort": .string("medium")]),
            // Cache the growing conversation prefix between turns.
            "cache_control": .object(["type": .string("ephemeral")]),
        ]
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        if fallbackModels.contains(request.model) {
            // If a safety classifier declines, let the API retry on a fallback model.
            body["fallbacks"] = .string("default")
            urlRequest.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }

    private func run(_ request: AIRequest, continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation) async throws {
        let urlRequest = try Self.makeURLRequest(request, apiKey: apiKey)
        let (bytes, response) = try await Self.session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AIError.incomplete }

        guard http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 65_536 { break }
            }
            let message = (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?["message"]?.stringValue
            throw AIError.api(status: http.statusCode, message: message ?? "No details were provided.")
        }

        var accumulator = StreamAccumulator()
        var finished = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let event = try? JSONValue.parse(payload) else { continue }
            if event["type"]?.stringValue == "message_stop" {
                finished = true
                continue
            }
            for uiEvent in try accumulator.handle(event) {
                continuation.yield(uiEvent)
            }
        }
        guard finished else { throw AIError.incomplete }
        continuation.yield(.completed(accumulator.finish()))
    }
}
