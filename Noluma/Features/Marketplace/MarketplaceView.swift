import SwiftUI

struct MarketplaceView: View {
    @Environment(MarketplaceStore.self) private var marketplace

    @State private var search = ""

    private var results: [MarketplaceListing] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return marketplace.listings }
        return marketplace.listings.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
                || $0.author.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if marketplace.isLoading {
                    ProgressView()
                } else if let error = marketplace.errorMessage, marketplace.listings.isEmpty {
                    ContentUnavailableView {
                        Label("Marketplace unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await marketplace.refresh() } }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(results) { listing in
                        NavigationLink(value: listing) {
                            ListingRow(listing: listing)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Marketplace")
            .navigationDestination(for: MarketplaceListing.self) { listing in
                ListingDetailView(listingID: listing.id, fallback: listing)
            }
            .searchable(text: $search, prompt: "Search apps")
            .refreshable { await marketplace.refresh() }
            .task { await marketplace.refresh() }
        }
    }
}

private struct ListingRow: View {
    let listing: MarketplaceListing

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(icon: listing.icon, tint: listing.tint, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name)
                    .font(.body.weight(.semibold))
                Text(listing.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(listing.isMine && listing.author != "You" ? "\(listing.author) (you)" : listing.author, systemImage: "person.fill")
                    if listing.prompts != nil {
                        Label("Prompts", systemImage: "text.bubble.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ListingDetailView: View {
    let listingID: String
    let fallback: MarketplaceListing

    @Environment(MarketplaceStore.self) private var marketplace
    @Environment(AppLibrary.self) private var library
    @Environment(AppRouter.self) private var router

    @State private var isDownloading = false
    @State private var errorMessage: String?

    private var listing: MarketplaceListing { marketplace.listing(id: listingID) ?? fallback }

    /// The copy of this listing in the library, if there is one.
    private var installed: MiniApp? {
        library.apps.first { $0.sourceListingID == listingID || $0.publishedListingID == listingID }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        AppIconView(icon: listing.icon, tint: listing.tint, size: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(listing.name).font(.title2.weight(.bold))
                            Text("by \(listing.author)").font(.subheadline).foregroundStyle(.secondary)
                            action.padding(.top, 4)
                        }
                    }
                    Text(listing.summary)
                    HStack(spacing: 16) {
                        Label(listing.category, systemImage: "tag.fill")
                        if !listing.isMine {
                            Label("\(listing.downloads.formatted()) downloads", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
                .padding(.vertical, 6)
                .listRowSeparator(.hidden)
            }

            Section {
                Label {
                    Text("Runs offline. This app cannot connect to the internet, so anything you enter stays on your iPhone. The author never sees it.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                }
            }

            Section {
                if let prompts = listing.prompts, !prompts.isEmpty {
                    ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(prompt)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Label("The author kept the prompts private.", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Prompts used to build it")
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Download failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var action: some View {
        if let installed {
            Button("Open") { router.running = installed }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        } else if listing.isMine {
            Text("Published by you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Button {
                download()
            } label: {
                if isDownloading {
                    ProgressView()
                } else {
                    Text("Download")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(isDownloading)
        }
    }

    private func download() {
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                try await marketplace.download(listing, into: library)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
