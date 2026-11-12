import SwiftUI

struct MarketplaceView: View {
    @Environment(MarketplaceStore.self) private var marketplace

    @State private var search = ""
    @State private var category: String?

    private var categories: [String] {
        var seen: [String] = []
        for listing in marketplace.listings where !seen.contains(listing.category) {
            seen.append(listing.category)
        }
        return seen
    }

    private var isFiltering: Bool {
        category != nil || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var results: [MarketplaceListing] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return marketplace.listings.filter { listing in
            (category == nil || listing.category == category)
                && (query.isEmpty
                    || listing.name.localizedCaseInsensitiveContains(query)
                    || listing.summary.localizedCaseInsensitiveContains(query)
                    || listing.author.localizedCaseInsensitiveContains(query))
        }
    }

    /// The most downloaded app from someone else leads the page.
    private var featured: MarketplaceListing? {
        marketplace.listings.filter { !$0.isMine }.max { $0.downloads < $1.downloads }
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
                } else {
                    content
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Marketplace")
            .navigationDestination(for: MarketplaceListing.self) { listing in
                ListingDetailView(listingID: listing.id, fallback: listing)
            }
            .searchable(text: $search, prompt: "Apps, authors and more")
            .refreshable { await marketplace.refresh() }
            .task { await marketplace.refresh() }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if !isFiltering, let featured {
                    NavigationLink(value: featured) {
                        FeaturedCard(listing: featured)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", selected: category == nil) { category = nil }
                        ForEach(categories, id: \.self) { name in
                            chip(name, selected: category == name) { category = name }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        SectionTitle(isFiltering ? "Results" : "All apps")
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, listing in
                                NavigationLink(value: listing) {
                                    ListingRow(listing: listing)
                                }
                                .buttonStyle(.plain)
                                if index < results.count - 1 {
                                    Divider().padding(.leading, 90)
                                }
                            }
                        }
                        .card()
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
                .background(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The large card at the top of the marketplace.
private struct FeaturedCard: View {
    let listing: MarketplaceListing

    var body: some View {
        let color = AppTint.color(listing.tint)
        VStack(alignment: .leading, spacing: 0) {
            Text("MOST POPULAR")
                .font(.caption.weight(.bold))
                .opacity(0.8)
            Text(listing.name)
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 2)
            Text(listing.summary)
                .font(.callout)
                .opacity(0.9)
                .padding(.top, 6)
                .frame(maxWidth: 260, alignment: .leading)
            Spacer(minLength: 28)
            HStack(spacing: 12) {
                Image(systemName: AppSymbol.normalized(listing.icon))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("by \(listing.author)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(listing.downloads.formatted()) downloads")
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                ListingAction(listing: listing, onColor: true)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                Rectangle().fill(color.gradient)
                LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
                Image(systemName: AppSymbol.normalized(listing.icon))
                    .font(.system(size: 170, weight: .bold))
                    .foregroundStyle(.white.opacity(0.16))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 36, y: -18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: color.opacity(0.3), radius: 18, y: 10)
    }
}

private struct ListingRow: View {
    let listing: MarketplaceListing

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(icon: listing.icon, tint: listing.tint, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(listing.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(listing.isMine ? "Published by you" : listing.author)
                    if listing.prompts != nil {
                        Text("·")
                        Image(systemName: "text.bubble.fill")
                        Text("Prompts")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            }
            Spacer(minLength: 4)
            ListingAction(listing: listing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// The Get / Open button for a listing, wherever it appears.
struct ListingAction: View {
    let listing: MarketplaceListing
    var prominent = false
    var onColor = false

    @Environment(MarketplaceStore.self) private var marketplace
    @Environment(AppLibrary.self) private var library
    @Environment(AppRouter.self) private var router

    @State private var isDownloading = false
    @State private var errorMessage: String?

    /// The copy of this listing in the library, if there is one.
    private var installed: MiniApp? {
        library.apps.first { $0.sourceListingID == listing.id || $0.publishedListingID == listing.id }
    }

    var body: some View {
        Group {
            if let installed {
                Button("Open") { router.running = installed }
            } else if isDownloading {
                ProgressView()
                    .frame(minWidth: 74, minHeight: 32)
            } else {
                Button("Get") { download() }
            }
        }
        .buttonStyle(PillButtonStyle(prominent: prominent, onColor: onColor))
        .alert("Download failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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

struct ListingDetailView: View {
    let listingID: String
    let fallback: MarketplaceListing

    @Environment(MarketplaceStore.self) private var marketplace

    private var listing: MarketplaceListing { marketplace.listing(id: listingID) ?? fallback }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                stats
                Text(listing.summary)
                    .font(.body)
                    .lineSpacing(3)
                privacy
                prompts
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            AppIconView(icon: listing.icon, tint: listing.tint, size: 112)
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                Text(listing.isMine ? "Published by you" : listing.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 10)
                ListingAction(listing: listing, prominent: true)
            }
            .frame(height: 112, alignment: .top)
            Spacer(minLength: 0)
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat("DOWNLOADS", value: listing.isMine ? "New" : listing.downloads.formatted(.number.notation(.compactName)), symbol: nil)
            Divider().frame(height: 36)
            stat("CATEGORY", value: listing.category, symbol: nil)
            Divider().frame(height: 36)
            stat("VERSION", value: "\(listing.version ?? 1)", symbol: nil)
            Divider().frame(height: 36)
            stat("NETWORK", value: "None", symbol: "wifi.slash")
        }
        .padding(.vertical, 14)
        .card(radius: 20)
    }

    private func stat(_ title: String, value: String, symbol: String?) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    Text(value)
                }
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.capitalized): \(value)")
    }

    private var privacy: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Private by design")
                    .font(.headline)
                Text("This app can't connect to the internet. Anything you enter stays on your iPhone, and the author never sees it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 20)
    }

    private var prompts: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("How it was made")
            if let prompts = listing.prompts, !prompts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.accentColor.gradient, in: Circle())
                            Text(prompt)
                                .font(.subheadline)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .card(radius: 18)
                    }
                }
                Text("These are the prompts the author typed to build this app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(.secondary)
                    Text("The author kept the prompts private.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 18)
            }
        }
    }
}
