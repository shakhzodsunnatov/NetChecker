import SwiftUI

/// Состояние связи между уровнями
enum FlowEdgeState {
    case idle
    case active
    case failed
    /// Прогон до сюда не дошёл
    case notRun
}

/// Связь между уровнями с подписями передаваемых значений
struct FlowEdgeView: View {
    /// Имена значений; больше двух сворачиваются в «+N»,
    /// иначе подпись не помещается по ширине телефона
    let labels: [String]
    let state: FlowEdgeState

    private var caption: String? {
        guard !labels.isEmpty else { return nil }
        if labels.count <= 2 { return labels.joined(separator: " · ") }
        return "\(labels[0]) +\(labels.count - 1)"
    }

    var body: some View {
        ZStack {
            line

            if let caption = caption {
                Text(caption)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(background)
                    .foregroundStyle(color)
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel(caption.map { "Передаётся: \($0)" } ?? "Связь между шагами")
    }

    @ViewBuilder
    private var line: some View {
        if state == .notRun {
            // Пунктир: до этих шагов дело не дошло
            Rectangle()
                .fill(.clear)
                .frame(width: 2)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .foregroundStyle(color)
                        .frame(width: 2)
                )
        } else {
            Rectangle()
                .fill(color)
                .frame(width: 2)
        }
    }

    private var color: Color {
        switch state {
        case .idle: return Color.secondary.opacity(0.35)
        case .active: return .purple
        case .failed: return .red
        case .notRun: return Color.secondary.opacity(0.3)
        }
    }

    private var background: Color {
        switch state {
        case .active: return .purple.opacity(0.12)
        case .failed: return .red.opacity(0.12)
        default: return Color.secondary.opacity(0.12)
        }
    }
}
