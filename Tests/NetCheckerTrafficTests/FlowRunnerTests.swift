import XCTest
@testable import NetCheckerTrafficCore

/// Подставной исполнитель: сеть в тестах не нужна, нужен контроль ответов
private actor StubExecutor: FlowExecuting {
    private var responses: [String: (ResponseData?, FlowRunError?)]
    private(set) var calls: [String] = []

    init(responses: [String: (ResponseData?, FlowRunError?)] = [:]) {
        self.responses = responses
    }

    func execute(_ request: RequestData) async -> (ResponseData?, FlowRunError?) {
        calls.append(request.url.path)
        return responses[request.url.path] ?? (ResponseData(statusCode: 200, body: Data("{}".utf8)), nil)
    }

    func setResponse(_ value: (ResponseData?, FlowRunError?), for path: String) {
        responses[path] = value
    }

    func callCount(for path: String) -> Int {
        calls.filter { $0 == path }.count
    }
}

@MainActor
final class FlowRunnerTests: XCTestCase {

    private func step(
        _ path: String,
        dependsOn: [UUID] = [],
        condition: FlowCondition? = nil,
        outputs: [FlowOutput] = [],
        inputs: [FlowInput] = [],
        expected: Int? = nil
    ) -> FlowStep {
        FlowStep(
            name: path,
            request: RequestData(url: URL(string: "https://api.example.com\(path)")!, method: .get),
            dependsOn: dependsOn,
            condition: condition,
            outputs: outputs,
            inputs: inputs,
            expectedStatusCode: expected
        )
    }

    // MARK: - Прогон

    func testRunsEveryStep() async {
        let a = step("/a"), b = step("/b")
        let runner = FlowRunner(executor: StubExecutor())

        await runner.run(Flow(name: "f", steps: [a, b]))

        XCTAssertEqual(runner.outcomes[a.id]?.state, .succeeded)
        XCTAssertEqual(runner.outcomes[b.id]?.state, .succeeded)
        XCTAssertFalse(runner.isRunning)
    }

