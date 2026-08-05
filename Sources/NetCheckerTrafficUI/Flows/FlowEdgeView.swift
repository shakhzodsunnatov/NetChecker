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

/// Одна связь между узлами соседних уровней
struct FlowConnection: Identifiable {
    let id: String
    /// Положение исходного узла в своём уровне, доля ширины
    let fromFraction: CGFloat
    /// Положение целевого узла
    let toFraction: CGFloat
    let state: FlowEdgeState
    /// Имена передаваемых значений
    let labels: [String]
}

/// Полоса связей между двумя уровнями.
///
/// Провода идут от конкретного узла к конкретному, а не общей вертикальной
/// чертой: иначе при нескольких узлах в уровне непонятно, что во что впадает.
struct FlowLevelConnector: View {
    let connections: [FlowConnection]

    private let height: CGFloat = 46

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ForEach(connections) { connection in
                    curve(for: connection, in: geometry.size)
                        .stroke(
                            color(connection.state),
                            style: StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                dash: connection.state == .notRun ? [4, 4] : []
                            )
                        )

                    arrowHead(for: connection, in: geometry.size)
                        .fill(color(connection.state))
                }
            }

            // Подпись — только у связей, которые что-то передают
            if let labelled = connections.first(where: { !$0.labels.isEmpty }) {
                Text(caption(for: labelled.labels))
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(background(labelled.state))
                    .foregroundStyle(color(labelled.state))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Геометрия

    private func curve(for connection: FlowConnection, in size: CGSize) -> Path {
        let start = CGPoint(x: size.width * connection.fromFraction, y: 0)
        let end = CGPoint(x: size.width * connection.toFraction, y: size.height - 6)

        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x, y: size.height * 0.55),
            control2: CGPoint(x: end.x, y: size.height * 0.45)
        )
        return path
    }

    private func arrowHead(for connection: FlowConnection, in size: CGSize) -> Path {
        let tip = CGPoint(x: size.width * connection.toFraction, y: size.height)
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - 4.5, y: tip.y - 7))
        path.addLine(to: CGPoint(x: tip.x + 4.5, y: tip.y - 7))
        path.closeSubpath()
        return path
    }

    // MARK: - Оформление

    private func caption(for labels: [String]) -> String {
        labels.count <= 2
            ? labels.joined(separator: " · ")
            : "\(labels[0]) +\(labels.count - 1)"
    }

    private func color(_ state: FlowEdgeState) -> Color {
        switch state {
        case .idle: return Color.secondary.opacity(0.4)
        case .active: return .purple
        case .failed: return .red
        case .notRun: return Color.secondary.opacity(0.35)
        }
    }

    private func background(_ state: FlowEdgeState) -> Color {
        switch state {
        case .active: return .purple.opacity(0.14)
        case .failed: return .red.opacity(0.14)
        default: return Color.secondary.opacity(0.14)
        }
    }

    private var accessibilityText: String {
        let labels = connections.flatMap(\.labels)
        return labels.isEmpty ? "Переход к следующему уровню" : "Передаётся: \(labels.joined(separator: ", "))"
    }
}

/// Подпись уровня — параллельность видна текстом, а не только раскладкой
struct FlowLevelCaption: View {
    let index: Int
    let isParallel: Bool

    var body: some View {
        Text(isParallel ? "УРОВЕНЬ \(index) · ОДНОВРЕМЕННО" : "УРОВЕНЬ \(index)")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 5)
    }
}

extension Int {
    /// Ограничить индекс диапазоном — уровень мог сжаться после удаления шага
    func clamped(to range: Range<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
