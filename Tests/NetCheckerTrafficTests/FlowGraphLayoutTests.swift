import XCTest
@testable import NetCheckerTrafficCore

final class FlowGraphLayoutTests: XCTestCase {

    private func step(_ name: String, dependsOn: [UUID] = []) -> FlowStep {
        FlowStep(
            name: name,
            request: RequestData(url: URL(string: "https://a.com/\(name)")!, method: .get),
            dependsOn: dependsOn
        )
    }

    func testEmptyFlowHasEmptyLayout() {
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: []))

        XCTAssertTrue(layout.nodes.isEmpty)
        XCTAssertEqual(layout.size, .zero)
    }

    func testChainPlacesEachStepOnItsOwnLevel() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let c = step("c", dependsOn: [b.id])
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a, b, c]))

        XCTAssertEqual(layout.frame(of: a.id)?.level, 0)
        XCTAssertEqual(layout.frame(of: b.id)?.level, 1)
        XCTAssertEqual(layout.frame(of: c.id)?.level, 2)
    }

    /// Один ряд означает одновременность — узлы обязаны стоять на одной высоте
    func testParallelStepsShareTheSameY() {
        let a = step("a")
        let b = step("b")
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a, b]))

        XCTAssertEqual(layout.frame(of: a.id)?.center.y, layout.frame(of: b.id)?.center.y)
        XCTAssertNotEqual(layout.frame(of: a.id)?.center.x, layout.frame(of: b.id)?.center.x)
    }

    func testLevelsGoDownwards() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a, b]))

        let top = layout.frame(of: a.id)!.center.y
        let bottom = layout.frame(of: b.id)!.center.y
        XCTAssertGreaterThan(bottom, top)
    }

    func testNodesDoNotOverlapWithinRow() {
        let steps = (0..<4).map { step("s\($0)") }
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: steps))
        let rects = steps.compactMap { layout.frame(of: $0.id)?.rect }

        for i in rects.indices {
            for j in rects.indices where j > i {
                XCTAssertFalse(rects[i].intersects(rects[j]))
            }
        }
    }

    func testRowIsCentredOnCanvas() {
        let a = step("a")
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a]))

        XCTAssertEqual(layout.frame(of: a.id)!.center.x, layout.size.width / 2, accuracy: 0.001)
    }

    func testCanvasIsLargeEnoughForEveryNode() {
        let a = step("a")
        let b = step("b")
        let c = step("c", dependsOn: [a.id, b.id])
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a, b, c]))

        let bounds = CGRect(origin: .zero, size: layout.size)
        for node in layout.nodes {
            XCTAssertTrue(bounds.contains(node.rect), "\(node.rect) не помещается в \(layout.size)")
        }
    }

    // MARK: - Точки провода

    func testOutletIsBelowInlet() {
        let a = step("a")
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a]))
        let node = layout.frame(of: a.id)!

        XCTAssertGreaterThan(node.outlet.y, node.inlet.y)
        XCTAssertEqual(node.outlet.x, node.center.x)
    }

    /// Провод, брошенный на узел, должен этот узел находить
    func testNodeAtPointFindsNodeUnderItsCentre() {
        let a = step("a")
        let b = step("b")
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a, b]))
        let target = layout.frame(of: b.id)!

        XCTAssertEqual(layout.node(at: target.center)?.id, b.id)
    }

    func testNodeAtPointReturnsNilOutsideAnyNode() {
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [step("a")]))
        XCTAssertNil(layout.node(at: CGPoint(x: 1, y: 1)))
    }

    func testLevelCentresMatchNodeRows() {
        let a = step("a")
        let b = step("b", dependsOn: [a.id])
        let layout = FlowGraphLayoutBuilder.layout(Flow(name: "f", steps: [a, b]))

        XCTAssertEqual(layout.levelCenters.count, 2)
        XCTAssertEqual(layout.levelCenters[0], layout.frame(of: a.id)?.center.y)
        XCTAssertEqual(layout.levelCenters[1], layout.frame(of: b.id)?.center.y)
    }
}
