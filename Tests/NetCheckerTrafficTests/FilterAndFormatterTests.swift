import XCTest
@testable import NetCheckerTrafficCore

/// Общие фикстуры для фильтров и форматтеров
private enum Fixture {
    static func record(
        url: String = "https://api.example.com/users",
        method: HTTPMethod = .get,
        status: Int? = 200,
        duration: TimeInterval = 0.1,
        requestHeaders: [String: String] = [:],
        requestBody: Data? = nil,
        responseBody: Data? = nil,
        timestamp: Date = Date(),
        failed: Bool = false
    ) -> TrafficRecord {
        let request = RequestData(
            url: URL(string: url)!,
            method: method,
            headers: requestHeaders,
            body: requestBody
        )

        let response = status.map {
            ResponseData(
                statusCode: $0,
                headers: ["Content-Type": "application/json"],
                body: responseBody
            )
        }

        let state: TrafficRecordState
        if failed {
            state = .failed(TrafficError(code: -1009, domain: NSURLErrorDomain, localizedDescription: "offline"))
        } else {
            state = response == nil ? .pending : .completed
        }

        return TrafficRecord(
            timestamp: timestamp,
            duration: duration,
            state: state,
            request: request,
            response: response
        )
    }
}

final class TrafficFilterTests: XCTestCase {

    private lazy var records: [TrafficRecord] = [
        Fixture.record(url: "https://api.example.com/users", method: .get, status: 200),
        Fixture.record(url: "https://api.example.com/users", method: .post, status: 201),
        Fixture.record(url: "https://api.example.com/orders", method: .get, status: 404),
        Fixture.record(url: "https://cdn.example.com/logo.png", method: .get, status: 200),
        Fixture.record(url: "https://api.example.com/slow", method: .get, status: 200, duration: 9),
        Fixture.record(url: "https://api.example.com/down", method: .get, status: nil, failed: true)
    ]

    func testEmptyFilterKeepsEverything() {
        XCTAssertEqual(TrafficFilter().apply(to: records).count, records.count)
    }

    func testFilterByMethod() {
        var filter = TrafficFilter()
        filter.methods = [.post]

        let result = filter.apply(to: records)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.request.method, .post)
    }

    func testFilterByMultipleMethods() {
        var filter = TrafficFilter()
        filter.methods = [.get, .post]

        XCTAssertEqual(filter.apply(to: records).count, records.count)
    }

    func testFilterByHost() {
        var filter = TrafficFilter()
        filter.hosts = ["cdn.example.com"]

        let result = filter.apply(to: records)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.host, "cdn.example.com")
    }

    func testExcludeHosts() {
        var filter = TrafficFilter()
        filter.excludeHosts = ["cdn.example.com"]

        let result = filter.apply(to: records)
        XCTAssertFalse(result.contains { $0.host == "cdn.example.com" })
    }

    func testFilterByStatusCodeRange() {
        var filter = TrafficFilter()
        filter.statusCodeRange = 400...499

        let result = filter.apply(to: records)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.statusCode, 404)
    }

    func testFilterByStatusCategory() {
        var filter = TrafficFilter()
        filter.statusCategories = [.clientError]

        XCTAssertEqual(filter.apply(to: records).count, 1)
    }

    func testFilterOnlyErrors() {
        var filter = TrafficFilter()
        filter.onlyErrors = true

        // 404 и упавший запрос
        XCTAssertEqual(filter.apply(to: records).count, 2)
    }

    func testFilterOnlySlowRequests() {
        var filter = TrafficFilter()
        filter.onlySlowRequests = true
        filter.slowThreshold = 3

        let result = filter.apply(to: records)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.path, "/slow")
    }

    func testFilterOnlyPending() {
        var filter = TrafficFilter()
        filter.onlyPending = true

        // Все записи либо завершены, либо упали — pending нет
        XCTAssertTrue(filter.apply(to: records).isEmpty)
    }

    func testSearchByPath() {
        var filter = TrafficFilter()
        filter.path = "/orders"

        XCTAssertEqual(filter.apply(to: records).count, 1)
    }

    func testFilterByTimeWindow() {
        let old = Fixture.record(url: "https://api.example.com/ancient", timestamp: Date().addingTimeInterval(-7200))
        var filter = TrafficFilter()
        filter.from = Date().addingTimeInterval(-60)

        let result = filter.apply(to: records + [old])
        XCTAssertFalse(result.contains { $0.path == "/ancient" })
    }

    func testCombinedFiltersNarrowTogether() {
        var filter = TrafficFilter()
        filter.methods = [.get]
        filter.hosts = ["api.example.com"]
        filter.statusCodeRange = 200...299

        let result = filter.apply(to: records)
        XCTAssertEqual(result.count, 2) // /users и /slow
        XCTAssertTrue(result.allSatisfy { $0.request.method == .get })
    }

    func testHostPresetFilter() {
        XCTAssertEqual(TrafficFilter.host("cdn.example.com").apply(to: records).count, 1)
    }
}

