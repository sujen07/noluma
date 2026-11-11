import XCTest
@testable import Noluma

@MainActor
final class StoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("noluma-tests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func sampleApp(prompts: [String] = ["make a counter", "make it pink"]) -> MiniApp {
        MiniApp(name: "Counter", summary: "Counts things", icon: "plus", tint: "pink", author: "Tester", prompts: prompts)
    }

    // MARK: - Library

    func testLibrarySavesReloadsAndDeletes() async throws {
        let library = AppLibrary(root: root.appendingPathComponent("Apps"))
        let app = try library.save(sampleApp(), html: "<html>one</html>")
        XCTAssertEqual(library.html(for: app.id), "<html>one</html>")

        let reloaded = AppLibrary(root: root.appendingPathComponent("Apps"))
        XCTAssertEqual(reloaded.apps.map(\.id), [app.id])
        XCTAssertEqual(reloaded.apps.first?.prompts, ["make a counter", "make it pink"])

        await reloaded.delete(app)
        XCTAssertTrue(reloaded.apps.isEmpty)
        XCTAssertNil(reloaded.html(for: app.id))
    }

    // MARK: - Marketplace

    private func makeMarketplace() -> (MarketplaceStore, AppLibrary) {
        let service = LocalMarketplaceService(root: root.appendingPathComponent("Marketplace"), bundle: .main)
        return (MarketplaceStore(service: service), AppLibrary(root: root.appendingPathComponent("Apps")))
    }

    func testBundledCatalogLoadsAndEveryListingHasCode() async throws {
        let service = LocalMarketplaceService(root: root.appendingPathComponent("Marketplace"), bundle: .main)
        let listings = try await service.listings()
        XCTAssertGreaterThanOrEqual(listings.count, 4)
        for listing in listings {
            let html = try await service.html(for: listing)
            XCTAssertTrue(html.contains("<html"), "\(listing.name) has no code")
            XCTAssertFalse(html.contains("http://") || html.contains("https://"), "\(listing.name) references a URL")
        }
    }

    func testDownloadCreatesAnIndependentLocalCopy() async throws {
        let (store, library) = makeMarketplace()
        await store.refresh()
        let listing = try XCTUnwrap(store.listings.first { $0.prompts != nil })
        let app = try await store.download(listing, into: library)
        XCTAssertEqual(app.origin, .downloaded)
        XCTAssertEqual(app.sourceListingID, listing.id)
        XCTAssertEqual(app.prompts, listing.prompts)
        XCTAssertNotNil(library.html(for: app.id))
        XCTAssertFalse(app.isPublished)
    }

    func testAppsArePrivateUntilPublished() async throws {
        let (store, library) = makeMarketplace()
        let app = try library.save(sampleApp(), html: "<html>mine</html>")
        await store.refresh()
        XCTAssertFalse(store.listings.contains { $0.name == "Counter" }, "an unpublished app must not be listed")

        try await store.publish(app, sharePrompts: false, library: library)
        let published = try XCTUnwrap(library.app(id: app.id))
        let listing = try XCTUnwrap(store.listing(id: published.publishedListingID))
        XCTAssertTrue(listing.isMine)
        XCTAssertNil(listing.prompts, "prompts must stay private unless sharing is turned on")

        try await store.publish(published, sharePrompts: true, library: library)
        XCTAssertEqual(store.listing(id: published.publishedListingID)?.prompts, ["make a counter", "make it pink"])
        XCTAssertEqual(store.listings.filter(\.isMine).count, 1, "republishing must update, not duplicate")

        try await store.unpublish(try XCTUnwrap(library.app(id: app.id)), library: library)
        XCTAssertFalse(store.listings.contains(where: \.isMine))
        XCTAssertNil(library.app(id: app.id)?.publishedListingID)
        XCTAssertNotNil(library.html(for: app.id), "unpublishing must not remove the local app")
    }

    // MARK: - Claude stream handling

    private func accumulate(_ lines: [String]) throws -> (AIResponse, [AIStreamEvent]) {
        var accumulator = StreamAccumulator()
        var events: [AIStreamEvent] = []
        for line in lines {
            events += try accumulator.handle(try JSONValue.parse(line))
        }
        return (accumulator.finish(), events)
    }

    func testStreamBuildsTextThinkingAndToolBlocks() throws {
        let (response, events) = try accumulate([
            #"{"type":"message_start","message":{"id":"msg_1"}}"#,
            #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig123"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":"","citations":null}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello "}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"there"}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"create_app","input":{}}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"name\":\"A\","}}"#,
            #"{"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"html\":\"<p>\\u00e9</p>\"}"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":5}}"#,
        ])
        XCTAssertEqual(response.stopReason, "tool_use")
        XCTAssertEqual(response.blocks.count, 3)
        XCTAssertEqual(response.blocks[0]["signature"]?.stringValue, "sig123")
        XCTAssertEqual(response.blocks[1]["text"]?.stringValue, "Hello there")
        XCTAssertNil(response.blocks[1]["citations"], "null fields are dropped before the block is sent back")
        XCTAssertEqual(response.blocks[2]["input"]?["name"]?.stringValue, "A")
        XCTAssertEqual(response.blocks[2]["input"]?["html"]?.stringValue, "<p>é</p>")
        XCTAssertTrue(response.invalidToolUseIDs.isEmpty)
        XCTAssertTrue(events.contains { if case .toolStarted(let name) = $0 { return name == "create_app" } else { return false } })
    }

    func testTruncatedToolInputIsFlaggedInvalid() throws {
        let (response, _) = try accumulate([
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_9","name":"create_app","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"name\":\"A\",\"html\":\"<p>cut"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
        ])
        XCTAssertEqual(response.invalidToolUseIDs, ["toolu_9"])
        XCTAssertEqual(response.stopReason, "max_tokens")
    }

    func testStreamErrorEventThrows() {
        var accumulator = StreamAccumulator()
        XCTAssertThrowsError(try accumulator.handle(try JSONValue.parse(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)))
    }

    func testRequestCarriesKeyVersionAndNoForcedToolChoice() throws {
        let request = AIRequest(model: "claude-opus-5-5", system: "sys", messages: [ChatMessage.user("hi").apiValue], tools: [AppBuilderPrompt.tool])
        let urlRequest = try ClaudeClient.makeURLRequest(request, apiKey: "test-key")
        XCTAssertEqual(urlRequest.url?.host, "api.anthropic.com")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(urlRequest.httpBody))
        XCTAssertEqual(body["model"]?.stringValue, "claude-opus-5-5")
        XCTAssertEqual(body["stream"], .bool(true))
        XCTAssertEqual(body["max_tokens"]?.intValue, 64_000)
        XCTAssertNil(body["tool_choice"])
        XCTAssertNil(body["temperature"])
        XCTAssertEqual(body["messages"]?.arrayValue?.first?["content"]?.arrayValue?.first?["text"]?.stringValue, "hi")
    }

    // MARK: - Chat flow (scripted client)

    func testChatBuildsInstallsAndUpdatesOneApp() async throws {
        let library = AppLibrary(root: root.appendingPathComponent("Apps"))
        let conversations = ConversationStore(root: root.appendingPathComponent("Conversations"))
        let chat = ChatViewModel(conversations: conversations, library: library, settings: SettingsStore(), clientOverride: MockAIClient())

        chat.send("Make me a tap counter")
        try await waitForIdle(chat)
        XCTAssertNil(chat.errorMessage)
        XCTAssertEqual(library.apps.count, 1)
        let first = try XCTUnwrap(chat.currentApp)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.prompts, ["Make me a tap counter"])
        XCTAssertEqual(first.origin, .created)
        XCTAssertFalse(first.isPublished, "a new app is private")

        chat.send("Make it pink")
        try await waitForIdle(chat)
        XCTAssertEqual(library.apps.count, 1, "a follow-up updates the same app")
        let second = try XCTUnwrap(chat.currentApp)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.version, 2)
        XCTAssertEqual(second.tint, "pink")
        XCTAssertEqual(second.prompts, ["Make me a tap counter", "Make it pink"])

        // The stored history must be valid to send back: every tool_use is answered.
        let messages = try XCTUnwrap(chat.conversation?.messages)
        for (index, message) in messages.enumerated() where !message.toolUses.isEmpty {
            let ids = message.toolUses.compactMap { $0["id"]?.stringValue }
            let answered = messages[index + 1].blocks.compactMap { $0["tool_use_id"]?.stringValue }
            XCTAssertEqual(ids, answered)
        }
        XCTAssertEqual(chat.items.filter { if case .app = $0 { return true } else { return false } }.count, 2)
    }

    private func waitForIdle(_ chat: ChatViewModel) async throws {
        for _ in 0..<300 {
            if !chat.isRunning { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("chat did not finish")
    }
}
