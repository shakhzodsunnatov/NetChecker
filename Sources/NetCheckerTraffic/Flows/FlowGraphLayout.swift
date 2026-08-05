import Foundation
import CoreGraphics

/// Место одного шага на полотне
public struct FlowNodeFrame: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let level: Int
    public let center: CGPoint
    public let size: CGSize

    public init(id: UUID, level: Int, center: CGPoint, size: CGSize) {
        self.id = id
        self.level = level
        self.center = center
        self.size = size
    }

    /// Точка выхода — снизу: значения текут сверху вниз
    public var outlet: CGPoint {
        CGPoint(x: center.x, y: center.y + size.height / 2)
    }

    /// Точка входа — сверху
    public var inlet: CGPoint {
        CGPoint(x: center.x, y: center.y - size.height / 2)
    }

    public var rect: CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Готовая раскладка сценария
public struct FlowGraphLayout: Sendable, Equatable {
    public let nodes: [FlowNodeFrame]
    public let size: CGSize

    /// Вертикальные отметки уровней: y-центр каждого ряда
    public let levelCenters: [CGFloat]

    public init(nodes: [FlowNodeFrame], size: CGSize, levelCenters: [CGFloat]) {
        self.nodes = nodes
        self.size = size
        self.levelCenters = levelCenters
    }

    public func frame(of id: UUID) -> FlowNodeFrame? {
        nodes.first { $0.id == id }
    }

    /// Шаг под точкой — для броска провода на узел
    public func node(at point: CGPoint) -> FlowNodeFrame? {
        nodes.first { $0.rect.contains(point) }
    }
}

/// Раскладка по уровням: ряд — это то, что идёт одновременно.
///
/// Позиции считаются, а не задаются руками: перетаскивание узлов
/// разрушило бы единственное, что здесь означает смысл — то, что
/// один ряд выполняется параллельно.
public enum FlowGraphLayoutBuilder {
    public static let nodeSize = CGSize(width: 176, height: 100)
    public static let horizontalGap: CGFloat = 26
    public static let verticalGap: CGFloat = 88
    public static let padding: CGFloat = 44

    public static func layout(_ flow: Flow) -> FlowGraphLayout {
        let levels = flow.levels()
        guard !levels.isEmpty else {
            return FlowGraphLayout(nodes: [], size: .zero, levelCenters: [])
        }

        let widest = levels.map(width(ofRowWith:)).max() ?? nodeSize.width
        let canvasWidth = widest + padding * 2
        let canvasHeight = CGFloat(levels.count) * nodeSize.height
            + CGFloat(max(levels.count - 1, 0)) * verticalGap
            + padding * 2

        var nodes: [FlowNodeFrame] = []
        var levelCenters: [CGFloat] = []

        for (levelIndex, level) in levels.enumerated() {
            let y = padding + nodeSize.height / 2
                + CGFloat(levelIndex) * (nodeSize.height + verticalGap)
            levelCenters.append(y)

            let rowWidth = width(ofRowWith: level)
            var x = (canvasWidth - rowWidth) / 2 + nodeSize.width / 2

            for step in level {
                nodes.append(
                    FlowNodeFrame(
                        id: step.id,
                        level: levelIndex,
                        center: CGPoint(x: x, y: y),
                        size: nodeSize
                    )
                )
                x += nodeSize.width + horizontalGap
            }
        }

        return FlowGraphLayout(
            nodes: nodes,
            size: CGSize(width: canvasWidth, height: canvasHeight),
            levelCenters: levelCenters
        )
    }

    private static func width(ofRowWith level: [FlowStep]) -> CGFloat {
        guard !level.isEmpty else { return nodeSize.width }
        return CGFloat(level.count) * nodeSize.width
            + CGFloat(level.count - 1) * horizontalGap
    }
}
