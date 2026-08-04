import XCTest
@testable import NetCheckerTrafficCore

/// Помеченные запросы должны переживать перезапуск приложения.
/// Обычный трафик живёт только в памяти, поэтому раньше экран тега
/// после перезапуска оказывался пустым.
@MainActor
final class TaggedRequestArchiveTests: XCTestCase {

    private var store: TrafficStore { TrafficStore.shared }
    private var archive: TaggedRequestArchive { TaggedRequestArchive.shared }

    override func setUp() async throws {
        try await super.setUp()
        store.clear()
        archive.clear()
        archive.maxRequests = 300
        archive.maxBodySize = 64 * 1024
    }

    override func tearDown() async throws {
        store.clear()
        archive.clear()
        archive.maxRequests = 300
        archive.maxBodySize = 64 * 1024
        try await super.tearDown()
    }

    @discardableResult
    private func addRecord(
        path: String = "/checkout",
        method: HTTPMethod = .post,
        body: Data? = nil
    ) -> TrafficRecord {
        let record = TrafficRecord(
            state: .completed,
            request: RequestData(
                url: URL(string: "https://api.example.com\(path)")!,
                method: method,
                headers: ["Authorization": "Bearer t"],
                body: body
            ),
            response: ResponseData(statusCode: 201)
        )
        store.add(record)
        return record
    }

    func testTaggingArchivesTheRequest() {
        let record = addRecord()
        store.addTag("NewFeatureFlow", to: [record.id])

        XCTAssertEqual(archive.requests(withTag: "NewFeatureFlow").count, 1)
    }

    func testArchivedRequestSurvivesTrafficBeingCleared() {
        let record = addRecord()
        store.addTag("NewFeatureFlow", to: [record.id])

        store.clear()

        // Это и есть сценарий перезапуска: живого трафика нет, помеченное осталось
        let archived = archive.requests(withTag: "NewFeatureFlow")
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(archived.first?.path, "/checkout")
        XCTAssertEqual(archived.first?.host, "api.example.com")
    }

    func testArchiveKeepsEnoughToReplay() {
        let body = Data(#"{"item":1}"#.utf8)
        let record = addRecord(body: body)
        store.addTag("Flow", to: [record.id])

        let archived = archive.request(id: record.id)
        XCTAssertEqual(archived?.method, .post)
        XCTAssertEqual(archived?.headers["Authorization"], "Bearer t")
        XCTAssertEqual(archived?.body, body)
        XCTAssertEqual(archived?.statusCode, 201)

        // Из архива восстанавливается полноценный запрос
        let restored = archived?.requestData
        XCTAssertEqual(restored?.url.absoluteString, "https://api.example.com/checkout")
        XCTAssertEqual(restored?.body, body)
    }

    func testOversizedBodyIsNotArchived() {
        archive.maxBodySize = 100
        let record = addRecord(body: Data(repeating: 0, count: 101))
        store.addTag("Flow", to: [record.id])

        // Запись сохраняется, но без гигантского тела
        XCTAssertNotNil(archive.request(id: record.id))
        XCTAssertNil(archive.request(id: record.id)?.body)
    }

    func testRemovingLastTagDropsTheArchivedRequest() {
        let record = addRecord()
        store.addTag("Flow", to: [record.id])
        store.removeTag("Flow", from: [record.id])

        XCTAssertNil(archive.request(id: record.id))
    }

    func testRemovingOneOfSeveralTagsKeepsTheRequest() {
        let record = addRecord()
        store.addTag("Flow", to: [record.id])
        store.addTag("Payments", to: [record.id])
        store.removeTag("Flow", from: [record.id])

        XCTAssertEqual(archive.request(id: record.id)?.tags, ["Payments"])
    }

    func testRemoveTagClearsItAcrossTheArchive() {
        let first = addRecord(path: "/a")
        let second = addRecord(path: "/b")
        store.addTag("Flow", to: [first.id, second.id])

        archive.removeTag("Flow")

        XCTAssertTrue(archive.requests.isEmpty)
    }

    func testTaggingTwiceDoesNotDuplicateInArchive() {
        let record = addRecord()
        store.addTag("Flow", to: [record.id])
        store.addTag("Payments", to: [record.id])

        XCTAssertEqual(archive.requests.count, 1)
        XCTAssertEqual(archive.request(id: record.id)?.tags.count, 2)
    }

    func testArchiveIsCappedAndDropsOldest() {
        archive.maxRequests = 2

        for index in 0..<4 {
            let record = addRecord(path: "/\(index)")
            store.addTag("Flow", to: [record.id])
        }

        XCTAssertEqual(archive.requests.count, 2)
        // Новые в начале, значит остались последние
        XCTAssertEqual(archive.requests.first?.path, "/3")
    }

    func testUsedTagsComeFromArchive() {
        let record = addRecord()
        store.addTag("Beta", to: [record.id])
        store.addTag("Alpha", to: [record.id])

        XCTAssertEqual(archive.usedTags, ["Alpha", "Beta"])
    }

    func testArchivedRequestSurvivesCodableRoundTrip() throws {
        let record = addRecord(body: Data(#"{"a":1}"#.utf8))
        store.addTag("Flow", to: [record.id])

        let archived = try XCTUnwrap(archive.request(id: record.id))
        let data = try JSONEncoder().encode(archived)
        let decoded = try JSONDecoder().decode(ArchivedRequest.self, from: data)

        XCTAssertEqual(decoded, archived)
    }
}
