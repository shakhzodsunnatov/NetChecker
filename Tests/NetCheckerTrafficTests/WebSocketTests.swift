import XCTest
@testable import NetCheckerTrafficCore

final class WebSocketFrameTests: XCTestCase {

    func testTextFrameSizeIsUTF8ByteCount() {
        let frame = WebSocketFrame(direction: .outgoing, kind: .text, text: "привет")
        // Кириллица занимает по два байта
        XCTAssertEqual(frame.size, 12)
    }

    func testBinaryFrameSizeIsByteCount() {
        let frame = WebSocketFrame(direction: .incoming, kind: .binary, data: Data(repeating: 0, count: 64))
        XCTAssertEqual(frame.size, 64)
    }

    func testEmptyFrameHasZeroSize() {
        XCTAssertEqual(WebSocketFrame(direction: .outgoing, kind: .ping).size, 0)
    }

    func testJSONDetectionAcceptsObjectsAndArrays() {
        XCTAssertTrue(WebSocketFrame(direction: .incoming, kind: .text, text: #"{"a":1}"#).isJSON)
        XCTAssertTrue(WebSocketFrame(direction: .incoming, kind: .text, text: "[1,2,3]").isJSON)
    }

    func testJSONDetectionRejectsPlainTextAndBrokenJSON() {
        XCTAssertFalse(WebSocketFrame(direction: .incoming, kind: .text, text: "hello").isJSON)
        XCTAssertFalse(WebSocketFrame(direction: .incoming, kind: .text, text: "{broken").isJSON)
    }

    func testJSONDetectionIgnoresBinaryFrames() {
        let frame = WebSocketFrame(direction: .incoming, kind: .binary, data: Data(#"{"a":1}"#.utf8))
        XCTAssertFalse(frame.isJSON)
    }

    func testPreviewCollapsesNewlines() {
        let frame = WebSocketFrame(direction: .outgoing, kind: .text, text: "line1\nline2")
        XCTAssertEqual(frame.preview, "line1 line2")
    }

    func testPreviewTruncatesLongText() {
        let frame = WebSocketFrame(direction: .outgoing, kind: .text, text: String(repeating: "x", count: 400))
        XCTAssertTrue(frame.preview.hasSuffix("…"))
        XCTAssertLessThan(frame.preview.count, 130)
    }

    func testPreviewDescribesBinaryPayload() {
        let frame = WebSocketFrame(direction: .incoming, kind: .binary, data: Data(repeating: 1, count: 7))
        XCTAssertTrue(frame.preview.contains("7"))
    }

    func testFrameFromStringMessage() {
        let frame = WebSocketFrame.message(.string("hi"), direction: .outgoing)

        XCTAssertEqual(frame.kind, .text)
        XCTAssertEqual(frame.text, "hi")
        XCTAssertEqual(frame.direction, .outgoing)
    }

    func testFrameFromDataMessage() {
        let payload = Data([1, 2, 3])
        let frame = WebSocketFrame.message(.data(payload), direction: .incoming)

        XCTAssertEqual(frame.kind, .binary)
        XCTAssertEqual(frame.data, payload)
    }

    func testFrameFromError() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "разрыв"])
        let frame = WebSocketFrame.failure(error, direction: .incoming)

        XCTAssertEqual(frame.kind, .error)
        XCTAssertEqual(frame.text, "разрыв")
    }
}

final class WebSocketRecordTests: XCTestCase {

    private func record(maxFrames: Int = 500) -> WebSocketRecord {
        WebSocketRecord(url: URL(string: "wss://api.example.com/socket")!, maxFrames: maxFrames)
    }

    func testNewRecordStartsConnecting() {
        XCTAssertEqual(record().state, .connecting)
        XCTAssertTrue(record().state.isActive)
    }

    func testMarkOpen() {
        var connection = record()
        connection.markOpen()

        XCTAssertEqual(connection.state, .open)
        XCTAssertTrue(connection.state.isActive)
    }

    func testMarkClosedRecordsCodeAndStopsBeingActive() {
        var connection = record()
        connection.markClosed(code: 1000, reason: "normal")

        XCTAssertEqual(connection.state, .closed(code: 1000, reason: "normal"))
        XCTAssertFalse(connection.state.isActive)
        XCTAssertNotNil(connection.closedAt)
    }

    func testMarkFailed() {
        var connection = record()
        connection.markFailed("обрыв")

        XCTAssertEqual(connection.state, .failed("обрыв"))
        XCTAssertTrue(connection.hasErrors)
    }

