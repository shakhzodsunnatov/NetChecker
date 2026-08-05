import XCTest
@testable import NetCheckerTrafficCore

final class FlowGraphTests: XCTestCase {

    private func step(_ name: String, dependsOn: [UUID] = []) -> FlowStep {
        FlowStep(
            name: name,
            request: RequestData(url: URL(string: "https://api.example.com/\(name)")!, method: .get),
            dependsOn: dependsOn
        )
    }

    // MARK: - Уровни

    func testStepsWithoutDependenciesShareTheFirstLevel() {
        let a = step("a"), b = step("b")
        let levels = Flow(name: "f", steps: [a, b]).levels()

        XCTAssertEqual(levels.count, 1)
        XCTAssertEqual(levels[0].count, 2)
    }

    func testDependencyCreatesASecondLevel() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let levels = Flow(name: "f", steps: [a, b]).levels()

        XCTAssertEqual(levels.map { $0.map(\.name) }, [["a"], ["b"]])
    }

    /// «Шаг 3 ждёт обоих» — две входящие связи
    func testStepWaitingForTwoLandsAfterBoth() {
        let a = step("a"), b = step("b")
        let c = step("c", dependsOn: [a.id, b.id])
        let levels = Flow(name: "f", steps: [a, b, c]).levels()

        XCTAssertEqual(levels.count, 2)
        XCTAssertEqual(levels[1].map(\.name), ["c"])
    }

    /// «Шаг 3 ждёт только 2, а 1 просто отрабатывает»
    func testTriggerStartsWithTheOthersButNobodyWaitsForIt() {
        let trigger = step("trigger")
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let flow = Flow(name: "f", steps: [trigger, a, b])

        // Оба стартуют на первом уровне
        XCTAssertEqual(Set(flow.levels()[0].map(\.name)), ["trigger", "a"])
        XCTAssertTrue(flow.isFireAndForget(trigger))
        XCTAssertFalse(flow.isFireAndForget(a))
    }

    /// Последний шаг тоже никто не ждёт, но это конец сценария,
    /// а не запрос, отправленный вдогонку
    func testLastStepIsNotMarkedFireAndForget() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let flow = Flow(name: "f", steps: [a, b])

        XCTAssertFalse(flow.isFireAndForget(b))
    }

    func testSingleStepFlowHasNoFireAndForget() {
        let a = step("a")
        XCTAssertFalse(Flow(name: "f", steps: [a]).isFireAndForget(a))
    }

    func testLongChainProducesOneLevelPerStep() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let c = step("c", dependsOn: [b.id])

        XCTAssertEqual(Flow(name: "f", steps: [a, b, c]).levels().count, 3)
    }

    // MARK: - Устойчивость

    func testCycleIsDetectedAndYieldsNoLevels() {
        var a = step("a")
        var b = step("b")
        a.dependsOn = [b.id]
        b.dependsOn = [a.id]
        let flow = Flow(name: "f", steps: [a, b])

        XCTAssertTrue(flow.hasCycle)
        XCTAssertTrue(flow.levels().isEmpty)
    }

    func testAcyclicGraphReportsNoCycle() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        XCTAssertFalse(Flow(name: "f", steps: [a, b]).hasCycle)
    }

    /// Ссылка на удалённый шаг не должна заклинивать весь сценарий
    func testDependencyOnMissingStepIsIgnored() {
        let orphan = step("orphan", dependsOn: [UUID()])
        let flow = Flow(name: "f", steps: [orphan])

        XCTAssertFalse(flow.hasCycle)
        XCTAssertEqual(flow.levels().count, 1)
    }

    func testEmptyFlowHasNoLevels() {
        XCTAssertTrue(Flow(name: "f").levels().isEmpty)
        XCTAssertFalse(Flow(name: "f").hasCycle)
    }

    func testStepLookupById() {
        let a = step("a")
        XCTAssertEqual(Flow(name: "f", steps: [a]).step(id: a.id)?.name, "a")
        XCTAssertNil(Flow(name: "f", steps: [a]).step(id: UUID()))
    }

    func testStepClampsNegativeDelay() {
        let step = FlowStep(
            name: "s",
            request: RequestData(url: URL(string: "https://a.com/x")!, method: .get),
            delay: -5
        )
        XCTAssertEqual(step.delay, 0)
    }
}
