import XCTest
@testable import NetCheckerTrafficCore

final class FlowRequestSlotTests: XCTestCase {

    private func request(
        _ urlString: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> RequestData {
        RequestData(url: URL(string: urlString)!, method: .post, headers: headers, body: body)
    }

    // MARK: - Плейсхолдеры пути

    func testFindsPathPlaceholder() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/orders/%7BorderId%7D/pay"))
        let placeholders = slots.filter { $0.kind == .pathPlaceholder }

        XCTAssertEqual(placeholders.map(\.name), ["orderId"])
    }

    func testFindsSeveralPlaceholders() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/u/%7BuserId%7D/o/%7BorderId%7D"))
        let names = slots.filter { $0.kind == .pathPlaceholder }.map(\.name)

        XCTAssertEqual(names, ["userId", "orderId"])
    }

    func testFindsUnescapedPlaceholder() {
        let slots = FlowRequestSlots.pathPlaceholders(in: URL(string: "https://a.com/o/x")!)
        XCTAssertTrue(slots.isEmpty)
    }

    func testURLWithoutPlaceholdersHasNone() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/orders/7781/pay"))
        XCTAssertTrue(slots.filter { $0.kind == .pathPlaceholder }.isEmpty)
    }

    // MARK: - Заголовки

    func testExistingHeadersBecomeSlotsWithTheirValue() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/x", headers: ["X-Trace": "t-1"]))
        let header = slots.first { $0.kind == .header && $0.name == "X-Trace" }

        XCTAssertNotNil(header)
        XCTAssertEqual(header?.currentValue, "t-1")
    }

    /// Токен чаще всего кладут в Authorization — предлагаем, даже если его нет
    func testAuthorizationIsSuggestedWhenAbsent() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/x"))
        XCTAssertTrue(slots.contains { $0.kind == .suggestedHeader && $0.name == "Authorization" })
    }

    func testSuggestedHeaderIsNotDuplicatedWhenPresent() {
        let slots = FlowRequestSlots.slots(
            in: request("https://a.com/x", headers: ["authorization": "Bearer t"])
        )

        XCTAssertFalse(slots.contains { $0.kind == .suggestedHeader && $0.name == "Authorization" })
        XCTAssertTrue(slots.contains { $0.kind == .header })
    }

    // MARK: - Параметры и тело

    func testQueryItemsBecomeSlots() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/search?q=shoes"))
        let query = slots.first { $0.kind == .queryItem }

        XCTAssertEqual(query?.name, "q")
        XCTAssertEqual(query?.currentValue, "shoes")
    }

    func testBodyFieldsBecomeSlotsWithCurrentValue() {
        let body = Data(#"{"userId":1,"title":"hello"}"#.utf8)
        let slots = FlowRequestSlots.slots(in: request("https://a.com/x", body: body))
        let fields = slots.filter { $0.kind == .bodyField }

        XCTAssertEqual(fields.map(\.name), ["title", "userId"])
        XCTAssertEqual(fields.first { $0.name == "userId" }?.currentValue, "1")
    }

    func testNonJSONBodyYieldsNoFieldSlots() {
        let slots = FlowRequestSlots.slots(in: request("https://a.com/x", body: Data("plain".utf8)))
        XCTAssertTrue(slots.filter { $0.kind == .bodyField }.isEmpty)
    }

    // MARK: - Отображение в модель

    /// Слот должен превращаться в подстановку, которая реально сработает
    func testSlotTargetActuallyInjects() {
        var target = request("https://a.com/orders/%7BorderId%7D/pay")
        let slot = FlowRequestSlots.slots(in: target).first { $0.kind == .pathPlaceholder }!

        FlowValueInjector.apply(FlowInput(name: "orderId", target: slot.target),
                                value: "7781", to: &target)

        XCTAssertEqual(target.url.absoluteString, "https://a.com/orders/7781/pay")
    }

    func testBodySlotTargetInjectsIntoBody() {
        var target = request("https://a.com/x", body: Data(#"{"userId":0}"#.utf8))
        let slot = FlowRequestSlots.slots(in: target).first { $0.kind == .bodyField }!

        FlowValueInjector.apply(FlowInput(name: "userId", target: slot.target),
                                value: "42", to: &target)

        let object = try? JSONSerialization.jsonObject(with: target.body ?? Data()) as? [String: Any]
        XCTAssertEqual((object ?? [:])["userId"] as? String, "42")
    }

    func testSlotsAreUniquelyIdentified() {
        let slots = FlowRequestSlots.slots(
            in: request("https://a.com/x?q=1", headers: ["A": "1"], body: Data(#"{"q":2}"#.utf8))
        )
        XCTAssertEqual(Set(slots.map(\.id)).count, slots.count)
    }
}
