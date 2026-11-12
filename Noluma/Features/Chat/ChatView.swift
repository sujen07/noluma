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
            .navigationTitle(chat.currentApp?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chats", systemImage: "line.3.horizontal") { showHistory = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { router.showSettings = true }
                    Button("New app", systemImage: "square.and.pencil") {
                        chat.startNewConversation()
                        draft = ""
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                ConversationListView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
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
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 56)
        case .assistant(_, let text):
            Text(markdown(text))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 20)
        case .app(_, let name, let version):
            AppCardView(name: name, version: version)
        }
    }

    @ViewBuilder
    private var liveRow: some View {
        if !chat.liveText.isEmpty {
            Text(markdown(chat.liveText))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 20)
        }
        if chat.isBuilding {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Building your app")
                        .font(.headline)
                    Text(chat.buildProgress > 0 ? "\(chat.buildProgress.formatted()) characters written" : "Getting started…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .card()
        } else if chat.liveText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .symbolEffect(.pulse, options: .repeating)
                Text("Thinking")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    private func errorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
            }
            HStack(spacing: 10) {
                if !settings.canChat {
                    Button("Open Settings") { router.showSettings = true }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                if chat.canRetry && settings.canChat {
                    Button("Try again") { chat.retry() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 20)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What should\nwe build?")
                        .font(.system(size: 40, weight: .bold))
                        .lineSpacing(-2)
                    Text("Describe an app in your own words. It's built in seconds and runs privately on this iPhone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if !settings.canChat {
                    Button {
                        router.showSettings = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key.fill")
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Add your Claude API key")
                                    .font(.subheadline.weight(.semibold))
                                Text("Needed once, stored on this iPhone")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .card(radius: 20)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Try one of these")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(Self.suggestions, id: \.title) { suggestion in
                            Button {
                                draft = suggestion.prompt
                                composerFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    AppIconView(icon: suggestion.icon, tint: suggestion.tint, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .font(.headline)
                                        Text(suggestion.detail)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2, reservesSpace: true)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private struct Suggestion {
        let title: String
        let detail: String
        let icon: String
        let tint: String
        let prompt: String
    }

    private static let suggestions = [
        Suggestion(title: "Workout log", detail: "Sets, reps and weight by day", icon: "dumbbell.fill", tint: "orange",
                   prompt: "A workout log where I add exercises with sets, reps and weight, and can see my history by day."),
        Suggestion(title: "Reading list", detail: "Track books with ratings and notes", icon: "books.vertical.fill", tint: "purple",
                   prompt: "A reading list with books I want to read, am reading and have finished, with a rating and notes for each."),
        Suggestion(title: "Water tracker", detail: "Daily goal and a 7-day chart", icon: "drop.fill", tint: "blue",
                   prompt: "A water tracker with a daily goal, quick buttons to add a glass, and a chart of the last 7 days."),
        Suggestion(title: "Packing list", detail: "Reusable checklist for trips", icon: "suitcase.fill", tint: "green",
                   prompt: "A packing checklist I can reuse for trips, grouped by category, with a button to uncheck everything."),
    ]

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(chat.currentApp == nil ? "Describe an app" : "Ask for a change", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($composerFocused)
                .padding(.leading, 18)
                .padding(.vertical, 13)
            Group {
                if chat.isRunning {
                    Button {
                        chat.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.primary.opacity(0.8), in: Circle())
                    }
                    .accessibilityLabel("Stop")
                } else {
                    let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button {
                        let text = draft
                        draft = ""
                        chat.send(text)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(empty ? AnyShapeStyle(Color(.systemGray3)) : AnyShapeStyle(Color.accentColor.gradient), in: Circle())
                    }
                    .disabled(empty)
                    .accessibilityLabel("Send")
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 7)
            .padding(.bottom, 7)
        }
        .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
        HStack(spacing: 14) {
            AppIconView(icon: app?.icon ?? "app.fill", tint: app?.tint ?? "indigo", size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                Text(app == nil ? "Removed from this iPhone" : "Version \(version) · Saved")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Open") {
                if let app { router.running = app }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(app == nil)
            .opacity(app == nil ? 0.4 : 1)
        }
        .padding(14)
        .card()
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
                                HStack(spacing: 14) {
                                    let app = library.app(id: conversation.appID)
                                    AppIconView(icon: app?.icon ?? "bubble.left.fill", tint: app?.tint ?? "indigo", size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app?.name ?? conversation.title)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(conversation.updatedAt, format: .relative(presentation: .named))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
