import SwiftUI

/// The manifest of a mini-app stored on this device. The app's code lives next
/// to it as a single `index.html`.
struct MiniApp: Identifiable, Codable, Hashable, Sendable {
    enum Origin: String, Codable, Sendable {
        case created
        case downloaded
    }

    var id = UUID()
    var name: String
    var summary: String
    var icon: String
    var tint: String
    var author: String
    var version = 1
    var createdAt = Date()
    var updatedAt = Date()
    var origin: Origin = .created
    /// The prompts the user wrote to build this app. Never leaves the device
    /// unless the user publishes the app with prompt sharing turned on.
    var prompts: [String] = []
    /// Set while this app is published to the marketplace.
    var publishedListingID: String?
    var publishedVersion: Int?
    /// Set when this app was downloaded from the marketplace.
    var sourceListingID: String?

    var isPublished: Bool { publishedListingID != nil }
    var hasUnpublishedChanges: Bool { isPublished && publishedVersion != version }
}

enum AppTint {
    static let names = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "mint", "teal"]

    static func color(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": Color(red: 0.98, green: 0.67, blue: 0.04)
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        default: .indigo
        }
    }

    static func normalized(_ name: String?) -> String {
        guard let name, names.contains(name) else { return "indigo" }
        return name
    }
}

enum AppSymbol {
    /// Returns `name` if it is a real SF Symbol, otherwise a safe default.
    static func normalized(_ name: String?) -> String {
        guard let name, UIImage(systemName: name) != nil else { return "app.fill" }
        return name
    }
}
