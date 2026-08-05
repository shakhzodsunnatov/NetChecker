import XCTest
@testable import NetCheckerTrafficCore

final class FlowConditionTests: XCTestCase {

    private let values = ["total": "120", "status": "paid", "flag": "true", "empty": ""]

    func testEqualsMatches() {
        XCTAssertTrue(FlowCondition(valueName: "status", operator: .equals, operand: "paid")
            .evaluate(values: values))
    }

    func testEqualsFailsOnDifferentValue() {
        XCTAssertFalse(FlowCondition(valueName: "status", operator: .equals, operand: "failed")
            .evaluate(values: values))
    }

    func testNotEquals() {
        XCTAssertTrue(FlowCondition(valueName: "status", operator: .notEquals, operand: "failed")
            .evaluate(values: values))
    }

    func testNumericComparison() {
        XCTAssertTrue(FlowCondition(valueName: "total", operator: .greaterThan, operand: "0")
            .evaluate(values: values))
        XCTAssertFalse(FlowCondition(valueName: "total", operator: .lessThan, operand: "0")
            .evaluate(values: values))
    }

    /// Сравнение нечисла оператором «больше» — ложь, а не падение
    func testNonNumericComparisonIsFalse() {
        XCTAssertFalse(FlowCondition(valueName: "status", operator: .greaterThan, operand: "0")
            .evaluate(values: values))
    }

    func testIsTrueAndIsFalse() {
        XCTAssertTrue(FlowCondition(valueName: "flag", operator: .isTrue).evaluate(values: values))
        XCTAssertFalse(FlowCondition(valueName: "flag", operator: .isFalse).evaluate(values: values))
    }

    func testExistsAndIsEmpty() {
        XCTAssertTrue(FlowCondition(valueName: "status", operator: .exists).evaluate(values: values))
        XCTAssertFalse(FlowCondition(valueName: "missing", operator: .exists).evaluate(values: values))
        XCTAssertTrue(FlowCondition(valueName: "empty", operator: .isEmpty).evaluate(values: values))
    }

    /// Отсутствующее значение проваливает любое сравнение,
    /// а не считается пустой строкой
    func testMissingValueIsFalseForComparisons() {
        XCTAssertFalse(FlowCondition(valueName: "missing", operator: .equals, operand: "x")
            .evaluate(values: values))
        XCTAssertFalse(FlowCondition(valueName: "missing", operator: .isTrue).evaluate(values: values))
    }

    func testMissingValueCountsAsEmpty() {
        XCTAssertTrue(FlowCondition(valueName: "missing", operator: .isEmpty).evaluate(values: values))
    }

    func testSummaryReadsAsABranchLabel() {
        XCTAssertEqual(
            FlowCondition(valueName: "total", operator: .greaterThan, operand: "0").summary,
            "total больше 0"
        )
        XCTAssertEqual(
            FlowCondition(valueName: "paid", operator: .isTrue).summary,
            "paid истина"
        )
    }

    func testOperandRequirementIsDeclared() {
        XCTAssertTrue(FlowConditionOperator.equals.needsOperand)
        XCTAssertFalse(FlowConditionOperator.isTrue.needsOperand)
    }
}
