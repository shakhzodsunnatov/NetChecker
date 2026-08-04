import XCTest
@testable import NetCheckerTrafficCore

/// Тесты сопоставления правил — чистые значения, без синглтонов
final class MockMatchingTests: XCTestCase {

    private func request(
        _ urlString: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = method
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body?.data(using: .utf8)
        return request
    }

    func testMatchesEverythingWhenNoCriteriaSet() {
        XCTAssertTrue(MockMatching().matches(request: request("https://api.example.com/users")))
    }

    func testExactPatternMatchesAsSubstring() {
        let matching = MockMatching(urlPattern: "/users")
        XCTAssertTrue(matching.matches(request: request("https://api.example.com/users/1")))
        XCTAssertFalse(matching.matches(request: request("https://api.example.com/posts/1")))
    }

    func testWildcardPatternMatches() {
        let matching = MockMatching(urlPattern: "*/api/users/*")
        XCTAssertTrue(matching.matches(request: request("https://example.com/api/users/42")))
        XCTAssertFalse(matching.matches(request: request("https://example.com/api/posts/42")))
    }

    func testPatternIsCaseInsensitive() {
        let matching = MockMatching(urlPattern: "/USERS")
        XCTAssertTrue(matching.matches(request: request("https://api.example.com/users")))
    }

    func testMethodNarrowsTheMatch() {
        let matching = MockMatching(urlPattern: "/users", method: .post)
        XCTAssertTrue(matching.matches(request: request("https://api.example.com/users", method: "POST")))
        XCTAssertFalse(matching.matches(request: request("https://api.example.com/users", method: "GET")))
    }

    func testHostMustMatchExactly() {
        let matching = MockMatching(host: "api.example.com")
        XCTAssertTrue(matching.matches(request: request("https://api.example.com/x")))
        XCTAssertFalse(matching.matches(request: request("https://cdn.example.com/x")))
    }

    func testRequiredHeadersMustAllBePresent() {
        let matching = MockMatching(headers: ["X-Env": "test", "X-Trace": "on"])

        XCTAssertTrue(matching.matches(request: request(
            "https://api.example.com/x",
            headers: ["X-Env": "test", "X-Trace": "on"]
        )))
        XCTAssertFalse(matching.matches(request: request(
            "https://api.example.com/x",
            headers: ["X-Env": "test"]
        )))
    }

    func testHeaderValueMustMatch() {
        let matching = MockMatching(headers: ["X-Env": "test"])
        XCTAssertFalse(matching.matches(request: request(
            "https://api.example.com/x",
            headers: ["X-Env": "production"]
        )))
    }

    func testBodyContains() {
        let matching = MockMatching(bodyContains: "\"id\":42")

        XCTAssertTrue(matching.matches(request: request(
            "https://api.example.com/x", method: "POST", body: "{\"id\":42}"
        )))
        XCTAssertFalse(matching.matches(request: request(
            "https://api.example.com/x", method: "POST", body: "{\"id\":7}"
        )))
    }

    func testBodyContainsFailsWhenBodyIsMissing() {
        let matching = MockMatching(bodyContains: "anything")
        XCTAssertFalse(matching.matches(request: request("https://api.example.com/x")))
    }

    // MARK: - MockRule

    func testDisabledRuleNeverMatches() {
        let rule = MockRule(
            isEnabled: false,
            matching: MockMatching(urlPattern: "/users"),
            action: .passthrough
        )
        XCTAssertFalse(rule.matches(request: request("https://api.example.com/users")))
    }

    func testRuleStopsMatchingAfterExpiry() {
        let rule = MockRule(
            matching: MockMatching(urlPattern: "/users"),
            action: .passthrough,
            limits: MockLimits(expiresAt: Date().addingTimeInterval(-60))
        )
        XCTAssertFalse(rule.matches(request: request("https://api.example.com/users")))
    }
}

/// Тесты MockEngine — синглтон, состояние чистится до и после каждого теста
@MainActor
final class MockEngineTests: XCTestCase {

