import XCTest
@testable import NetCheckerTrafficCore

final class FlowValueBindingTests: XCTestCase {

    private func response(_ json: String, headers: [String: String] = [:]) -> ResponseData {
        ResponseData(statusCode: 200, headers: headers, body: Data(json.utf8))
    }

    // MARK: - Извлечение

    func testExtractsTopLevelField() {
        let output = FlowOutput(name: "token", source: .jsonPath("token"))
        XCTAssertEqual(FlowValueExtractor.extract(output, from: response(#"{"token":"abc"}"#)), "abc")
    }

    func testExtractsNestedField() {
        let output = FlowOutput(name: "id", source: .jsonPath("data.order.id"))
        let value = FlowValueExtractor.extract(output, from: response(#"{"data":{"order":{"id":7781}}}"#))
        XCTAssertEqual(value, "7781")
    }

    func testExtractsBooleanAsText() {
        let output = FlowOutput(name: "paid", source: .jsonPath("paid"))
        XCTAssertEqual(FlowValueExtractor.extract(output, from: response(#"{"paid":true}"#)), "true")
    }

    func testExtractsHeaderIgnoringCase() {
        let output = FlowOutput(name: "trace", source: .header("x-trace"))
        XCTAssertEqual(FlowValueExtractor.extract(output, from: response("{}", headers: ["X-Trace": "t-1"])), "t-1")
    }

    func testMissingFieldYieldsNil() {
        let output = FlowOutput(name: "token", source: .jsonPath("nope"))
        XCTAssertNil(FlowValueExtractor.extract(output, from: response(#"{"token":"abc"}"#)))
    }

    func testMalformedBodyYieldsNil() {
        let output = FlowOutput(name: "token", source: .jsonPath("token"))
        XCTAssertNil(FlowValueExtractor.extract(output, from: response("not json")))
    }

    // MARK: - Подстановка

    func testInjectsHeader() {
        var request = RequestData(url: URL(string: "https://a.com/x")!, method: .get)
        FlowValueInjector.apply(FlowInput(name: "token", target: .header("Authorization")),
                                value: "Bearer abc", to: &request)
        XCTAssertEqual(request.headers["Authorization"], "Bearer abc")
    }

    func testInjectsPathPlaceholder() {
        var request = RequestData(url: URL(string: "https://a.com/orders/%7BorderId%7D/pay")!, method: .post)
        FlowValueInjector.apply(FlowInput(name: "orderId", target: .pathPlaceholder("orderId")),
                                value: "7781", to: &request)
        XCTAssertEqual(request.url.absoluteString, "https://a.com/orders/7781/pay")
    }

    func testInjectsQueryItem() {
        var request = RequestData(url: URL(string: "https://a.com/search")!, method: .get)
        FlowValueInjector.apply(FlowInput(name: "q", target: .queryItem("q")), value: "shoes", to: &request)
        XCTAssertEqual(request.url.absoluteString, "https://a.com/search?q=shoes")
    }

    func testQueryItemReplacesExistingValue() {
        var request = RequestData(url: URL(string: "https://a.com/search?q=old")!, method: .get)
        FlowValueInjector.apply(FlowInput(name: "q", target: .queryItem("q")), value: "new", to: &request)
        XCTAssertEqual(request.url.absoluteString, "https://a.com/search?q=new")
    }

    func testInjectsBodyField() {
        var request = RequestData(url: URL(string: "https://a.com/pay")!, method: .post,
                                  body: Data(#"{"orderId":0}"#.utf8))
        FlowValueInjector.apply(FlowInput(name: "orderId", target: .bodyField("orderId")),
                                value: "7781", to: &request)

        let body = try? JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]
        XCTAssertEqual((body ?? [:])["orderId"] as? String, "7781")
    }

    func testBodyInjectionUpdatesRecordedSize() {
        var request = RequestData(url: URL(string: "https://a.com/pay")!, method: .post,
                                  body: Data(#"{"orderId":0}"#.utf8))
        FlowValueInjector.apply(FlowInput(name: "orderId", target: .bodyField("orderId")),
                                value: "7781", to: &request)

        XCTAssertEqual(request.bodySize, Int64(request.body?.count ?? 0))
    }

    func testBodyInjectionLeavesNonJSONBodyAlone() {
        let original = Data("plain text".utf8)
        var request = RequestData(url: URL(string: "https://a.com/pay")!, method: .post, body: original)
        FlowValueInjector.apply(FlowInput(name: "x", target: .bodyField("x")), value: "1", to: &request)

        XCTAssertEqual(request.body, original)
    }
}
