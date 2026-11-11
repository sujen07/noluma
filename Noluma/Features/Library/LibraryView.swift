import SwiftUI

struct LibraryView: View {
    @Environment(AppLibrary.self) private var library
    @Environment(AppRouter.self) private var router

    @State private var details: MiniApp?
    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 18)]

    var body: some View {
        NavigationStack {
            Group {
                if library.apps.isEmpty {
                    ContentUnavailableView {
                        Label("No apps yet", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Apps you build or download from the marketplace live here, on this iPhone only.")
                    } actions: {
                        Button("Build an app") { router.tab = .chat }
                            .buttonStyle(.borderedProminent)
                        Button("Browse the marketplace") { router.tab = .marketplace }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(library.apps) { app in
                                Button {
                                    router.running = app
                                } label: {
                                    VStack(spacing: 6) {
                                        AppIconView(icon: app.icon, tint: app.tint, size: 64)
                                            .overlay(alignment: .topTrailing) {
                                                if app.isPublished {
                                                    Image(systemName: "globe")
                                                        .font(.caption2.weight(.bold))
                                                        .padding(4)
                                                        .background(.thinMaterial, in: Circle())
                                                        .offset(x: 6, y: -6)
                                                        .accessibilityLabel("Published")
                                                }
                                            }
                                        Text(app.name)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                            .frame(height: 32, alignment: .top)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Open", systemImage: "play.fill") { router.running = app }
                                    Button("Details", systemImage: "info.circle") { details = app }
                                }
                            }
                        }
                        .padding(20)
                        Text("Press and hold an app for details and sharing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("My Apps")
            .sheet(item: $details) { app in
                AppDetailView(appID: app.id)
            }
        }
    }
}

/// Details, sharing controls and removal for one installed app.
struct AppDetailView: View {
    let appID: UUID

    @Environment(AppLibrary.self) private var library
    @Environment(MarketplaceStore.self) private var marketplace
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var sharePrompts = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            if let app = library.app(id: appID) {
                Form {
                    Section {
                        HStack(spacing: 14) {
                            AppIconView(icon: app.icon, tint: app.tint, size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.name).font(.title3.weight(.semibold))
                                Text(app.summary).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        Button("Open", systemImage: "play.fill") {
                            dismiss()
                            router.running = app
                        }
                    }

                    Section {
                        LabeledContent("Source", value: app.origin == .created ? "Built by you" : "Marketplace · \(app.author)")
                        LabeledContent("Version", value: "\(app.version)")
                        LabeledContent("Updated", value: app.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    } footer: {
                        Label("Runs offline. This app cannot connect to the internet, and its data never leaves this iPhone.", systemImage: "lock.fill")
                    }

                    if app.origin == .created {
                        sharing(app)
                    }

                    if !app.prompts.isEmpty {
                        Section(app.origin == .created ? "Your prompts" : "Prompts from the author") {
                            ForEach(Array(app.prompts.enumerated()), id: \.offset) { _, prompt in
                                Text(prompt).font(.subheadline)
                            }
                        }
                    }

                    Section {
                        Button("Delete app", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Deleting removes the app and everything saved in it from this iPhone.")
                    }
                }
                .navigationTitle("App details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .disabled(isWorking)
                .onAppear {
                    sharePrompts = marketplace.listing(id: app.publishedListingID)?.prompts != nil
                }
                .confirmationDialog("Delete \(app.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete app and its data", role: .destructive) {
                        Task {
                            try? await marketplace.unpublish(app, library: library)
                            await library.delete(app)
                            dismiss()
                        }
                    }
                } message: {
                    Text(app.isPublished ? "It will also be removed from the marketplace. This can't be undone." : "This can't be undone.")
                }
                .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
                    Button("OK") { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
            } else {
                ContentUnavailableView("App removed", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func sharing(_ app: MiniApp) -> some View {
        Section {
            Toggle("Share the prompts I used", isOn: $sharePrompts)
                .onChange(of: sharePrompts) { _, newValue in
                    // Changing the choice on a live listing applies it right away.
                    guard app.isPublished,
                          (marketplace.listing(id: app.publishedListingID)?.prompts != nil) != newValue else { return }
                    run { try await marketplace.publish(app, sharePrompts: newValue, library: library) }
                }
            if app.isPublished {
                if app.hasUnpublishedChanges {
                    Button("Publish version \(app.version)", systemImage: "arrow.up.circle") {
                        run { try await marketplace.publish(app, sharePrompts: sharePrompts, library: library) }
                    }
                }
                Button("Remove from marketplace", systemImage: "xmark.circle", role: .destructive) {
                    run { try await marketplace.unpublish(app, library: library) }
                }
            } else {
                Button("Publish to marketplace", systemImage: "globe") {
                    run { try await marketplace.publish(app, sharePrompts: sharePrompts, library: library) }
                }
            }
        } header: {
            Text("Marketplace")
        } footer: {
            if app.isPublished {
                Text(app.hasUnpublishedChanges
                     ? "Published. The marketplace still has version \(app.publishedVersion ?? 1)."
                     : "Published. Others can download a copy; they never see the data you entered.")
            } else {
                Text("Private. Nobody else can get this app unless you publish it. Publishing shares the app's code, never the data you entered in it.")
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
