import Foundation
import Observation

/// One row in the chat transcript.
enum ChatItem: Identifiable, Hashable {
    case user(id: String, text: String)
    case assistant(id: String, text: String)
    case app(id: String, name: String, version: Int)

    var id: String {
        switch self {
        case .user(let id, _), .assistant(let id, _), .app(let id, _, _): id
        }
    }
}

/// Drives the active conversation: sends prompts, streams replies and installs
/// the apps Claude builds.
@MainActor
@Observable
final class ChatViewModel {
    private(set) var conversationID: UUID?
    private(set) var isRunning = false
    /// Text of the reply being streamed.
    private(set) var liveText = ""
    /// Set while Claude is writing an app's code.
    private(set) var isBuilding = false
    private(set) var buildProgress = 0
    var errorMessage: String?
    private(set) var notice: String?

    @ObservationIgnored private let conversations: ConversationStore
    @ObservationIgnored private let library: AppLibrary
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Replaces the real client; used by tests.
    @ObservationIgnored private let clientOverride: (any AIClient)?

    init(conversations: ConversationStore, library: AppLibrary, settings: SettingsStore, clientOverride: (any AIClient)? = nil) {
        self.conversations = conversations
        self.library = library
        self.settings = settings
        self.clientOverride = clientOverride
    }

    var conversation: Conversation? { conversations.conversation(conversationID) }

    var title: String {
        if let app = library.app(id: conversation?.appID) { return app.name }
        return "New app"
    }

    var currentApp: MiniApp? { library.app(id: conversation?.appID) }

    /// True when the last turn failed and can be sent again as is.
    var canRetry: Bool {
        !isRunning && errorMessage != nil && conversation?.messages.last?.role == .user
    }

    var items: [ChatItem] {
        guard let conversation else { return [] }
        var items: [ChatItem] = []
        var version = 0
        for message in conversation.messages {
            let text = message.text
            switch message.role {
            case .user:
                if !text.isEmpty { items.append(.user(id: message.id.uuidString, text: text)) }
            case .assistant:
                if !text.isEmpty { items.append(.assistant(id: message.id.uuidString, text: text)) }
                for (index, tool) in message.toolUses.enumerated() {
                    guard let name = tool["input"]?["name"]?.stringValue, !name.isEmpty else { continue }
                    version += 1
                    items.append(.app(id: "\(message.id.uuidString)-\(index)", name: name, version: version))
                }
            }
        }
        return items
    }

    // MARK: - Actions

    func startNewConversation() {
        stop()
        conversationID = nil
        errorMessage = nil
        notice = nil
    }

    func open(_ id: UUID) {
        guard id != conversationID else { return }
        stop()
        conversationID = id
        errorMessage = nil
        notice = nil
    }

    func delete(_ id: UUID) {
        if id == conversationID { startNewConversation() }
        conversations.delete(id)
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        var conversation = self.conversation ?? Conversation()
        if conversation.title.isEmpty { conversation.title = String(text.prefix(60)) }
        conversation.messages.append(.user(text))
        conversations.save(conversation)
        conversationID = conversation.id
        run()
    }

    func retry() {
        guard canRetry else { return }
        run()
    }

    func stop() {
        task?.cancel()
        task = nil
        resetLiveState()
        isRunning = false
    }

    // MARK: - Turn loop

    private func run() {
        guard let id = conversationID else { return }
        guard let client = clientOverride ?? settings.makeClient() else {
            errorMessage = "Add your Claude API key in Settings to start building."
            return
        }
        errorMessage = nil
        notice = nil
        isRunning = true
        task = Task { [weak self] in
            await self?.turnLoop(conversationID: id, client: client)
        }
    }

    private func turnLoop(conversationID id: UUID, client: any AIClient) async {
        defer {
            if conversationID == id {
                resetLiveState()
                isRunning = false
            }
        }
        do {
            // Keep going while Claude is waiting on a tool result.
            while true {
                guard var conversation = conversations.conversation(id) else { return }
                let request = AIRequest(
                    model: settings.model,
                    system: AppBuilderPrompt.system,
                    messages: conversation.messages.map(\.apiValue),
                    tools: [AppBuilderPrompt.tool]
                )
                resetLiveState()
                var response: AIResponse?
                for try await event in client.stream(request) {
                    try Task.checkCancellation()
                    switch event {
                    case .textDelta(let text): liveText += text
                    case .toolStarted: isBuilding = true
                    case .toolProgress(let characters): buildProgress = characters
                    case .completed(let finished): response = finished
                    }
                }
                try Task.checkCancellation()
                guard let response else { throw AIError.incomplete }

                var results: [JSONValue] = []
                if !response.blocks.isEmpty {
                    let message = ChatMessage(role: .assistant, blocks: response.blocks)
                    conversation.messages.append(message)
                    // Every tool call gets an answer, so the history stays valid.
                    for tool in message.toolUses {
                        results.append(install(tool, response: response, conversation: &conversation))
                    }
                    if !results.isEmpty {
                        conversation.messages.append(ChatMessage(role: .user, blocks: results))
                    }
                    conversations.save(conversation)
                }

                switch response.stopReason {
                case "tool_use" where !results.isEmpty:
                    continue
                case "max_tokens":
                    notice = "The reply was cut off because it got too long. Ask Claude to continue or to make the app simpler."
                case "refusal":
                    notice = "Claude declined this request. Try describing the app differently."
                default:
                    break
                }
                return
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if conversationID == id {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Handles one `create_app` call and returns the tool_result block for it.
    private func install(_ tool: JSONValue, response: AIResponse, conversation: inout Conversation) -> JSONValue {
        let toolID = tool["id"]?.stringValue ?? ""
        func result(_ text: String, isError: Bool = false) -> JSONValue {
            var block: [String: JSONValue] = [
                "type": .string("tool_result"),
                "tool_use_id": .string(toolID),
                "content": .string(text),
            ]
            if isError { block["is_error"] = .bool(true) }
            return .object(block)
        }

        guard tool["name"]?.stringValue == AppBuilderPrompt.toolName else {
            return result("Unknown tool. The only tool available is \(AppBuilderPrompt.toolName).", isError: true)
        }
        let input = tool["input"]
        let name = input?["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let html = input?["html"]?.stringValue ?? ""
        guard !response.invalidToolUseIDs.contains(toolID), !name.isEmpty, html.contains("<") else {
            return result("INVALID_JSON: the tool input was incomplete or not valid JSON, so nothing was saved. Call \(AppBuilderPrompt.toolName) again with the complete input.", isError: true)
        }

        var app = library.app(id: conversation.appID)
            ?? MiniApp(name: name, summary: "", icon: "app.fill", tint: "indigo", author: settings.authorName, version: 0)
        app.name = String(name.prefix(40))
        app.summary = input?["summary"]?.stringValue ?? app.summary
        app.icon = AppSymbol.normalized(input?["icon"]?.stringValue)
        app.tint = AppTint.normalized(input?["tint"]?.stringValue)
        app.author = settings.authorName
        app.version += 1
        app.prompts = conversation.userPrompts
        do {
            try library.save(app, html: html)
        } catch {
            return result("The app could not be saved on the device: \(error.localizedDescription)", isError: true)
        }
        conversation.appID = app.id
        return result("Saved version \(app.version) of \"\(app.name)\" to the user's library. A card to open it is now shown in the chat.")
    }

    private func resetLiveState() {
        liveText = ""
        isBuilding = false
        buildProgress = 0
    }
}
