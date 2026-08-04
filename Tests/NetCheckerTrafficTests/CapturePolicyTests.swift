import XCTest
@testable import NetCheckerTrafficCore

/// Политика захвата — то, что защищает прод-приложение от SDK.
/// Раньше эти настройки объявлялись, но не применялись нигде.
final class CapturePolicyTests: XCTestCase {

    // MARK: - Лимиты размера тела

    func testBodyWithinLimitsPassesOrdinaryBody() {
        let config = InterceptorConfiguration()
        let body = Data(repeating: 0, count: 1_000)

        XCTAssertEqual(config.bodyWithinLimits(body), body)
    }

    func testOversizedBodyIsDropped() {
        var config = InterceptorConfiguration()
        config.maxBodySizeToCapture = 1_000

        XCTAssertNil(config.bodyWithinLimits(Data(repeating: 0, count: 1_001)))
    }

    func testBodyExactlyAtLimitIsKept() {
        var config = InterceptorConfiguration()
        config.maxBodySizeToCapture = 1_000

        XCTAssertNotNil(config.bodyWithinLimits(Data(repeating: 0, count: 1_000)))
    }

    func testBodyBelowMinimumIsDropped() {
        var config = InterceptorConfiguration()
        config.minBodySizeToCapture = 500

        XCTAssertNil(config.bodyWithinLimits(Data(repeating: 0, count: 499)))
        XCTAssertNotNil(config.bodyWithinLimits(Data(repeating: 0, count: 500)))
    }

    func testEmptyAndNilBodiesAreDropped() {
        let config = InterceptorConfiguration()

        XCTAssertNil(config.bodyWithinLimits(nil))
        XCTAssertNil(config.bodyWithinLimits(Data()))
    }

    // MARK: - Редакция заголовков

    func testSensitiveHeadersAreRedacted() {
        var config = InterceptorConfiguration()
        config.redactHeaders = ["Authorization"]
        config.redactionString = "***"

        let result = config.redacted(headers: [
            "Authorization": "Bearer secret-token",
            "Accept": "application/json"
        ])

        XCTAssertEqual(result["Authorization"], "***")
        XCTAssertEqual(result["Accept"], "application/json")
    }

    func testRedactionIsCaseInsensitive() {
        var config = InterceptorConfiguration()
        config.redactHeaders = ["authorization"]
        config.redactionString = "***"

        XCTAssertEqual(config.redacted(headers: ["AUTHORIZATION": "secret"])["AUTHORIZATION"], "***")
    }

    func testRedactionKeepsHeaderNames() {
        var config = InterceptorConfiguration()
        config.redactHeaders = ["Authorization"]

        let result = config.redacted(headers: ["Authorization": "secret", "X-Trace": "1"])
        XCTAssertEqual(Set(result.keys), ["Authorization", "X-Trace"])
    }

    func testEmptyRedactionListLeavesHeadersAlone() {
        var config = InterceptorConfiguration()
        config.redactHeaders = []

        let headers = ["Authorization": "secret"]
        XCTAssertEqual(config.redacted(headers: headers), headers)
    }

    func testDefaultConfigurationRedactsAuthorization() {
        let config = InterceptorConfiguration()
        let result = config.redacted(headers: ["Authorization": "Bearer t"])

        XCTAssertNotEqual(result["Authorization"], "Bearer t")
    }

    // MARK: - Разрешение по конфигурации сборки

    func testDebugBuildAlwaysAllowsInterception() {
        #if DEBUG
        XCTAssertTrue(InterceptorConfiguration().isAllowedInCurrentBuild)
        #endif
    }

    func testReleaseBuildRequiresExplicitOptIn() {
        #if !DEBUG
        var config = InterceptorConfiguration()
        config.enableInRelease = false
        XCTAssertFalse(config.isAllowedInCurrentBuild)

        config.enableInRelease = true
        XCTAssertTrue(config.isAllowedInCurrentBuild)
        #endif
    }
}

@MainActor
final class TrafficStoreRetentionTests: XCTestCase {

    private var store: TrafficStore { TrafficStore.shared }

    override func setUp() async throws {
        try await super.setUp()
        store.clear()
        store.retentionPeriod = nil
        store.maxRecords = 1000
    }

    override func tearDown() async throws {
        store.clear()
        store.retentionPeriod = nil
        store.maxRecords = 1000
        try await super.tearDown()
    }

    private func record(ageInSeconds: TimeInterval) -> TrafficRecord {
        TrafficRecord(
            timestamp: Date().addingTimeInterval(-ageInSeconds),
            request: RequestData(url: URL(string: "https://api.example.com/x")!, method: .get)
        )
    }

    func testExpiredRecordsArePrunedOnInsert() {
        store.retentionPeriod = 60
        store.add(record(ageInSeconds: 3600))
        store.add(record(ageInSeconds: 0))

        XCTAssertEqual(store.count, 1)
    }

    func testFreshRecordsSurvivePruning() {
        store.retentionPeriod = 3600
        store.add(record(ageInSeconds: 60))
        store.add(record(ageInSeconds: 0))

        XCTAssertEqual(store.count, 2)
    }

    func testNoRetentionPeriodKeepsEverything() {
        store.retentionPeriod = nil
        store.add(record(ageInSeconds: 100_000))
        store.add(record(ageInSeconds: 0))

        XCTAssertEqual(store.count, 2)
    }

    func testLookupStillWorksAfterPruning() {
        store.retentionPeriod = 60
        store.add(record(ageInSeconds: 3600))

        let fresh = record(ageInSeconds: 0)
        store.add(fresh)

        // Индекс пересобирается после удаления — иначе поиск сломался бы
        XCTAssertNotNil(store.record(for: fresh.id))
    }

    func testMaxRecordsStillCapsTheStore() {
        store.maxRecords = 3
        for _ in 0..<10 {
            store.add(record(ageInSeconds: 0))
        }

        XCTAssertEqual(store.count, 3)
    }
}