    func testDirectionCountsAreSeparate() {
        var connection = record()
        connection.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "a"))
        connection.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "b"))
        connection.append(WebSocketFrame(direction: .incoming, kind: .text, text: "c"))

        XCTAssertEqual(connection.sentFrameCount, 2)
        XCTAssertEqual(connection.receivedFrameCount, 1)
    }

    func testTotalBytesSumsFrames() {
        var connection = record()
        connection.append(WebSocketFrame(direction: .outgoing, kind: .binary, data: Data(repeating: 0, count: 10)))
        connection.append(WebSocketFrame(direction: .incoming, kind: .binary, data: Data(repeating: 0, count: 5)))

        XCTAssertEqual(connection.totalBytes, 15)
    }

    func testFrameLimitDropsOldestAndCounts() {
        var connection = record(maxFrames: 3)
        for index in 0..<5 {
            connection.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "\(index)"))
        }

        XCTAssertEqual(connection.frames.count, 3)
        XCTAssertEqual(connection.droppedFrameCount, 2)
        XCTAssertEqual(connection.frames.first?.text, "2")
        XCTAssertEqual(connection.frames.last?.text, "4")
    }

    func testMaxFramesIsAtLeastOne() {
        var connection = record(maxFrames: 0)
        connection.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "x"))

        XCTAssertEqual(connection.frames.count, 1)
    }

    func testErrorFrameMakesConnectionErroneous() {
        var connection = record()
        connection.markOpen()
        XCTAssertFalse(connection.hasErrors)

        connection.append(WebSocketFrame(direction: .incoming, kind: .error, text: "boom"))
        XCTAssertTrue(connection.hasErrors)
    }

    func testHostAndPathAreDerivedFromURL() {
        let connection = record()
        XCTAssertEqual(connection.host, "api.example.com")
        XCTAssertEqual(connection.path, "/socket")
    }

    func testPathFallsBackToSlash() {
        let connection = WebSocketRecord(url: URL(string: "wss://api.example.com")!)
        XCTAssertEqual(connection.path, "/")
    }
}

@MainActor
final class WebSocketStoreTests: XCTestCase {

    private var store: WebSocketStore { WebSocketStore.shared }
    private let url = URL(string: "wss://api.example.com/socket")!

    override func setUp() async throws {
        try await super.setUp()
        store.clear()
        store.isRecordingEnabled = true
        store.maxConnections = 50
        store.maxFramesPerConnection = 500
    }

    override func tearDown() async throws {
        store.clear()
        store.maxConnections = 50
        store.maxFramesPerConnection = 500
        store.isRecordingEnabled = true
        try await super.tearDown()
    }

    func testOpenRegistersConnection() {
        let id = store.open(url: url)

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.connection(id: id)?.url, url)
        XCTAssertEqual(store.connection(id: id)?.state, .open)
    }

    func testNewestConnectionComesFirst() {
        _ = store.open(url: URL(string: "wss://a.com/1")!)
        _ = store.open(url: URL(string: "wss://b.com/2")!)

        XCTAssertEqual(store.connections.first?.host, "b.com")
    }

    func testRegisterIsIdempotent() {
        let id = UUID()
        store.register(id: id, url: url)
        store.register(id: id, url: url)

        XCTAssertEqual(store.count, 1)
    }

    func testAppendFrameLandsInConnection() {
        let id = store.open(url: url)
        store.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "ping"), to: id)

        XCTAssertEqual(store.connection(id: id)?.frames.count, 1)
    }

    func testAppendToUnknownConnectionIsIgnored() {
        store.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "x"), to: UUID())
        XCTAssertEqual(store.totalFrameCount, 0)
    }

    func testCloseUpdatesState() {
        let id = store.open(url: url)
        store.close(id: id, code: 1001, reason: "уходим")

        XCTAssertEqual(store.connection(id: id)?.state, .closed(code: 1001, reason: "уходим"))
        XCTAssertEqual(store.activeCount, 0)
    }

    func testFailUpdatesState() {
        let id = store.open(url: url)
        store.fail(id: id, message: "обрыв")

        XCTAssertEqual(store.connection(id: id)?.state, .failed("обрыв"))
    }

    func testActiveCountTracksOpenConnections() {
        _ = store.open(url: url)
        let second = store.open(url: URL(string: "wss://b.com/x")!)
        store.close(id: second, code: 1000, reason: nil)

        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.activeCount, 1)
    }

    func testConnectionLimitEvictsOldest() {
        store.maxConnections = 2
        _ = store.open(url: URL(string: "wss://a.com/1")!)
        _ = store.open(url: URL(string: "wss://b.com/2")!)
        _ = store.open(url: URL(string: "wss://c.com/3")!)

        XCTAssertEqual(store.count, 2)
        XCTAssertFalse(store.connections.contains { $0.host == "a.com" })
    }

    func testFrameLimitIsAppliedToNewConnections() {
        store.maxFramesPerConnection = 2
        let id = store.open(url: url)

        for index in 0..<5 {
            store.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "\(index)"), to: id)
        }

        XCTAssertEqual(store.connection(id: id)?.frames.count, 2)
        XCTAssertEqual(store.connection(id: id)?.droppedFrameCount, 3)
    }

    func testRecordingCanBeDisabled() {
        store.isRecordingEnabled = false
        let id = store.open(url: url)
        store.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "x"), to: id)

        XCTAssertEqual(store.count, 0)
    }

    func testRemoveDropsSingleConnection() {
        let id = store.open(url: url)
        _ = store.open(url: URL(string: "wss://b.com/x")!)
        store.remove(id: id)

        XCTAssertEqual(store.count, 1)
        XCTAssertNil(store.connection(id: id))
    }

    func testClearRemovesEverything() {
        _ = store.open(url: url)
        _ = store.open(url: URL(string: "wss://b.com/x")!)
        store.clear()

        XCTAssertEqual(store.count, 0)
    }

    func testTotalFrameCountSpansConnections() {
        let first = store.open(url: URL(string: "wss://a.com/1")!)
        let second = store.open(url: URL(string: "wss://b.com/2")!)
        store.append(WebSocketFrame(direction: .outgoing, kind: .text, text: "a"), to: first)
        store.append(WebSocketFrame(direction: .incoming, kind: .text, text: "b"), to: second)

        XCTAssertEqual(store.totalFrameCount, 2)
    }
}

