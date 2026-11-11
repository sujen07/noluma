import Foundation

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    /// Claude API content blocks, kept exactly as sent or received.
    var blocks: [JSONValue]

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, blocks: [.text(text)])
    }

    /// The message in the shape the Messages API expects.
    var apiValue: JSONValue {
        .object(["role": .string(role.rawValue), "content": .array(blocks)])
    }

    /// All text blocks joined together.
    var text: String {
        blocks
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var toolUses: [JSONValue] {
        blocks.filter { $0["type"]?.stringValue == "tool_use" }
    }
}

/// One conversation builds (and keeps refining) at most one app.
struct Conversation: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title = ""
    var messages: [ChatMessage] = []
    var appID: UUID?
    var updatedAt = Date()

    /// The prompts the user typed, in order.
    var userPrompts: [String] {
        messages.filter { $0.role == .user }.map(\.text).filter { !$0.isEmpty }
    }
}
