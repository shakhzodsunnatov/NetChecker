import XCTest
@testable import NetCheckerTrafficCore

final class FlowGroupTests: XCTestCase {

    private func step(_ name: String, dependsOn: [UUID] = []) -> FlowStep {
        FlowStep(
            name: name,
            request: RequestData(url: URL(string: "https://a.com/\(name)")!, method: .get),
            dependsOn: dependsOn
        )
    }

    private func levelIndex(of step: FlowStep, in flow: Flow) -> Int? {
        flow.levels().firstIndex { $0.contains { $0.id == step.id } }
    }

    // MARK: - Параллельный блок

    /// Ради этого блок и нужен: класть шаги внутрь, а не убирать связи
    func testAddingStepsToParallelGroupPutsThemOnTheSameLevel() {
        let a = step("a")
        let b = step("b", dependsOn: [])
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Загрузка", kind: .parallel)
        XCTAssertTrue(flow.addStep(a.id, toGroup: group.id))
        XCTAssertTrue(flow.addStep(b.id, toGroup: group.id))

        XCTAssertEqual(levelIndex(of: a, in: flow), levelIndex(of: b, in: flow))
    }

    /// Шаг, который шёл после другого, попав с ним в один блок
    /// перестаёт его ждать
    func testChainedStepBecomesParallelWhenJoiningTheGroup() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Оба сразу")
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)

        XCTAssertEqual(flow.levels().count, 1)
        XCTAssertTrue(flow.step(id: b.id)!.dependsOn.isEmpty)
    }

    /// Следующий шаг обязан ждать весь блок, а не одного участника
    func testSuccessorWaitsForEveryMemberOfParallelGroup() {
        let a = step("a")
        let b = step("b")
        let next = step("next", dependsOn: [a.id])
        var flow = Flow(name: "f", steps: [a, b, next])

        let group = flow.addGroup(name: "Оба")
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)

        let deps = Set(flow.step(id: next.id)!.dependsOn)
        XCTAssertEqual(deps, [a.id, b.id])
    }

    func testGroupKeepsWhatCameBeforeIt() {
        let first = step("first")
        let a = step("a", dependsOn: [first.id])
        let b = step("b", dependsOn: [first.id])
        var flow = Flow(name: "f", steps: [first, a, b])

        let group = flow.addGroup(name: "Оба")
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)

        XCTAssertEqual(flow.step(id: a.id)?.dependsOn, [first.id])
        XCTAssertEqual(flow.step(id: b.id)?.dependsOn, [first.id])
        XCTAssertEqual(levelIndex(of: first, in: flow), 0)
    }

    // MARK: - Очередь

    func testSequenceGroupChainsItsMembersInOrder() {
        let a = step("a")
        let b = step("b")
        let c = step("c")
        var flow = Flow(name: "f", steps: [a, b, c])

        let group = flow.addGroup(name: "Оформление", kind: .sequence)
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)
        flow.addStep(c.id, toGroup: group.id)

        XCTAssertTrue(flow.step(id: a.id)!.dependsOn.isEmpty)
        XCTAssertEqual(flow.step(id: b.id)?.dependsOn, [a.id])
        XCTAssertEqual(flow.step(id: c.id)?.dependsOn, [b.id])
        XCTAssertEqual(flow.levels().count, 3)
    }

    func testSuccessorOfSequenceWaitsOnlyForTheLastMember() {
        let a = step("a")
        let b = step("b")
        let next = step("next", dependsOn: [a.id])
        var flow = Flow(name: "f", steps: [a, b, next])

        let group = flow.addGroup(name: "Очередь", kind: .sequence)
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)

        XCTAssertEqual(flow.step(id: next.id)?.dependsOn, [b.id])
    }

    func testSwitchingKindRewiresExistingMembers() {
        let a = step("a")
        let b = step("b")
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Блок", kind: .parallel)
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)
        XCTAssertEqual(flow.levels().count, 1)

        flow.setKind(.sequence, forGroup: group.id)
        XCTAssertEqual(flow.levels().count, 2)
        XCTAssertEqual(flow.step(id: b.id)?.dependsOn, [a.id])
    }

    func testReorderingSequenceChangesRunOrder() {
        let a = step("a")
        let b = step("b")
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Очередь", kind: .sequence)
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)

        flow.moveStep(b.id, inGroup: group.id, to: 0)

        XCTAssertTrue(flow.step(id: b.id)!.dependsOn.isEmpty)
        XCTAssertEqual(flow.step(id: a.id)?.dependsOn, [b.id])
    }

    // MARK: - Состав

    func testStepBelongsToOnlyOneGroup() {
        let a = step("a")
        var flow = Flow(name: "f", steps: [a])

        let first = flow.addGroup(name: "Первый")
        let second = flow.addGroup(name: "Второй")
        flow.addStep(a.id, toGroup: first.id)
        flow.addStep(a.id, toGroup: second.id)

        XCTAssertEqual(flow.group(id: first.id)?.stepIds, [])
        XCTAssertEqual(flow.group(id: second.id)?.stepIds, [a.id])
        XCTAssertEqual(flow.group(containing: a.id)?.id, second.id)
    }

    /// Бросок, который замкнул бы граф, отклоняется целиком
    func testAddingStepIsRejectedWhenItWouldCreateACycle() {
        var a = step("a")
        var b = step("b")
        a.dependsOn = [b.id]
        b.dependsOn = [a.id]
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Блок")
        XCTAssertFalse(flow.addStep(a.id, toGroup: group.id))
        XCTAssertTrue(flow.group(id: group.id)!.isEmpty)
    }

    func testRemovingStepFromGroupKeepsItInTheFlow() {
        let a = step("a")
        let b = step("b")
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Блок")
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)
        flow.removeStep(a.id, fromGroup: group.id)

        XCTAssertNotNil(flow.step(id: a.id))
        XCTAssertEqual(flow.group(id: group.id)?.stepIds, [b.id])
    }

    func testDeletingStepAlsoDropsItFromItsGroup() {
        let a = step("a")
        var flow = Flow(name: "f", steps: [a])

        let group = flow.addGroup(name: "Блок")
        flow.addStep(a.id, toGroup: group.id)
        flow.removeStep(id: a.id)

        XCTAssertTrue(flow.group(id: group.id)!.isEmpty)
    }

    func testDissolvingGroupKeepsStepsAndTheirOrder() {
        let a = step("a")
        let b = step("b")
        var flow = Flow(name: "f", steps: [a, b])

        let group = flow.addGroup(name: "Очередь", kind: .sequence)
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)
        flow.dissolveGroup(id: group.id)

        XCTAssertTrue(flow.groups.isEmpty)
        XCTAssertEqual(flow.steps.count, 2)
        XCTAssertEqual(flow.step(id: b.id)?.dependsOn, [a.id])
    }

    func testRemovingGroupTakesItsStepsWithIt() {
        let a = step("a")
        let b = step("b")
        let outside = step("outside")
        var flow = Flow(name: "f", steps: [a, b, outside])

        let group = flow.addGroup(name: "Блок")
        flow.addStep(a.id, toGroup: group.id)
        flow.addStep(b.id, toGroup: group.id)
        flow.removeGroup(id: group.id)

        XCTAssertEqual(flow.steps.map(\.id), [outside.id])
        XCTAssertTrue(flow.groups.isEmpty)
    }

    // MARK: - Групповое удаление

    func testRemovingSeveralStepsClearsEveryReference() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let c = step("c", dependsOn: [b.id])
        var flow = Flow(name: "f", steps: [a, b, c])

        flow.removeSteps(ids: [a.id, b.id])

        XCTAssertEqual(flow.steps.map(\.id), [c.id])
        XCTAssertTrue(flow.step(id: c.id)!.dependsOn.isEmpty)
    }

    // MARK: - Копия шага

    func testDuplicateLandsRightAfterTheOriginal() {
        let a = step("a")
        let b = step("b")
        var flow = Flow(name: "f", steps: [a, b])

        let copy = flow.duplicateStep(id: a.id)

        XCTAssertNotNil(copy)
        XCTAssertEqual(flow.steps.map(\.id), [a.id, copy!.id, b.id])
        XCTAssertNotEqual(copy?.id, a.id)
        XCTAssertEqual(copy?.request.url, a.request.url)
    }

    /// Два шага с одинаковым именем значения писали бы в одну ячейку
    func testDuplicateRenamesOutputsToStayUnique() {
        var a = step("a")
        a.outputs = [FlowOutput(name: "token", source: .jsonPath("token"))]
        var flow = Flow(name: "f", steps: [a])

        let copy = flow.duplicateStep(id: a.id)

        XCTAssertEqual(copy?.outputs.map(\.name), ["token2"])
    }

    func testDuplicateJoinsTheSameGroup() {
        let a = step("a")
        var flow = Flow(name: "f", steps: [a])
        let group = flow.addGroup(name: "Блок")
        flow.addStep(a.id, toGroup: group.id)

        let copy = flow.duplicateStep(id: a.id)

        XCTAssertEqual(flow.group(id: group.id)?.stepIds, [a.id, copy!.id])
    }

    // MARK: - Совместимость

    /// Сохранённые сценарии сделаны до появления блоков —
    /// без этого они бы просто исчезли после обновления
    func testFlowSavedBeforeGroupsStillDecodes() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Старый",
          "steps": [],
          "createdAt": 0
        }
        """

        let flow = try JSONDecoder().decode(Flow.self, from: Data(json.utf8))

        XCTAssertEqual(flow.name, "Старый")
        XCTAssertTrue(flow.groups.isEmpty)
    }

    func testGroupsSurviveEncodingRoundTrip() throws {
        let a = step("a")
        var flow = Flow(name: "f", steps: [a])
        let group = flow.addGroup(name: "Блок", kind: .sequence)
        flow.addStep(a.id, toGroup: group.id)

        let data = try JSONEncoder().encode(flow)
        let restored = try JSONDecoder().decode(Flow.self, from: data)

        XCTAssertEqual(restored.groups.first?.name, "Блок")
        XCTAssertEqual(restored.groups.first?.kind, .sequence)
        XCTAssertEqual(restored.groups.first?.stepIds, [a.id])
    }
}