@MainActor
final class NetCheckerWebSocketTaskTests: XCTestCase {

    private var store: WebSocketStore { WebSocketStore.shared }

    override func setUp() async throws {
        try await super.setUp()
        store.clear()
        store.isRecordingEnabled = true
    }

    override func tearDown() async throws {
        store.clear()
        try await super.tearDown()
    }

    func testWrapperRegistersConnection() async {
        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "wss://api.example.com/socket")!
        let task = session.netCheckerWebSocketTask(with: url)

        // Регистрация уходит на главный актор — даём ей завершиться
        await Task.yield()

        XCTAssertEqual(store.connection(id: task.recordId)?.url, url)
        task.task.cancel()
    }

    func testWrapperExposesUnderlyingTask() {
        let session = URLSession(configuration: .ephemeral)
        let task = session.netCheckerWebSocketTask(with: URL(string: "wss://a.com/x")!)

        XCTAssertEqual(task.task.originalRequest?.url?.host, "a.com")
        task.task.cancel()
    }

    func testRecordedURLKeepsWebSocketScheme() async {
        let session = URLSession(configuration: .ephemeral)
        // Foundation переписывает wss:// в https:// внутри задачи —
        // в записи схема должна остаться сокетной
        let task = session.netCheckerWebSocketTask(with: URL(string: "wss://api.example.com/socket")!)
        await Task.yield()

        XCTAssertEqual(task.task.originalRequest?.url?.scheme, "https")
        XCTAssertEqual(store.connection(id: task.recordId)?.url.scheme, "wss")
        task.task.cancel()
    }

    func testPlainWebSocketSchemeIsAlsoRestored() async {
        let session = URLSession(configuration: .ephemeral)
        let task = session.netCheckerWebSocketTask(with: URL(string: "ws://api.example.com/socket")!)
        await Task.yield()

        XCTAssertEqual(store.connection(id: task.recordId)?.url.scheme, "ws")
        task.task.cancel()
    }

    func testRecordingCanBeSuppressed() async {
        let session = URLSession(configuration: .ephemeral)
        let raw = session.webSocketTask(with: URL(string: "wss://a.com/x")!)
        let task = NetCheckerWebSocketTask(raw, recording: false)

        await Task.yield()

        XCTAssertNil(store.connection(id: task.recordId))
        raw.cancel()
    }

    func testCancelRecordsCloseFrameAndState() async {
        let session = URLSession(configuration: .ephemeral)
        let task = session.netCheckerWebSocketTask(with: URL(string: "wss://a.com/x")!)
        await Task.yield()

        task.cancel(with: .goingAway, reason: Data("пока".utf8))

        // Закрытие тоже публикуется через главный актор
        for _ in 0..<10 where store.connection(id: task.recordId)?.state.isActive == true {
            await Task.yield()
        }

        let connection = store.connection(id: task.recordId)
        XCTAssertEqual(connection?.state, .closed(code: 1001, reason: "пока"))
        XCTAssertTrue(connection?.frames.contains { $0.kind == .close } ?? false)
    }

    func testRequestHeadersAreCaptured() async {
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: URL(string: "wss://a.com/x")!)
        request.setValue("Bearer t", forHTTPHeaderField: "Authorization")

        let task = session.netCheckerWebSocketTask(with: request)
        await Task.yield()

        XCTAssertEqual(store.connection(id: task.recordId)?.requestHeaders["Authorization"], "Bearer t")
        task.task.cancel()
    }
}
