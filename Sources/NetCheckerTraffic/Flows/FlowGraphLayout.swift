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

/// Часть блока, попавшая на один уровень.
///
/// Блок рисуется не одним прямоугольником на все уровни, а срезом на
/// каждом: очередь занимает несколько рядов, и общая рамка накрыла бы
/// заодно чужие шаги, стоящие в тех же рядах.
public struct FlowGraphSlice: Identifiable, Sendable, Equatable {
    public let id: String
    public let level: Int
    public let rect: CGRect

    public init(id: String, level: Int, rect: CGRect) {
        self.id = id
        self.level = level
        self.rect = rect
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

    /// Срезы блока по уровням, сверху вниз
    public func slices(of stepIds: [UUID], id: String) -> [FlowGraphSlice] {
        let wanted = Set(stepIds)
        let members = nodes.filter { wanted.contains($0.id) }
        guard !members.isEmpty else { return [] }

        return Dictionary(grouping: members, by: \.level)
            .map { level, group -> FlowGraphSlice in
                let rects = group.map(\.rect)
                let minX = rects.map(\.minX).min() ?? 0
                let maxX = rects.map(\.maxX).max() ?? 0
                let minY = rects.map(\.minY).min() ?? 0
                let maxY = rects.map(\.maxY).max() ?? 0
                return FlowGraphSlice(
                    id: "\(id)-\(level)",
                    level: level,
                    rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                )
            }
            .sorted { $0.level < $1.level }
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
        let levels = ordered(flow.levels(), in: flow)
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

    /// Разложить каждый ряд по дорожкам: участники одного блока встают
    /// подряд, иначе рамка блока накрыла бы чужой шаг, случайно оказавшийся
    /// между ними.
    ///
    /// Номер дорожки одинаков на всех рядах, поэтому очередь идёт сверху
    /// вниз одной колонкой, а не скачет из стороны в сторону.
    static func ordered(_ levels: [[FlowStep]], in flow: Flow) -> [[FlowStep]] {
        guard !flow.groups.isEmpty else { return levels }

        var laneOrder: [UUID: Int] = [:]
        for level in levels {
            for step in level {
                let lane = flow.group(containing: step.id)?.id ?? step.id
                if laneOrder[lane] == nil { laneOrder[lane] = laneOrder.count }
            }
        }

        return levels.map { level in
            level.enumerated()
                .sorted { left, right in
                    let leftLane = lane(of: left.element, in: flow)
                    let rightLane = lane(of: right.element, in: flow)

                    let leftIndex = laneOrder[leftLane] ?? 0
                    let rightIndex = laneOrder[rightLane] ?? 0
                    if leftIndex != rightIndex { return leftIndex < rightIndex }

                    // Внутри блока порядок задаёт сам блок
                    let leftSeat = seat(of: left.element, in: flow)
                    let rightSeat = seat(of: right.element, in: flow)
                    if leftSeat != rightSeat { return leftSeat < rightSeat }

                    return left.offset < right.offset
                }
                .map(\.element)
        }
    }

    private static func lane(of step: FlowStep, in flow: Flow) -> UUID {
        flow.group(containing: step.id)?.id ?? step.id
    }

    private static func seat(of step: FlowStep, in flow: Flow) -> Int {
        flow.group(containing: step.id)?.stepIds.firstIndex(of: step.id) ?? 0
    }

    private static func width(ofRowWith level: [FlowStep]) -> CGFloat {
        guard !level.isEmpty else { return nodeSize.width }
        return CGFloat(level.count) * nodeSize.width
            + CGFloat(level.count - 1) * horizontalGap
    }
}
