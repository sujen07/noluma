import Foundation
import Observation

struct ModelOption: Identifiable, Hashable {
    let id: String
    let name: String
    let note: String

    static let all = [
        ModelOption(id: "claude-opus-5-5", name: "Claude Opus 5.5", note: "Recommended"),
        ModelOption(id: "claude-fable-5-2", name: "Claude Fable 5.2", note: "Most capable, slower and pricier"),
        ModelOption(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", note: "Faster and cheaper"),
        ModelOption(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", note: "Fastest and cheapest"),
    ]
    static let defaultID = "claude-opus-5-5"
}

@MainActor
@Observable
final class SettingsStore {
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }
    private(set) var hasAPIKey: Bool

    /// True when launched with `-mockAI`: the chat uses a scripted reply and no network.
    let usesMockAI = ProcessInfo.processInfo.arguments.contains("-mockAI")

    init() {
        let saved = UserDefaults.standard.string(forKey: "model")
        model = ModelOption.all.contains { $0.id == saved } ? saved! : ModelOption.defaultID
        displayName = UserDefaults.standard.string(forKey: "displayName") ?? ""
        hasAPIKey = KeychainStore.load() != nil
    }

    var authorName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    var canChat: Bool { usesMockAI || hasAPIKey }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasAPIKey = KeychainStore.save(trimmed)
    }

    func removeAPIKey() {
        KeychainStore.delete()
        hasAPIKey = false
    }

    func makeClient() -> (any AIClient)? {
        if usesMockAI { return MockAIClient() }
        guard let key = KeychainStore.load() else { return nil }
        return ClaudeClient(apiKey: key)
    }
}
