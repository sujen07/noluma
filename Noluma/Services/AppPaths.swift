import Foundation

/// Where Noluma keeps its files. Everything is inside the app's own container.
enum AppPaths {
    static let base: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Noluma", isDirectory: true)
    }()

    static var apps: URL { base.appendingPathComponent("Apps", isDirectory: true) }
    static var conversations: URL { base.appendingPathComponent("Conversations", isDirectory: true) }
    static var marketplace: URL { base.appendingPathComponent("Marketplace", isDirectory: true) }
}

enum Coding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
