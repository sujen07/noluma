import Foundation

struct AIRequest: Sendable {
    var model: String
    var system: String
    var messages: [JSONValue]
    var tools: [JSONValue]
    var maxTokens = 64_000
}

struct AIResponse: Sendable, Equatable {
    /// Content blocks to store and send back unchanged on the next request.
    var blocks: [JSONValue]
    var stopReason: String?
    /// Tool calls whose streamed input was not valid JSON (for example, cut off).
    var invalidToolUseIDs: Set<String> = []
}

enum AIStreamEvent: Sendable {
    case textDelta(String)
    case toolStarted(name: String)
    case toolProgress(characters: Int)
    case completed(AIResponse)
}

enum AIError: LocalizedError {
    case api(status: Int, message: String)
    case stream(String)
    case incomplete

    var errorDescription: String? {
        switch self {
        case .api(let status, let message):
            switch status {
            case 401: "Claude rejected the API key. Check it in Settings."
            case 429: "Claude is rate limiting this key right now. Try again in a moment."
            case 529: "Claude is overloaded right now. Try again in a moment."
            default: "Claude returned an error (\(status)): \(message)"
            }
        case .stream(let message): "Claude reported a problem: \(message)"
        case .incomplete: "The reply ended before it was complete. Try again."
        }
    }
}

protocol AIClient: Sendable {
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}

/// Turns the Messages API's server-sent events into finished content blocks.
struct StreamAccumulator {
    private struct Builder {
        var block: [String: JSONValue]
        var partialJSON = ""
    }

    private var builders: [Int: Builder] = [:]
    private var stopReason: String?

    /// Consumes one decoded `data:` payload and returns UI events for it.
    mutating func handle(_ event: JSONValue) throws -> [AIStreamEvent] {
        guard let type = event["type"]?.stringValue else { return [] }
        switch type {
        case "content_block_start":
            guard let index = event["index"]?.intValue,
                  let block = event["content_block"]?.objectValue else { return [] }
            builders[index] = Builder(block: block)
            if block["type"]?.stringValue == "tool_use", let name = block["name"]?.stringValue {
                return [.toolStarted(name: name)]
            }
            if let text = block["text"]?.stringValue, block["type"]?.stringValue == "text", !text.isEmpty {
                return [.textDelta(text)]
            }
            return []

        case "content_block_delta":
            guard let index = event["index"]?.intValue,
                  let delta = event["delta"],
                  var builder = builders[index] else { return [] }
            defer { builders[index] = builder }
            switch delta["type"]?.stringValue {
            case "text_delta":
                let text = delta["text"]?.stringValue ?? ""
                builder.block["text"] = .string((builder.block["text"]?.stringValue ?? "") + text)
                return [.textDelta(text)]
            case "input_json_delta":
                builder.partialJSON += delta["partial_json"]?.stringValue ?? ""
                return [.toolProgress(characters: builder.partialJSON.count)]
            case "thinking_delta":
                let thinking = delta["thinking"]?.stringValue ?? ""
                builder.block["thinking"] = .string((builder.block["thinking"]?.stringValue ?? "") + thinking)
                return []
            case "signature_delta":
                builder.block["signature"] = delta["signature"] ?? .null
                return []
            default:
                return []
            }

        case "message_delta":
            if let reason = event["delta"]?["stop_reason"]?.stringValue {
                stopReason = reason
            }
            return []

        case "error":
            throw AIError.stream(event["error"]?["message"]?.stringValue ?? "unknown error")

        default:
            return []
        }
    }

    func finish() -> AIResponse {
        var invalid: Set<String> = []
        let blocks: [JSONValue] = builders.keys.sorted().compactMap { index in
            guard var block = builders[index]?.block else { return nil }
            if block["type"]?.stringValue == "tool_use" {
                let raw = builders[index]?.partialJSON ?? ""
                if raw.isEmpty {
                    block["input"] = block["input"] ?? .object([:])
                } else if let parsed = try? JSONValue.parse(raw), parsed.objectValue != nil {
                    block["input"] = parsed
                } else {
                    block["input"] = .object([:])
                    if let id = block["id"]?.stringValue { invalid.insert(id) }
                }
            }
            // Optional fields arrive as null; the API prefers them absent on the way back.
            block = block.filter { $0.value != .null }
            return .object(block)
        }
        return AIResponse(blocks: blocks, stopReason: stopReason, invalidToolUseIDs: invalid)
    }
}
