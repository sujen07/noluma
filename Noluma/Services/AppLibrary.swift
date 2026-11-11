import Foundation
import Observation
import WebKit

/// The mini-apps installed on this device. Each app is a folder holding
/// `manifest.json` and `index.html`.
@MainActor
@Observable
final class AppLibrary {
    private(set) var apps: [MiniApp] = []

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let files = FileManager.default

    init(root: URL = AppPaths.apps) {
        self.root = root
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func app(id: UUID?) -> MiniApp? {
        guard let id else { return nil }
        return apps.first { $0.id == id }
    }

    func html(for id: UUID) -> String? {
        try? String(contentsOf: folder(id).appendingPathComponent("index.html"), encoding: .utf8)
    }

    /// Installs a new app or replaces an existing one's code and manifest.
    @discardableResult
    func save(_ app: MiniApp, html: String) throws -> MiniApp {
        var app = app
        app.updatedAt = Date()
        let folder = folder(app.id)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(html.utf8).write(to: folder.appendingPathComponent("index.html"), options: .atomic)
        try writeManifest(app)
        upsert(app)
        return app
    }

    /// Updates the manifest only.
    func update(_ app: MiniApp) throws {
        try writeManifest(app)
        upsert(app)
    }

    /// Removes the app, its code and everything it stored.
    func delete(_ app: MiniApp) async {
        try? files.removeItem(at: folder(app.id))
        apps.removeAll { $0.id == app.id }
        try? await WKWebsiteDataStore.remove(forIdentifier: app.id)
    }

    // MARK: - Private

    private func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func writeManifest(_ app: MiniApp) throws {
        let data = try Coding.encoder.encode(app)
        try data.write(to: folder(app.id).appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func upsert(_ app: MiniApp) {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
        } else {
            apps.insert(app, at: 0)
        }
    }

    private func load() {
        let folders = (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        apps = folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("manifest.json")) }
            .compactMap { try? Coding.decoder.decode(MiniApp.self, from: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}
