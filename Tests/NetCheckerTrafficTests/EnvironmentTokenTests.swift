import XCTest
@testable import NetCheckerTrafficCore

final class EnvironmentTokenTests: XCTestCase {

    private func environment(headers: [String: String]) -> Environment {
        Environment(
            name: "Staging",
            baseURL: URL(string: "https://staging.example.com")!,
            headers: headers
        )
    }

    func testTokenIsReadFromAuthorizationHeader() {
        XCTAssertEqual(environment(headers: ["Authorization": "Bearer abc"]).token, "Bearer abc")
    }

    func testTokenIsReadFromAlternativeHeaders() {
        XCTAssertEqual(environment(headers: ["X-API-Key": "secret"]).token, "secret")
        XCTAssertEqual(environment(headers: ["x-auth-token": "secret"]).token, "secret")
    }

    func testTokenIsNilWhenNoAuthHeaderPresent() {
        XCTAssertNil(environment(headers: ["Accept": "application/json"]).token)
        XCTAssertFalse(environment(headers: [:]).hasToken)
    }

    func testSettingTokenCreatesAuthorizationHeader() {
        var env = environment(headers: [:])
        env.token = "Bearer new"

        XCTAssertEqual(env.headers["Authorization"], "Bearer new")
        XCTAssertTrue(env.hasToken)
    }

    func testSettingTokenReusesExistingHeaderName() {
        var env = environment(headers: ["X-API-Key": "old"])
        env.token = "new"

        XCTAssertEqual(env.headers["X-API-Key"], "new")
        XCTAssertNil(env.headers["Authorization"])
    }

    func testClearingTokenRemovesTheHeader() {
        var env = environment(headers: ["Authorization": "Bearer abc", "Accept": "json"])
        env.token = nil

        XCTAssertNil(env.headers["Authorization"])
        XCTAssertEqual(env.headers["Accept"], "json")
    }

    func testOtherHeadersSurviveTokenChanges() {
        var env = environment(headers: ["Accept": "json"])
        env.token = "Bearer abc"

        XCTAssertEqual(env.headers["Accept"], "json")
        XCTAssertEqual(env.headers.count, 2)
    }

    // MARK: - Маскирование

    func testMaskKeepsSchemeAndEdges() {
        let env = environment(headers: ["Authorization": "Bearer abcdefghijklmnop"])
        let masked = env.maskedToken

        XCTAssertEqual(masked?.hasPrefix("Bearer "), true)
        XCTAssertEqual(masked?.contains("…"), true)
        XCTAssertEqual(masked?.contains("abcdefghijklmnop"), false)
    }

    func testShortTokenIsFullyMasked() {
        let env = environment(headers: ["Authorization": "short"])
        XCTAssertEqual(env.maskedToken?.contains("short"), false)
    }

    func testMaskIsNilWithoutToken() {
        XCTAssertNil(environment(headers: [:]).maskedToken)
    }

    func testTokenHeaderNameIsReported() {
        XCTAssertEqual(environment(headers: ["X-API-Key": "k"]).tokenHeaderName, "X-API-Key")
    }
}

@MainActor
final class TokenDetectorTests: XCTestCase {

    private func record(url: String, headers: [String: String]) -> TrafficRecord {
        TrafficRecord(
            request: RequestData(url: URL(string: url)!, method: .get, headers: headers)
        )
    }

    func testDetectsAuthorizationHeader() {
        let found = TokenDetector.detect(in: [
            record(url: "https://api.example.com/me", headers: ["Authorization": "Bearer abc"])
        ])

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.value, "Bearer abc")
        XCTAssertEqual(found.first?.host, "api.example.com")
    }

    func testIgnoresOrdinaryHeaders() {
        let found = TokenDetector.detect(in: [
            record(url: "https://api.example.com/me", headers: ["Accept": "application/json"])
        ])

        XCTAssertTrue(found.isEmpty)
    }

    func testCountsRepeatedUse() {
        let found = TokenDetector.detect(in: [
            record(url: "https://api.example.com/a", headers: ["Authorization": "Bearer abc"]),
            record(url: "https://api.example.com/b", headers: ["Authorization": "Bearer abc"])
        ])

        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.occurrences, 2)
    }

    func testDistinctTokensAreReportedSeparately() {
        let found = TokenDetector.detect(in: [
            record(url: "https://api.example.com/a", headers: ["Authorization": "Bearer one"]),
            record(url: "https://api.example.com/b", headers: ["Authorization": "Bearer two"])
        ])

        XCTAssertEqual(found.count, 2)
    }

    func testMostUsedTokenComesFirst() {
        let found = TokenDetector.detect(in: [
            record(url: "https://api.example.com/a", headers: ["Authorization": "rare"]),
            record(url: "https://api.example.com/b", headers: ["Authorization": "common"]),
            record(url: "https://api.example.com/c", headers: ["Authorization": "common"])
        ])

        XCTAssertEqual(found.first?.value, "common")
    }

    func testRedactedValuesAreSkipped() {
        // Подставлять замаскированное значение бессмысленно
        let found = TokenDetector.detect(in: [
            record(url: "https://api.example.com/a", headers: ["Authorization": "***REDACTED***"])
        ])

        XCTAssertTrue(found.isEmpty)
    }

    func testFilteringByHost() {
        let records = [
            record(url: "https://api.example.com/a", headers: ["Authorization": "one"]),
            record(url: "https://cdn.other.com/b", headers: ["Authorization": "two"])
        ]
        TrafficStore.shared.clear()
        records.forEach { TrafficStore.shared.add($0) }

        let found = TokenDetector.detect(forHost: "api.example.com")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.value, "one")

        TrafficStore.shared.clear()
    }
}

@MainActor
final class InspectorFeatureSettingsTests: XCTestCase {

    private var settings: InspectorFeatureSettings { InspectorFeatureSettings.shared }

    override func setUp() async throws {
        try await super.setUp()
        settings.showAll()
    }

    override func tearDown() async throws {
        settings.showAll()
        try await super.tearDown()
    }

    func testAllFeaturesVisibleByDefault() {
        XCTAssertEqual(settings.visible.count, InspectorFeature.allCases.count)
    }

    func testHidingFeatureRemovesItFromVisible() {
        settings.setVisible(false, for: .mocks)

        XCTAssertFalse(settings.isVisible(.mocks))
        XCTAssertFalse(settings.visible.contains(.mocks))
    }

    func testTrafficCannotBeHidden() {
        settings.setVisible(false, for: .traffic)

        XCTAssertTrue(settings.isVisible(.traffic))
    }

    func testShowAllRestoresEverything() {
        settings.setVisible(false, for: .mocks)
        settings.setVisible(false, for: .breakpoints)
        settings.showAll()

        XCTAssertEqual(settings.visible.count, InspectorFeature.allCases.count)
    }

    func testVisibleOrderIsStable() {
        settings.setVisible(false, for: .environments)

        XCTAssertEqual(settings.visible, [.traffic, .mocks, .breakpoints])
    }
}
