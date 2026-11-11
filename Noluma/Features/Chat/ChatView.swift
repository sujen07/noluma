import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var chat
    @Environment(SettingsStore.self) private var settings
    @Environment(AppRouter.self) private var router

    @State private var draft = ""
    @State private var showHistory = false
    @FocusState private var composerFocused: Bool

    private let bottomID = "bottom"

    var body: some View {
        NavigationStack {
            Group {
                if chat.items.isEmpty && !chat.isRunning {
                    emptyState
                } else {
                    transcript
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(chat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("History", systemImage: "clock.arrow.circlepath") { showHistory = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("New app", systemImage: "square.and.pencil") {
                        chat.startNewConversation()
                        draft = ""
                    }
                    Button("Settings", systemImage: "gearshape") { router.showSettings = true }
                }
            }
            .sheet(isPresented: $showHistory) { ConversationListView() }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.items) { item in
                        row(for: item)
                    }
                    if chat.isRunning {
                        liveRow
                    }
                    if let notice = chat.notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = chat.errorMessage {
                        errorRow(error)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.items.count) { scrollToBottom(proxy) }
            .onChange(of: chat.liveText) { scrollToBottom(proxy, animated: false) }
            .onChange(of: chat.isBuilding) { scrollToBottom(proxy) }
            .onChange(of: chat.errorMessage) { scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    @ViewBuilder
    private func row(for item: ChatItem) -> some View {
        switch item {
        case .user(_, let text):
            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 48)
        case .assistant(_, let text):
            Text(markdown(text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)
        case .app(_, let name, let version):
            AppCardView(name: name, version: version)
        }
    }

    @ViewBuilder
    private var liveRow: some View {
        if !chat.liveText.isEmpty {
            Text(markdown(chat.liveText))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)
        }
        HStack(spacing: 10) {
            ProgressView()
            if chat.isBuilding {
                Text(chat.buildProgress > 0 ? "Writing your app… \(chat.buildProgress.formatted()) characters" : "Writing your app…")
                    .monospacedDigit()
            } else if chat.liveText.isEmpty {
                Text("Thinking…")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func errorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.multicolor)
            HStack {
                if !settings.canChat {
                    Button("Open Settings") { router.showSettings = true }
                        .buttonStyle(.borderedProminent)
                }
                if chat.canRetry && settings.canChat {
                    Button("Try again") { chat.retry() }
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .padding(.top, 48)
                VStack(spacing: 6) {
                    Text("What do you want to build?")
                        .font(.title2.weight(.bold))
                    Text("Describe a small app and it's built for you. Apps run offline and keep their data on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 10) {
                    ForEach(Self.suggestions, id: \.title) { suggestion in
                        Button {
                            draft = suggestion.prompt
                            composerFocused = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: suggestion.icon)
                                    .frame(width: 28)
                                    .foregroundStyle(.tint)
                                Text(suggestion.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !settings.canChat {
                    Button {
                        router.showSettings = true
                    } label: {
                        Label("Add your Claude API key to get started", systemImage: "key.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private struct Suggestion {
        let title: String
        let icon: String
        let prompt: String
    }

    private static let suggestions = [
        Suggestion(title: "Workout log", icon: "dumbbell.fill",
                   prompt: "A workout log where I add exercises with sets, reps and weight, and can see my history by day."),
        Suggestion(title: "Reading list", icon: "books.vertical.fill",
                   prompt: "A reading list with books I want to read, am reading and have finished, with a rating and notes for each."),
        Suggestion(title: "Water tracker", icon: "drop.fill",
                   prompt: "A water tracker with a daily goal, quick buttons to add a glass, and a chart of the last 7 days."),
        Suggestion(title: "Packing checklist", icon: "suitcase.fill",
                   prompt: "A packing checklist I can reuse for trips, grouped by category, with a button to uncheck everything."),
    ]

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(chat.currentApp == nil ? "Describe an app…" : "Ask for a change…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if chat.isRunning {
                Button {
                    chat.stop()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 34))
                }
                .accessibilityLabel("Stop")
            } else {
                Button {
                    let text = draft
                    draft = ""
                    chat.send(text)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// The card shown in the transcript each time Claude delivers a version of the app.
struct AppCardView: View {
    let name: String
    let version: Int

    @Environment(ChatViewModel.self) private var chat
    @Environment(AppRouter.self) private var router

    var body: some View {
        let app = chat.currentApp
        HStack(spacing: 12) {
            AppIconView(icon: app?.icon ?? "app.fill", tint: app?.tint ?? "indigo", size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text(app == nil ? "Removed from this iPhone" : "Version \(version) · saved to My Apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open") {
                if let app { router.running = app }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(app == nil)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ConversationListView: View {
    @Environment(ChatViewModel.self) private var chat
    @Environment(ConversationStore.self) private var conversations
    @Environment(AppLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if conversations.conversations.isEmpty {
                    ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Each app you build keeps its own chat here."))
                } else {
                    List {
                        ForEach(conversations.conversations) { conversation in
                            Button {
                                chat.open(conversation.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    let app = library.app(id: conversation.appID)
                                    AppIconView(icon: app?.icon ?? "bubble.left.fill", tint: app?.tint ?? "indigo", size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app?.name ?? conversation.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(conversation.updatedAt, format: .relative(presentation: .named))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { conversations.conversations[$0].id }.forEach(chat.delete)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
