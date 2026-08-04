import XCTest
@testable import NetCheckerTrafficCore

final class HARParserTests: XCTestCase {

    private func har(_ entries: String, version: String = "1.2") -> Data {
        Data("""
        {"log":{"version":"\(version)","creator":{"name":"test","version":"1"},"entries":[\(entries)]}}
        """.utf8)
    }

    private let fullEntry = """
    {
      "startedDateTime": "2026-04-11T10:00:00.000Z",
      "time": 250.5,
      "request": {
        "method": "POST",
        "url": "https://api.example.com/v1/users",
        "headers": [{"name": "Authorization", "value": "Bearer t"}],
        "postData": {"mimeType": "application/json", "text": "{\\"a\\":1}"}
      },
      "response": {
        "status": 201,
        "headers": [{"name": "Content-Type", "value": "application/json"}],
        "content": {"size": 9, "mimeType": "application/json", "text": "{\\"id\\":42}"}
      }
    }
    """

    // MARK: - Успешный разбор

    func testParsesRequestFields() throws {
        let records = try HARParser.parse(har(fullEntry))
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.request.method, .post)
        XCTAssertEqual(record.request.url.absoluteString, "https://api.example.com/v1/users")
        XCTAssertEqual(record.request.headers["Authorization"], "Bearer t")
        XCTAssertEqual(record.request.body, Data("{\"a\":1}".utf8))
    }

    func testParsesResponseFields() throws {
        let record = try XCTUnwrap(try HARParser.parse(har(fullEntry)).first)
        let response = try XCTUnwrap(record.response)

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.headers["Content-Type"], "application/json")
        XCTAssertEqual(response.body, Data("{\"id\":42}".utf8))
    }

    func testConvertsTimeFromMillisecondsToSeconds() throws {
        let record = try XCTUnwrap(try HARParser.parse(har(fullEntry)).first)
        XCTAssertEqual(record.duration, 0.2505, accuracy: 0.0001)
    }

    func testMarksImportedRecords() throws {
        let record = try XCTUnwrap(try HARParser.parse(har(fullEntry)).first)
        XCTAssertTrue(record.metadata.tags.contains("imported"))
        XCTAssertTrue(record.metadata.tags.contains("har"))
    }

    func testParsesFractionalAndPlainTimestamps() throws {
        let plain = """
        {"startedDateTime":"2026-04-11T10:00:00Z","time":1,
         "request":{"method":"GET","url":"https://a.com/x"},
         "response":{"status":200}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(plain)).first)

        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(identifier: "UTC")!, from: record.timestamp)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.hour, 10)
    }

    // MARK: - Снисходительность к разным экспортёрам

    func testMinimalEntryIsAccepted() throws {
        let minimal = """
        {"request":{"url":"https://api.example.com/ping"}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(minimal)).first)

        XCTAssertEqual(record.request.method, .get)
        XCTAssertNil(record.response)
    }

    func testEntryWithoutResponseStaysPending() throws {
        let noResponse = """
        {"request":{"method":"GET","url":"https://a.com/x"}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(noResponse)).first)

        if case .pending = record.state {} else {
            XCTFail("Запись без ответа должна остаться в состоянии pending")
        }
    }

    func testZeroStatusIsTreatedAsNoResponse() throws {
        let failed = """
        {"request":{"method":"GET","url":"https://a.com/x"},"response":{"status":0}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(failed)).first)
        XCTAssertNil(record.response)
    }

    func testHTTP2PseudoHeadersAreDropped() throws {
        let pseudo = """
        {"request":{"method":"GET","url":"https://a.com/x",
         "headers":[{"name":":authority","value":"a.com"},{"name":"Accept","value":"*/*"}]},
         "response":{"status":200}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(pseudo)).first)

        XCTAssertNil(record.request.headers[":authority"])
        XCTAssertEqual(record.request.headers["Accept"], "*/*")
    }

    func testHeaderWithoutValueBecomesEmptyString() throws {
        let entry = """
        {"request":{"method":"GET","url":"https://a.com/x","headers":[{"name":"X-Empty"}]},
         "response":{"status":200}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(entry)).first)
        XCTAssertEqual(record.request.headers["X-Empty"], "")
    }

    func testBase64ResponseBodyIsDecoded() throws {
        let encoded = Data("hello".utf8).base64EncodedString()
        let entry = """
        {"request":{"method":"GET","url":"https://a.com/x"},
         "response":{"status":200,"content":{"text":"\(encoded)","encoding":"base64"}}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(entry)).first)

        XCTAssertEqual(record.response?.body, Data("hello".utf8))
    }

    func testInvalidBase64FallsBackToRawText() throws {
        let entry = """
        {"request":{"method":"GET","url":"https://a.com/x"},
         "response":{"status":200,"content":{"text":"не base64!","encoding":"base64"}}}
        """
        let record = try XCTUnwrap(try HARParser.parse(har(entry)).first)

        XCTAssertEqual(record.response?.body, Data("не base64!".utf8))
    }

    func testEntriesWithUnusableURLsAreSkipped() throws {
        let mixed = """
        {"request":{"method":"GET","url":"not a url"}},
        {"request":{"method":"GET","url":"https://a.com/ok"},"response":{"status":200}}
        """
        let records = try HARParser.parse(har(mixed))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.host, "a.com")
    }

    func testAcceptsHAR11() throws {
        XCTAssertNoThrow(try HARParser.parse(har(fullEntry, version: "1.1")))
    }

    // MARK: - Ошибки

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try HARParser.parse(Data("не json".utf8))) { error in
            XCTAssertEqual(error as? HARParseError, .notJSON)
        }
    }

    func testRejectsJSONWithoutLog() {
        XCTAssertThrowsError(try HARParser.parse(Data(#"{"something":true}"#.utf8))) { error in
            XCTAssertEqual(error as? HARParseError, .missingLog)
        }
    }

    func testRejectsUnsupportedVersion() {
        XCTAssertThrowsError(try HARParser.parse(har(fullEntry, version: "2.0"))) { error in
            XCTAssertEqual(error as? HARParseError, .unsupportedVersion("2.0"))
        }
    }

    func testRejectsEmptyEntryList() {
        XCTAssertThrowsError(try HARParser.parse(har(""))) { error in
            XCTAssertEqual(error as? HARParseError, .noEntries)
        }
    }

    func testRejectsFileWhereEveryEntryIsUnusable() {
        let broken = #"{"request":{"url":"garbage"}}"#
        XCTAssertThrowsError(try HARParser.parse(har(broken))) { error in
            XCTAssertEqual(error as? HARParseError, .noEntries)
        }
    }

    // MARK: - Круговой обход

    func testExportedHARCanBeImportedBack() throws {
        let original = TrafficRecord(
            duration: 0.5,
            state: .completed,
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .get,
                headers: ["Accept": "application/json"]
            ),
            response: ResponseData(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"ok":true}"#.utf8)
            )
        )

        let exported = try XCTUnwrap(HARFormatter.format(records: [original]))
        let reimported = try XCTUnwrap(try HARParser.parse(exported).first)

        XCTAssertEqual(reimported.request.url, original.request.url)
        XCTAssertEqual(reimported.request.method, original.request.method)
        XCTAssertEqual(reimported.response?.statusCode, 200)
        XCTAssertEqual(reimported.response?.body, original.response?.body)
        XCTAssertEqual(reimported.duration, original.duration, accuracy: 0.001)
    }
}

@MainActor
final class HARImporterTests: XCTestCase {

    private var wasMockingEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        wasMockingEnabled = MockEngine.shared.isEnabled
        MockEngine.shared.clearRules()
        TrafficStore.shared.clear()
    }

    override func tearDown() async throws {
        MockEngine.shared.clearRules()
        MockEngine.shared.isEnabled = wasMockingEnabled
        TrafficStore.shared.clear()
        try await super.tearDown()
    }

    private func sampleHAR() -> Data {
        Data("""
        {"log":{"version":"1.2","creator":{"name":"t","version":"1"},"entries":[
          {"request":{"method":"GET","url":"https://api.example.com/users/1"},
           "response":{"status":200,"content":{"text":"{\\"id\\":1}"}}},
          {"request":{"method":"GET","url":"https://api.example.com/users/2"},
           "response":{"status":200,"content":{"text":"{\\"id\\":2}"}}},
          {"request":{"method":"POST","url":"https://api.example.com/orders"},
           "response":{"status":201,"content":{"text":"{}"}}}
        ]}}
        """.utf8)
    }

    func testImportAddsRecordsToStore() throws {
        let result = try HARImporter.importRecords(from: sampleHAR())

        XCTAssertEqual(result.importedCount, 3)
        XCTAssertEqual(TrafficStore.shared.count, 3)
        XCTAssertEqual(result.mockRuleCount, 0)
    }

    func testImportDoesNotTouchMockEngine() throws {
        _ = try HARImporter.importRecords(from: sampleHAR())
        XCTAssertTrue(MockEngine.shared.rules.isEmpty)
    }

    func testReplayCreatesMockRules() throws {
        let result = try HARImporter.importAndReplay(from: sampleHAR())

        // /users/1 и /users/2 сворачиваются в один паттерн, /orders — второй
        XCTAssertEqual(result.mockRuleCount, 2)
        XCTAssertTrue(MockEngine.shared.isEnabled)
    }

    func testReplayRulesMatchTheOriginalRequests() throws {
        _ = try HARImporter.importAndReplay(from: sampleHAR())

        let response = MockEngine.shared.match(
            request: URLRequest(url: URL(string: "https://api.example.com/users/1")!)
        )
        XCTAssertEqual(response?.statusCode, 200)
    }

    func testNumericPathSegmentsBecomeWildcards() throws {
        _ = try HARImporter.importAndReplay(from: sampleHAR())

        // Идентификатор, которого не было в HAR, всё равно попадает под правило
        let response = MockEngine.shared.match(
            request: URLRequest(url: URL(string: "https://api.example.com/users/999")!)
        )
        XCTAssertEqual(response?.statusCode, 200)
    }

    func testReplayCanReplaceExistingRules() throws {
        MockEngine.shared.addRule(
            MockRule(matching: MockMatching(urlPattern: "/old"), action: .passthrough)
        )

        _ = try HARImporter.importAndReplay(from: sampleHAR(), replaceExistingRules: true)

        XCTAssertFalse(MockEngine.shared.rules.contains { $0.matching.urlPattern == "/old" })
    }

    func testReplayKeepsExistingRulesByDefault() throws {
        MockEngine.shared.addRule(
            MockRule(matching: MockMatching(urlPattern: "/old"), action: .passthrough)
        )

        _ = try HARImporter.importAndReplay(from: sampleHAR())

        XCTAssertTrue(MockEngine.shared.rules.contains { $0.matching.urlPattern == "/old" })
    }

    func testMockRulesBuilderIgnoresRecordsWithoutResponse() {
        let record = TrafficRecord(
            request: RequestData(url: URL(string: "https://a.com/x")!, method: .get)
        )
        XCTAssertTrue(HARImporter.mockRules(from: [record]).isEmpty)
    }

    func testImportPropagatesParseErrors() {
        XCTAssertThrowsError(try HARImporter.importRecords(from: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? HARParseError, .notJSON)
        }
    }
}
