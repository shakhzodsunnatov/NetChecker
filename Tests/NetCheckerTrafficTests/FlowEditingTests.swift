import XCTest
@testable import NetCheckerTrafficCore

final class FlowEditingTests: XCTestCase {

    private func step(_ name: String, dependsOn: [UUID] = [], outputs: [FlowOutput] = []) -> FlowStep {
        FlowStep(
            name: name,
            request: RequestData(url: URL(string: "https://api.example.com/\(name)")!, method: .get),
            dependsOn: dependsOn,
            outputs: outputs
        )
    }

    // MARK: - Доступные значения

    func testValuesFromEarlierStepsAreAvailable() {
        let login = step("login", outputs: [FlowOutput(name: "token", source: .jsonPath("token"))])
        let order = step("order", dependsOn: [login.id],
                         outputs: [FlowOutput(name: "orderId", source: .jsonPath("id"))])
        let pay = step("pay", dependsOn: [order.id])
        let flow = Flow(name: "f", steps: [login, order, pay])

        XCTAssertEqual(flow.availableValueNames(before: pay.id), ["orderId", "token"])
    }

    func testStepOnTheFirstLevelHasNothingAvailable() {
        let login = step("login", outputs: [FlowOutput(name: "token", source: .jsonPath("token"))])
        let flow = Flow(name: "f", steps: [login])

        XCTAssertTrue(flow.availableValueNames(before: login.id).isEmpty)
    }

    /// Значение соседа по уровню недоступно: они идут одновременно,
    /// и полагаться на порядок внутри уровня нельзя
    func testValueFromAParallelStepIsNotAvailable() {
        let a = step("a", outputs: [FlowOutput(name: "fromA", source: .jsonPath("x"))])
        let b = step("b")
        let flow = Flow(name: "f", steps: [a, b])

        XCTAssertTrue(flow.availableValueNames(before: b.id).isEmpty)
    }

    func testValuesAreDeduplicated() {
        let a = step("a", outputs: [FlowOutput(name: "token", source: .jsonPath("token"))])
        let b = step("b", outputs: [FlowOutput(name: "token", source: .jsonPath("other"))])
        let c = step("c", dependsOn: [a.id, b.id])
        let flow = Flow(name: "f", steps: [a, b, c])

        XCTAssertEqual(flow.availableValueNames(before: c.id), ["token"])
    }

    // MARK: - Кандидаты в зависимости

    func testEarlierStepsCanBeDependencies() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let c = step("c", dependsOn: [b.id])
        let flow = Flow(name: "f", steps: [a, b, c])

        XCTAssertEqual(Set(flow.possibleDependencies(for: c.id).map(\.name)), ["a", "b"])
    }

    /// Зависеть от себя нельзя
    func testStepIsNotItsOwnDependency() {
        let a = step("a")
        let flow = Flow(name: "f", steps: [a])

        XCTAssertFalse(flow.possibleDependencies(for: a.id).contains { $0.id == a.id })
    }

    /// Кандидат, который сам зависит от этого шага, создал бы цикл
    func testDependentsAreExcludedToPreventCycles() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let flow = Flow(name: "f", steps: [a, b])

        XCTAssertFalse(flow.possibleDependencies(for: a.id).contains { $0.id == b.id })
    }

    func testIndirectDependentsAreAlsoExcluded() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let c = step("c", dependsOn: [b.id])
        let flow = Flow(name: "f", steps: [a, b, c])

        // c зависит от a через b — иначе получился бы цикл
        XCTAssertFalse(flow.possibleDependencies(for: a.id).contains { $0.id == c.id })
    }

    func testUnrelatedStepIsAValidDependency() {
        let a = step("a"), b = step("b")
        let flow = Flow(name: "f", steps: [a, b])

        XCTAssertTrue(flow.possibleDependencies(for: b.id).contains { $0.id == a.id })
    }

    // MARK: - Обновление шага

    func testUpdatingStepReplacesItInPlace() {
        var flow = Flow(name: "f", steps: [step("a"), step("b")])
        var updated = flow.steps[1]
        updated.expectedStatusCode = 201

        flow.update(updated)

        XCTAssertEqual(flow.steps[1].expectedStatusCode, 201)
        XCTAssertEqual(flow.steps.count, 2)
    }

    func testRemovingStepAlsoClearsDependenciesOnIt() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        var flow = Flow(name: "f", steps: [a, b])

        flow.removeStep(id: a.id)

        XCTAssertEqual(flow.steps.count, 1)
        XCTAssertTrue(flow.steps[0].dependsOn.isEmpty, "Висячая зависимость осталась бы после удаления")
    }
}
