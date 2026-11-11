import Foundation

struct MarketplaceListing: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var summary: String
    var icon: String
    var tint: String
    var author: String
    var category: String
    var downloads: Int
    /// The prompts used to build the app, or nil when the author kept them private.
    var prompts: [String]?
    /// Bundled sample listings name their HTML resource here.
    var htmlFile: String?
    var version: Int?
    var publishedAt: Date?

    /// Listings this user published from this device.
    var isMine: Bool { id.hasPrefix(Self.localPrefix) }

    static let localPrefix = "local-"
}