    func testValuePassesBetweenSteps() async {
        let first = step("/login", outputs: [FlowOutput(name: "token", source: .jsonPath("token"))])
        let second = step("/me", dependsOn: [first.id],
                          inputs: [FlowInput(name: "token", target: .header("Authorization"))])

        let executor = StubExecutor(responses: [
            "/login": (ResponseData(statusCode: 200, body: Data(#"{"token":"abc"}"#.utf8)), nil)
        ])
        let runner = FlowRunner(executor: executor)

        await runner.run(Flow(name: "f", steps: [first, second]))

        XCTAssertEqual(runner.outcomes[second.id]?.state, .succeeded)
        XCTAssertEqual(runner.context.values["token"], "abc")
    }

    func testFailureStopsDependentsButNotSiblings() async {
        let failing = step("/bad")
        let dependent = step("/after", dependsOn: [failing.id])
        let sibling = step("/independent")

        let executor = StubExecutor(responses: ["/bad": (nil, FlowRunError.transport("offline"))])
        let runner = FlowRunner(executor: executor)

        await runner.run(Flow(name: "f", steps: [failing, dependent, sibling]))

        XCTAssertEqual(runner.outcomes[dependent.id]?.state, .notRun)
        XCTAssertEqual(runner.outcomes[sibling.id]?.state, .succeeded)
        XCTAssertEqual(runner.failedStepId, failing.id)
    }

    func testUnexpectedStatusFailsTheStep() async {
        let checked = step("/x", expected: 200)
        let executor = StubExecutor(responses: [
            "/x": (ResponseData(statusCode: 500, body: Data("{}".utf8)), nil)
        ])
        let runner = FlowRunner(executor: executor)

        await runner.run(Flow(name: "f", steps: [checked]))

        guard case .failed(let message) = runner.outcomes[checked.id]?.state else {
            return XCTFail("Ожидалось падение шага по несовпавшему статусу")
        }
        XCTAssertTrue(message.contains("500"))
    }

    // MARK: - Условия

    func testFalseConditionSkipsAndCascades() async {
        let source = step("/status", outputs: [FlowOutput(name: "paid", source: .jsonPath("paid"))])
        let branch = step("/pay", dependsOn: [source.id],
                          condition: FlowCondition(valueName: "paid", operator: .isTrue))
        let after = step("/receipt", dependsOn: [branch.id])

        let executor = StubExecutor(responses: [
            "/status": (ResponseData(statusCode: 200, body: Data(#"{"paid":false}"#.utf8)), nil)
        ])
        let runner = FlowRunner(executor: executor)

        await runner.run(Flow(name: "f", steps: [source, branch, after]))

        XCTAssertEqual(runner.outcomes[branch.id]?.state, .skipped)
        XCTAssertEqual(runner.outcomes[after.id]?.state, .skipped)
    }

    func testIfElseRunsExactlyOneBranch() async {
        let source = step("/status", outputs: [FlowOutput(name: "paid", source: .jsonPath("paid"))])
        let ifTrue = step("/paid", dependsOn: [source.id],
                          condition: FlowCondition(valueName: "paid", operator: .isTrue))
        let ifFalse = step("/unpaid", dependsOn: [source.id],
                           condition: FlowCondition(valueName: "paid", operator: .isFalse))

        let executor = StubExecutor(responses: [
            "/status": (ResponseData(statusCode: 200, body: Data(#"{"paid":true}"#.utf8)), nil)
        ])
        let runner = FlowRunner(executor: executor)

        await runner.run(Flow(name: "f", steps: [source, ifTrue, ifFalse]))

        XCTAssertEqual(runner.outcomes[ifTrue.id]?.state, .succeeded)
        XCTAssertEqual(runner.outcomes[ifFalse.id]?.state, .skipped)
    }

    func testMissingValueFailsWithNamedValue() async {
        let target = step("/pay", inputs: [FlowInput(name: "orderId", target: .pathPlaceholder("orderId"))])
        let runner = FlowRunner(executor: StubExecutor())

        await runner.run(Flow(name: "f", steps: [target]))

        guard case .failed(let message) = runner.outcomes[target.id]?.state else {
            return XCTFail("Ожидалось падение шага")
        }
        XCTAssertTrue(message.contains("orderId"))
    }

    // MARK: - Восстановление

    func testRetryFromStepKeepsEarlierValuesAndDoesNotRepeatLogin() async {
        let first = step("/login", outputs: [FlowOutput(name: "token", source: .jsonPath("token"))])
        let failing = step("/pay", dependsOn: [first.id],
                           inputs: [FlowInput(name: "token", target: .header("Authorization"))])

        let executor = StubExecutor(responses: [
            "/login": (ResponseData(statusCode: 200, body: Data(#"{"token":"abc"}"#.utf8)), nil),
            "/pay": (nil, FlowRunError.transport("offline"))
        ])
        let runner = FlowRunner(executor: executor)
        let flow = Flow(name: "f", steps: [first, failing])

        await runner.run(flow)
        XCTAssertEqual(runner.failedStepId, failing.id)

        await executor.setResponse((ResponseData(statusCode: 200, body: Data("{}".utf8)), nil), for: "/pay")
        await runner.retry(from: failing.id, in: flow)

        XCTAssertEqual(runner.outcomes[failing.id]?.state, .succeeded)
        XCTAssertNil(runner.failedStepId)

        let loginCalls = await executor.callCount(for: "/login")
        XCTAssertEqual(loginCalls, 1, "Логин не должен выполняться повторно")
    }

    func testSkipContinuesTheRun() async {
        let failing = step("/bad")
        let after = step("/after", dependsOn: [failing.id])

        let executor = StubExecutor(responses: ["/bad": (nil, FlowRunError.transport("offline"))])
        let runner = FlowRunner(executor: executor)
        let flow = Flow(name: "f", steps: [failing, after])

        await runner.run(flow)
        await runner.skip(failing.id, in: flow)

        XCTAssertEqual(runner.outcomes[failing.id]?.state, .skipped)
        XCTAssertEqual(runner.outcomes[after.id]?.state, .skipped)
    }

    // MARK: - Отказ

    func testCyclicFlowIsRefused() async {
        var a = step("/a"), b = step("/b")
        a.dependsOn = [b.id]
        b.dependsOn = [a.id]

        let runner = FlowRunner(executor: StubExecutor())
        await runner.run(Flow(name: "f", steps: [a, b]))

        XCTAssertTrue(runner.outcomes.isEmpty)
        XCTAssertNotNil(runner.refusalReason)
    }

    func testParallelStepsBothExecute() async {
        let a = step("/a"), b = step("/b"), c = step("/c")
        let executor = StubExecutor()
        let runner = FlowRunner(executor: executor)

        await runner.run(Flow(name: "f", steps: [a, b, c]))

        let calls = await executor.calls
        XCTAssertEqual(Set(calls), ["/a", "/b", "/c"])
    }
}
