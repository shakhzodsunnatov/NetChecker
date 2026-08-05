import XCTest
@testable import NetCheckerTrafficCore

@MainActor
final class FlowStoreTests: XCTestCase {

    private var store: FlowStore { FlowStore.shared }

    override func setUp() async throws {
        try await super.setUp()
        store.removeAll()
    }

    override func tearDown() async throws {
        store.removeAll()
        try await super.tearDown()
    }

    private func record(_ path: String) -> TrafficRecord {
        TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com\(path)")!,
                method: .post,
                headers: ["Authorization": "Bearer secret", "Accept": "application/json"]
            )
        )
    }

    // MARK: - Хранение

    func testAddAndLookup() {
        let flow = Flow(name: "Checkout")
        store.add(flow)

        XCTAssertEqual(store.flows.count, 1)
        XCTAssertEqual(store.flow(id: flow.id)?.name, "Checkout")
    }

    func testUpdateReplacesFlow() {
        var flow = Flow(name: "Checkout")
        store.add(flow)

        flow.name = "Renamed"
        store.update(flow)

        XCTAssertEqual(store.flow(id: flow.id)?.name, "Renamed")
        XCTAssertEqual(store.flows.count, 1)
    }

    func testRemove() {
        let flow = Flow(name: "Checkout")
        store.add(flow)
        store.remove(id: flow.id)

        XCTAssertTrue(store.flows.isEmpty)
    }

    // MARK: - Сборка из трафика

    func testBuildingFlowFromRecordsKeepsOrderAndChainsThem() {
        let flow = store.makeFlow(name: "Checkout",
                                  from: [record("/login"), record("/orders"), record("/pay")])

        XCTAssertEqual(flow.steps.count, 3)
        XCTAssertEqual(flow.steps[0].dependsOn, [])
        XCTAssertEqual(flow.steps[1].dependsOn, [flow.steps[0].id])
        XCTAssertEqual(flow.steps[2].dependsOn, [flow.steps[1].id])
        XCTAssertEqual(flow.levels().count, 3)
    }

    func testStepKeepsHeadersAndMethod() {
        let flow = store.makeFlow(name: "f", from: [record("/login")])

        XCTAssertEqual(flow.steps[0].request.headers["Authorization"], "Bearer secret")
        XCTAssertEqual(flow.steps[0].request.method, .post)
    }

    func testEmptySelectionYieldsEmptyFlow() {
        XCTAssertTrue(store.makeFlow(name: "f", from: [TrafficRecord]()).steps.isEmpty)
    }

    // MARK: - Экспорт

    /// Файл со сценарием уходит другому человеку — живой токен уходить не должен
    func testExportStripsSensitiveHeaders() {
        let flow = store.makeFlow(name: "f", from: [record("/login")])
        let text = String(data: FlowExporter.export(flow), encoding: .utf8) ?? ""

        XCTAssertFalse(text.contains("Bearer secret"))
        XCTAssertTrue(text.contains(FlowExporter.redaction))
    }

    func testExportKeepsHarmlessHeaders() throws {
        let flow = store.makeFlow(name: "f", from: [record("/login")])

        // Сравнивать текстом нельзя: JSONEncoder экранирует слэш как \/
        let loaded = try FlowExporter.load(FlowExporter.export(flow))

        XCTAssertEqual(loaded.steps[0].request.headers["Accept"], "application/json")
        XCTAssertEqual(loaded.steps[0].request.headers["Authorization"], FlowExporter.redaction)
    }

    func testExportedFlowLoadsBack() throws {
        let flow = store.makeFlow(name: "Checkout", from: [record("/login"), record("/pay")])
        let loaded = try FlowExporter.load(FlowExporter.export(flow))

        XCTAssertEqual(loaded.name, "Checkout")
        XCTAssertEqual(loaded.steps.count, 2)
        XCTAssertEqual(loaded.steps[1].dependsOn, [loaded.steps[0].id])
    }

    func testLoadingGarbageThrows() {
        XCTAssertThrowsError(try FlowExporter.load(Data("nope".utf8)))
    }
}
