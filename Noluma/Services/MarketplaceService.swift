import Foundation
import Observation

/// The marketplace backend. The app only talks to this protocol, so the local
/// implementation below can be replaced by a networked one later.
protocol MarketplaceService: Sendable {
    func listings() async throws -> [MarketplaceListing]
    func html(for listing: MarketplaceListing) async throws -> String
    func publish(_ app: MiniApp, html: String, sharePrompts: Bool) async throws -> MarketplaceListing
    func unpublish(listingID: String) async throws
}

enum MarketplaceError: LocalizedError {
    case missingCode

    var errorDescription: String? {
        switch self {
        case .missingCode: "This app's files could not be found."
        }
    }
}

/// A marketplace that lives entirely on this device: the sample catalog that
/// ships with Noluma plus whatever this user has published.
struct LocalMarketplaceService: MarketplaceService {
    var root: URL = AppPaths.marketplace
    var bundle: Bundle = .main

    func listings() async throws -> [MarketplaceListing] {
        (published() + bundled())
    }

    func html(for listing: MarketplaceListing) async throws -> String {
        if listing.isMine {
            let url = folder(listing.id).appendingPathComponent("index.html")
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { throw MarketplaceError.missingCode }
            return html
        }
        guard let file = listing.htmlFile,
              let url = bundle.url(forResource: file, withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else { throw MarketplaceError.missingCode }
        return html
    }

    func publish(_ app: MiniApp, html: String, sharePrompts: Bool) async throws -> MarketplaceListing {
        let id = app.publishedListingID ?? MarketplaceListing.localPrefix + app.id.uuidString
        let listing = MarketplaceListing(
            id: id,
            name: app.name,
            summary: app.summary,
            icon: app.icon,
            tint: app.tint,
            author: app.author,
            category: "Community",
            downloads: 0,
            prompts: sharePrompts ? app.prompts : nil,
            htmlFile: nil,
            version: app.version,
            publishedAt: Date()
        )
        let folder = folder(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(html.utf8).write(to: folder.appendingPathComponent("index.html"), options: .atomic)
        try Coding.encoder.encode(listing).write(to: folder.appendingPathComponent("listing.json"), options: .atomic)
        return listing
    }

    func unpublish(listingID: String) async throws {
        guard listingID.hasPrefix(MarketplaceListing.localPrefix) else { return }
        try? FileManager.default.removeItem(at: folder(listingID))
    }

    // MARK: - Private

    private func folder(_ id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func bundled() -> [MarketplaceListing] {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? Coding.decoder.decode([MarketplaceListing].self, from: data)) ?? []
    }

    private func published() -> [MarketplaceListing] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("listing.json")) }
            .compactMap { try? Coding.decoder.decode(MarketplaceListing.self, from: $0) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }
}

@MainActor
@Observable
final class MarketplaceStore {
    private(set) var listings: [MarketplaceListing] = []
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: any MarketplaceService

    init(service: any MarketplaceService = LocalMarketplaceService()) {
        self.service = service
    }

    func refresh() async {
        isLoading = listings.isEmpty
        defer { isLoading = false }
        do {
            listings = try await service.listings()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Copies a listing into the library as a brand-new app with empty storage.
    @discardableResult
    func download(_ listing: MarketplaceListing, into library: AppLibrary) async throws -> MiniApp {
        let html = try await service.html(for: listing)
        let app = MiniApp(
            name: listing.name,
            summary: listing.summary,
            icon: listing.icon,
            tint: listing.tint,
            author: listing.author,
            version: listing.version ?? 1,
            origin: .downloaded,
            prompts: listing.prompts ?? [],
            sourceListingID: listing.id
        )
        return try library.save(app, html: html)
    }

    func publish(_ app: MiniApp, sharePrompts: Bool, library: AppLibrary) async throws {
        guard let html = library.html(for: app.id) else { throw MarketplaceError.missingCode }
        let listing = try await service.publish(app, html: html, sharePrompts: sharePrompts)
        var app = app
        app.publishedListingID = listing.id
        app.publishedVersion = app.version
        try library.update(app)
        await refresh()
    }

    func unpublish(_ app: MiniApp, library: AppLibrary) async throws {
        guard let listingID = app.publishedListingID else { return }
        try await service.unpublish(listingID: listingID)
        var app = app
        app.publishedListingID = nil
        app.publishedVersion = nil
        try library.update(app)
        await refresh()
    }

    func listing(id: String?) -> MarketplaceListing? {
        guard let id else { return nil }
        return listings.first { $0.id == id }
    }
}
