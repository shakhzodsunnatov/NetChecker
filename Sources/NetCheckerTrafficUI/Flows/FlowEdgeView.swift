import SwiftUI
import NetCheckerTrafficCore

/// Состояние связи
enum FlowEdgeState {
    case idle
    case active
    case failed
    /// Прогон до этих шагов не дошёл
    case notRun
}

/// Провод между двумя узлами полотна
struct FlowWire: Identifiable {
    let id: String
    let from: CGPoint
    let to: CGPoint
    /// Имена значений, которые по нему передаются
    let labels: [String]
    let state: FlowEdgeState

    var midpoint: CGPoint {
        // Точка на кривой при t = 0.5 при вертикальных касательных —
        // ровно середина по обеим осям
        CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
    }
}

/// Кривая с вертикальными касательными на концах.
///
/// Провод выходит из узла строго вниз и входит в следующий строго сверху —
/// поэтому стрелка всегда смотрит вниз, а направление читается без подписи.
struct FlowWireShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)

        // Чем дальше узлы, тем плавнее дуга; вверх идущие связи
        // (шаг ждёт кого-то с дальнего уровня) не схлопываются в прямую
        let reach = max(abs(to.y - from.y) * 0.45, 30)

        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x, y: from.y + reach),
            control2: CGPoint(x: to.x, y: to.y - reach)
        )
        return path
    }
}

/// Наконечник в точке входа
struct FlowArrowShape: Shape {
    let tip: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 5, y: tip.y - 8))
        path.addLine(to: CGPoint(x: tip.x + 5, y: tip.y - 8))
        path.closeSubpath()
        return path
    }
}

extension FlowEdgeState {
    var color: Color {
        switch self {
        case .idle: return Color.secondary.opacity(0.45)
        case .active: return .purple
        case .failed: return .red
        case .notRun: return Color.secondary.opacity(0.3)
        }
    }

    var labelBackground: Color {
        switch self {
        case .active: return .purple.opacity(0.16)
        case .failed: return .red.opacity(0.16)
        default: return Color.secondary.opacity(0.16)
        }
    }

    var dash: [CGFloat] {
        switch self {
        case .notRun: return [5, 5]
        case .active: return [7, 5]
        default: return []
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .active, .failed: return 2.4
        default: return 1.8
        }
    }
}

extension Int {
    /// Ограничить индекс диапазоном — уровень мог сжаться после удаления шага
    func clamped(to range: Range<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
