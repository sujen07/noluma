import Foundation
import Observation

/// Chat history, one JSON file per conversation, on this device only.
@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let files = FileManager.default

    init(root: URL = AppPaths.conversations) {
        self.root = root
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        conversations = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? Coding.decoder.decode(Conversation.self, from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func conversation(_ id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    func save(_ conversation: Conversation) {
        var conversation = conversation
        conversation.updatedAt = Date()
        if let data = try? Coding.encoder.encode(conversation) {
            try? data.write(to: url(conversation.id), options: .atomic)
        }
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
    }

    func delete(_ id: UUID) {
        try? files.removeItem(at: url(id))
        conversations.removeAll { $0.id == id }
    }

    private func url(_ id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).json")
    }
}
