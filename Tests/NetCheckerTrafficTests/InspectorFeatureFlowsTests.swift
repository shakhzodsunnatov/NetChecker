import XCTest
@testable import NetCheckerTrafficCore

@MainActor
final class InspectorFeatureFlowsTests: XCTestCase {

    func testFlowsIsAFeature() {
        XCTAssertTrue(InspectorFeature.allCases.contains(.flows))
        XCTAssertEqual(InspectorFeature.flows.title, "Flows")
        XCTAssertFalse(InspectorFeature.flows.summary.isEmpty)
    }

    func testFlowsCanBeHidden() {
        let settings = InspectorFeatureSettings.shared
        settings.showAll()

        settings.setVisible(false, for: .flows)
        XCTAssertFalse(settings.isVisible(.flows))

        settings.showAll()
        XCTAssertTrue(settings.isVisible(.flows))
    }

    func testOnlyTrafficIsRequired() {
        for feature in InspectorFeature.allCases {
            XCTAssertEqual(feature.isRequired, feature == .traffic, "\(feature) требуемость определена неверно")
        }
    }
}