    private var engine: MockEngine { MockEngine.shared }
    private var wasEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        wasEnabled = engine.isEnabled
        engine.clearRules()
        engine.isEnabled = true
    }

    override func tearDown() async throws {
        engine.clearRules()
        engine.isEnabled = wasEnabled
        try await super.tearDown()
    }

    private func jsonRule(pattern: String, status: Int, priority: Int = 0) -> MockRule {
        MockRule(
            name: "rule-\(status)",
            priority: priority,
            matching: MockMatching(urlPattern: pattern),
            action: .respond(MockResponse(
                statusCode: status,
                headers: ["Content-Type": "application/json"],
                body: Data("{}".utf8)
            ))
        )
    }

    func testAddedRuleIsStored() {
        engine.addRule(jsonRule(pattern: "/users", status: 200))
        XCTAssertEqual(engine.rules.count, 1)
    }

    func testClearRulesEmptiesTheEngine() {
        engine.addRule(jsonRule(pattern: "/users", status: 200))
        engine.clearRules()
        XCTAssertTrue(engine.rules.isEmpty)
    }

    func testRemoveRuleById() {
        let rule = jsonRule(pattern: "/users", status: 200)
        engine.addRule(rule)
        engine.removeRule(id: rule.id)
        XCTAssertTrue(engine.rules.isEmpty)
    }

    func testRulesAreSortedByPriorityDescending() {
        engine.addRule(jsonRule(pattern: "/a", status: 200, priority: 1))
        engine.addRule(jsonRule(pattern: "/b", status: 201, priority: 99))
        engine.addRule(jsonRule(pattern: "/c", status: 202, priority: 50))

        XCTAssertEqual(engine.rules.map(\.priority), [99, 50, 1])
    }

    func testHighestPriorityRuleWinsForOverlappingPatterns() {
        engine.addRule(jsonRule(pattern: "/users", status: 500, priority: 1))
        engine.addRule(jsonRule(pattern: "/users", status: 200, priority: 100))

        let response = engine.match(request: URLRequest(url: URL(string: "https://api.example.com/users")!))
        XCTAssertEqual(response?.statusCode, 200)
    }

    func testDisabledEngineMatchesNothing() {
        engine.addRule(jsonRule(pattern: "/users", status: 200))
        engine.isEnabled = false

        XCTAssertNil(engine.match(request: URLRequest(url: URL(string: "https://api.example.com/users")!)))
    }

    func testNonMatchingRequestReturnsNoResponse() {
        engine.addRule(jsonRule(pattern: "/users", status: 200))

        XCTAssertNil(engine.match(request: URLRequest(url: URL(string: "https://api.example.com/posts")!)))
    }

    func testSetRuleEnabledTogglesMatching() {
        let rule = jsonRule(pattern: "/users", status: 200)
        engine.addRule(rule)
        engine.setRuleEnabled(id: rule.id, enabled: false)

        XCTAssertNil(engine.match(request: URLRequest(url: URL(string: "https://api.example.com/users")!)))
    }

    func testMatchErrorReturnsConfiguredError() {
        engine.addRule(MockRule(
            matching: MockMatching(urlPattern: "/payments"),
            action: .error(.timeout)
        ))

        let error = engine.matchError(request: URLRequest(url: URL(string: "https://api.example.com/payments")!))
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.domain, NSURLErrorDomain)
    }

    func testMatchErrorIgnoresNonErrorRules() {
        engine.addRule(jsonRule(pattern: "/users", status: 200))

        XCTAssertNil(engine.matchError(request: URLRequest(url: URL(string: "https://api.example.com/users")!)))
    }

    // MARK: - Задержки

    func testMatchDelayReportsConfiguredDelay() {
        engine.addRule(MockRule(
            matching: MockMatching(urlPattern: "/slow"),
            action: .delay(seconds: 2.5)
        ))

        let delay = engine.matchDelay(request: URLRequest(url: URL(string: "https://api.example.com/slow")!))
        XCTAssertEqual(delay, 2.5)
    }

    func testMatchDelayIgnoresNonDelayRules() {
        engine.addRule(jsonRule(pattern: "/users", status: 200))

        XCTAssertNil(engine.matchDelay(request: URLRequest(url: URL(string: "https://api.example.com/users")!)))
    }

    func testMatchDelayIsNilWhenEngineDisabled() {
        engine.addRule(MockRule(
            matching: MockMatching(urlPattern: "/slow"),
            action: .delay(seconds: 2)
        ))
        engine.isEnabled = false

        XCTAssertNil(engine.matchDelay(request: URLRequest(url: URL(string: "https://api.example.com/slow")!)))
    }

    func testMatchDoesNotBlockOnDelayRules() {
        engine.addRule(MockRule(
            matching: MockMatching(urlPattern: "/slow"),
            action: .delay(seconds: 30)
        ))

        // match() раньше вызывал Thread.sleep и вешал поток загрузки URL
        let start = Date()
        _ = engine.match(request: URLRequest(url: URL(string: "https://api.example.com/slow")!))

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    // MARK: - Подмена тела запроса

    func testRequestBodyOverrideSurvivesRuleRoundTrip() throws {
        let override = Data(#"{"intended":true}"#.utf8)
        let rule = MockRule(
            matching: MockMatching(urlPattern: "/users"),
            action: .respond(MockResponse(statusCode: 200, requestBodyOverride: override))
        )

        // Правила персистятся в UserDefaults, поэтому поле должно кодироваться
        let encoded = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(MockRule.self, from: encoded)

        guard case .respond(let response) = decoded.action else {
            return XCTFail("Ожидалось действие .respond")
        }
        XCTAssertEqual(response.requestBodyOverride, override)
    }

    func testRequestBodyOverrideIsNilByDefault() {
        guard case .respond(let response) = jsonRule(pattern: "/x", status: 200).action else {
            return XCTFail("Ожидалось действие .respond")
        }
        XCTAssertNil(response.requestBodyOverride)
    }
}

/// Подмена тела запроса должна доезжать до записи трафика.
/// Раньше поле записывалось в правило и не читалось ничем.
@MainActor
final class MockRequestBodyOverrideTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        TrafficStore.shared.clear()
    }

    override func tearDown() async throws {
        TrafficStore.shared.clear()
        try await super.tearDown()
    }

    func testOverrideReplacesRecordedRequestBody() {
        let original = Data(#"{"original":true}"#.utf8)
        let override = Data(#"{"mocked":true}"#.utf8)

        let record = TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .post,
                body: original
            )
        )
        TrafficStore.shared.add(record)

        // Тот же шаг, что делает NetCheckerURLProtocol при срабатывании мока
        TrafficStore.shared.update(id: record.id) { stored in
            stored.request.body = override
            stored.request.bodySize = Int64(override.count)
            stored.markAsMocked()
        }

        let stored = TrafficStore.shared.record(for: record.id)
        XCTAssertEqual(stored?.request.body, override)
        XCTAssertEqual(stored?.request.bodySize, Int64(override.count))
    }

    func testRecordRequestBodyStaysWhenNoOverride() {
        let original = Data(#"{"original":true}"#.utf8)
        let record = TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .post,
                body: original
            )
        )
        TrafficStore.shared.add(record)

        XCTAssertEqual(TrafficStore.shared.record(for: record.id)?.request.body, original)
    }
}
