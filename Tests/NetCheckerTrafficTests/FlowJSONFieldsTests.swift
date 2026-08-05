import XCTest
@testable import NetCheckerTrafficCore

final class FlowJSONFieldsTests: XCTestCase {

    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testFlattensTopLevelFields() {
        let fields = FlowJSONFields.fields(in: json(#"{"id":1,"title":"hello"}"#))

        XCTAssertEqual(fields.map(\.path).sorted(), ["id", "title"])
        XCTAssertEqual(fields.first { $0.path == "id" }?.value, "1")
        XCTAssertEqual(fields.first { $0.path == "title" }?.value, "hello")
    }

    func testFlattensNestedFieldsWithDottedPaths() {
        let fields = FlowJSONFields.fields(in: json(#"{"data":{"order":{"id":7781}}}"#))

        XCTAssertEqual(fields.map(\.path), ["data.order.id"])
        XCTAssertEqual(fields[0].value, "7781")
    }

    /// Путь пригоден для FlowValueSource.jsonPath — иначе выбор был бы бесполезен
    func testFlattenedPathExtractsTheSameValue() {
        let body = json(#"{"data":{"order":{"id":7781}}}"#)
        let field = FlowJSONFields.fields(in: body)[0]

        let extracted = FlowValueExtractor.extract(
            FlowOutput(name: "x", source: .jsonPath(field.path)),
            from: ResponseData(statusCode: 200, body: body)
        )

        XCTAssertEqual(extracted, field.value)
    }

    func testBooleanIsShownAsText() {
        let fields = FlowJSONFields.fields(in: json(#"{"paid":true}"#))
        XCTAssertEqual(fields[0].value, "true")
    }

    func testNullIsShown() {
        let fields = FlowJSONFields.fields(in: json(#"{"note":null}"#))
        XCTAssertEqual(fields[0].value, "null")
    }

    func testArrayItemsAreLimited() {
        let items = (0..<20).map { "{\"id\":\($0)}" }.joined(separator: ",")
        let fields = FlowJSONFields.fields(in: json("{\"items\":[\(items)]}"))

        XCTAssertEqual(fields.count, FlowJSONFields.maxArrayItems)
    }

    /// Индексы массивов текущим форматом пути не адресуются,
    /// поэтому такие поля показываются, но выбрать их нельзя
    func testArrayFieldsAreNotSelectable() {
        let fields = FlowJSONFields.fields(in: json(#"{"items":[{"id":1}]}"#))

        XCTAssertFalse(fields.allSatisfy(FlowJSONFields.isSelectable))
        XCTAssertTrue(fields[0].path.contains("["))
    }

    func testMalformedBodyYieldsNoFields() {
        XCTAssertTrue(FlowJSONFields.fields(in: json("not json")).isEmpty)
        XCTAssertTrue(FlowJSONFields.fields(in: nil).isEmpty)
    }

    func testSuggestedNameIsTheLastSegment() {
        let field = FlowJSONField(path: "data.order.id", value: "1", depth: 0)
        XCTAssertEqual(field.suggestedName, "id")
    }

    // MARK: - Поля тела запроса

    func testTopLevelKeysOfRequestBody() {
        let keys = FlowJSONFields.topLevelKeys(in: json(#"{"userId":1,"title":"x"}"#))
        XCTAssertEqual(keys, ["title", "userId"])
    }

    func testTopLevelKeysIgnoreNonObjects() {
        XCTAssertTrue(FlowJSONFields.topLevelKeys(in: json("[1,2,3]")).isEmpty)
        XCTAssertTrue(FlowJSONFields.topLevelKeys(in: nil).isEmpty)
    }
}

@MainActor
final class FlowOutcomeCaptureTests: XCTestCase {

    /// Ответ должен сохраняться в исходе шага — иначе выбирать значение
    /// для следующего шага не из чего
    func testOutcomeCarriesRequestAndResponse() async {
        let step = FlowStep(
            name: "s",
            request: RequestData(url: URL(string: "https://api.example.com/x")!, method: .get)
        )

        let runner = FlowRunner(executor: CapturingExecutor())
        await runner.run(Flow(name: "f", steps: [step]))

        let outcome = runner.outcomes[step.id]
        XCTAssertNotNil(outcome?.sentRequest, "Отправленный запрос не сохранён")
        XCTAssertNotNil(outcome?.response, "Ответ не сохранён")
        XCTAssertEqual(outcome?.response?.statusCode, 200)
    }

    /// И при несовпадении статуса тоже: значения из такого ответа
    /// по-прежнему могут понадобиться
    func testResponseIsKeptEvenWhenStatusCheckFails() async {
        let step = FlowStep(
            name: "s",
            request: RequestData(url: URL(string: "https://api.example.com/x")!, method: .get),
            expectedStatusCode: 404
        )

        let runner = FlowRunner(executor: CapturingExecutor())
        await runner.run(Flow(name: "f", steps: [step]))

        guard case .failed = runner.outcomes[step.id]?.state else {
            return XCTFail("Ожидалось падение по статусу")
        }
        XCTAssertNotNil(runner.outcomes[step.id]?.response)
    }
}

private struct CapturingExecutor: FlowExecuting {
    func execute(_ request: RequestData) async -> (ResponseData?, FlowRunError?) {
        (ResponseData(statusCode: 200, body: Data(#"{"id":7781}"#.utf8)), nil)
    }
}
