import XCTest
@testable import NetCheckerTrafficCore

final class FlowRunContextTests: XCTestCase {

    private func step(inputs: [FlowInput] = [], outputs: [FlowOutput] = []) -> FlowStep {
        FlowStep(
            name: "s",
            request: RequestData(url: URL(string: "https://a.com/orders/%7BorderId%7D")!, method: .get),
            outputs: outputs,
            inputs: inputs
        )
    }

    func testRecordingOutputsMakesValuesAvailable() {
        var context = FlowRunContext()
        let source = step(outputs: [FlowOutput(name: "orderId", source: .jsonPath("id"))])

        context.record(ResponseData(statusCode: 200, body: Data(#"{"id":7781}"#.utf8)), for: source)

        XCTAssertEqual(context.values["orderId"], "7781")
    }

    func testPreparedRequestSubstitutesValues() throws {
        var context = FlowRunContext()
        context.record(ResponseData(statusCode: 200, body: Data(#"{"id":7781}"#.utf8)),
                       for: step(outputs: [FlowOutput(name: "orderId", source: .jsonPath("id"))]))

        let target = step(inputs: [FlowInput(name: "orderId", target: .pathPlaceholder("orderId"))])
        let request = try context.prepared(target)

        XCTAssertEqual(request.url.absoluteString, "https://a.com/orders/7781")
    }

    /// Уходить в сеть с пустой подстановкой нельзя — падаем с именем значения
    func testMissingValueThrowsInsteadOfSendingBlank() {
        let context = FlowRunContext()
        let target = step(inputs: [FlowInput(name: "orderId", target: .pathPlaceholder("orderId"))])

        XCTAssertThrowsError(try context.prepared(target)) { error in
            XCTAssertEqual(error as? FlowRunError, .missingValue("orderId"))
            XCTAssertTrue((error as? FlowRunError)?.message.contains("orderId") ?? false)
        }
    }

    func testMissingOutputInResponseIsReportedAsUnresolved() {
        var context = FlowRunContext()
        let source = step(outputs: [FlowOutput(name: "orderId", source: .jsonPath("nope"))])

        context.record(ResponseData(statusCode: 200, body: Data("{}".utf8)), for: source)

        XCTAssertNil(context.values["orderId"])
        XCTAssertEqual(context.unresolvedOutputs, ["orderId"])
    }

    /// Контекст переживает падение шага — ради этого он и существует
    func testContextAccumulatesAcrossSteps() {
        var context = FlowRunContext()
        context.record(ResponseData(statusCode: 200, body: Data(#"{"token":"abc"}"#.utf8)),
                       for: step(outputs: [FlowOutput(name: "token", source: .jsonPath("token"))]))
        context.record(ResponseData(statusCode: 201, body: Data(#"{"id":1}"#.utf8)),
                       for: step(outputs: [FlowOutput(name: "orderId", source: .jsonPath("id"))]))

        XCTAssertEqual(context.values.count, 2)
        XCTAssertEqual(context.values["token"], "abc")
        XCTAssertEqual(context.values["orderId"], "1")
    }

    func testSubstitutionsDescribeWhatWillBeSent() {
        var context = FlowRunContext()
        context.record(ResponseData(statusCode: 200, body: Data(#"{"id":7781}"#.utf8)),
                       for: step(outputs: [FlowOutput(name: "orderId", source: .jsonPath("id"))]))

        let target = step(inputs: [
            FlowInput(name: "orderId", target: .pathPlaceholder("orderId")),
            FlowInput(name: "missing", target: .header("X-Missing"))
        ])

        let substitutions = context.substitutions(for: target)
        XCTAssertEqual(substitutions["orderId"], "7781")
        XCTAssertEqual(substitutions["missing"], "—")
    }

    func testResetClearsEverything() {
        var context = FlowRunContext()
        context.record(ResponseData(statusCode: 200, body: Data(#"{"id":1}"#.utf8)),
                       for: step(outputs: [FlowOutput(name: "orderId", source: .jsonPath("id"))]))
        context.reset()

        XCTAssertTrue(context.values.isEmpty)
        XCTAssertTrue(context.unresolvedOutputs.isEmpty)
    }

    func testUnresolvedOutputIsNotRecordedTwice() {
        var context = FlowRunContext()
        let source = step(outputs: [FlowOutput(name: "x", source: .jsonPath("nope"))])

        context.record(ResponseData(statusCode: 200, body: Data("{}".utf8)), for: source)
        context.record(ResponseData(statusCode: 200, body: Data("{}".utf8)), for: source)

        XCTAssertEqual(context.unresolvedOutputs, ["x"])
    }
}