final class CURLFormatterTests: XCTestCase {

    func testFormatsMethodAndURL() {
        let record = Fixture.record(url: "https://api.example.com/users", method: .post, status: 201)
        let curl = CURLFormatter.format(record: record)

        XCTAssertTrue(curl.hasPrefix("curl"))
        XCTAssertTrue(curl.contains("POST"))
        XCTAssertTrue(curl.contains("https://api.example.com/users"))
    }

    func testIncludesHeaders() {
        let record = Fixture.record(requestHeaders: ["X-Trace": "abc123"])
        let curl = CURLFormatter.format(record: record)

        XCTAssertTrue(curl.contains("X-Trace"))
        XCTAssertTrue(curl.contains("abc123"))
    }

    func testIncludesRequestBody() {
        let record = Fixture.record(
            method: .post,
            requestBody: Data("{\"name\":\"test\"}".utf8)
        )
        let curl = CURLFormatter.format(record: record)

        XCTAssertTrue(curl.contains("name"))
    }

    func testHandlesRecordWithoutHeadersOrBody() {
        let curl = CURLFormatter.format(record: Fixture.record())
        XCTAssertFalse(curl.isEmpty)
        XCTAssertTrue(curl.contains("curl"))
    }
}

final class HARFormatterTests: XCTestCase {

    private func json(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testProducesValidHAREnvelope() throws {
        let data = try XCTUnwrap(HARFormatter.format(records: [Fixture.record()]))
        let root = try json(from: data)
        let log = try XCTUnwrap(root["log"] as? [String: Any])

        XCTAssertEqual(log["version"] as? String, "1.2")
        XCTAssertNotNil(log["creator"])
        XCTAssertNotNil(log["entries"])
    }

    func testEntryCountMatchesRecordCount() throws {
        let records = [
            Fixture.record(url: "https://api.example.com/a"),
            Fixture.record(url: "https://api.example.com/b"),
            Fixture.record(url: "https://api.example.com/c")
        ]
        let data = try XCTUnwrap(HARFormatter.format(records: records))
        let log = try XCTUnwrap(try json(from: data)["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])

        XCTAssertEqual(entries.count, 3)
    }

    func testEntryCarriesRequestAndResponse() throws {
        let record = Fixture.record(url: "https://api.example.com/users", method: .post, status: 201)
        let data = try XCTUnwrap(HARFormatter.format(records: [record]))
        let log = try XCTUnwrap(try json(from: data)["log"] as? [String: Any])
        let entry = try XCTUnwrap((log["entries"] as? [[String: Any]])?.first)

        let request = try XCTUnwrap(entry["request"] as? [String: Any])
        let response = try XCTUnwrap(entry["response"] as? [String: Any])

        XCTAssertEqual(request["method"] as? String, "POST")
        XCTAssertEqual(request["url"] as? String, "https://api.example.com/users")
        XCTAssertEqual(response["status"] as? Int, 201)
    }

    func testEmptyRecordListStillProducesValidHAR() throws {
        let data = try XCTUnwrap(HARFormatter.format(records: []))
        let log = try XCTUnwrap(try json(from: data)["log"] as? [String: Any])
        let entries = try XCTUnwrap(log["entries"] as? [[String: Any]])

        XCTAssertTrue(entries.isEmpty)
    }

    func testSingleRecordConvenienceMatchesArrayForm() throws {
        let record = Fixture.record()
        let single = try XCTUnwrap(HARFormatter.format(record: record))
        let log = try XCTUnwrap(try json(from: single)["log"] as? [String: Any])

        XCTAssertEqual((log["entries"] as? [[String: Any]])?.count, 1)
    }
}
