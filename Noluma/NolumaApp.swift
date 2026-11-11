import SwiftUI
import Observation

/// App-wide navigation state.
@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case chat, library, marketplace
    }

    var tab: Tab = .chat
    /// The mini-app currently open full screen.
    var running: MiniApp?
    var showSettings = false
}

@main
struct NolumaApp: App {
    @State private var router = AppRouter()
    @State private var settings: SettingsStore
    @State private var library: AppLibrary
    @State private var conversations: ConversationStore
    @State private var marketplace = MarketplaceStore()
    @State private var chat: ChatViewModel

    init() {
        let settings = SettingsStore()
        let library = AppLibrary()
        let conversations = ConversationStore()
        _settings = State(initialValue: settings)
        _library = State(initialValue: library)
        _conversations = State(initialValue: conversations)
        _chat = State(initialValue: ChatViewModel(conversations: conversations, library: library, settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(settings)
                .environment(library)
                .environment(conversations)
                .environment(marketplace)
                .environment(chat)
        }
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ChatView()
                .tabItem { Label("Build", systemImage: "sparkles") }
                .tag(AppRouter.Tab.chat)
            LibraryView()
                .tabItem { Label("My Apps", systemImage: "square.grid.2x2.fill") }
                .tag(AppRouter.Tab.library)
            MarketplaceView()
                .tabItem { Label("Marketplace", systemImage: "bag.fill") }
                .tag(AppRouter.Tab.marketplace)
        }
        .fullScreenCover(item: $router.running) { app in
            AppRunnerView(app: app)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
    }
}
