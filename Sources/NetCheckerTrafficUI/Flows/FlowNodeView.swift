import SwiftUI
import NetCheckerTrafficCore

/// Узел графа — один шаг сценария
struct FlowNodeView: View {
    let step: FlowStep
    let outcome: FlowStepOutcome?
    let index: Int
    let isFireAndForget: Bool

    private var state: FlowStepState { outcome?.state ?? .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            path
            status
            badges
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        // Пунктир у того, что не выполнялось: сплошная рамка одинаковой
        // толщины делала «ожидает» и «пропущен» неотличимыми от остальных
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(
                        lineWidth: isRunning ? 2 : 1,
                        dash: isUnexecuted ? [5, 4] : []
                    )
                )
        )
        .opacity(isDimmed ? 0.62 : 1)
        // scale, а не изменение размеров: соседние узлы не съезжают
        .scaleEffect(isRunning ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isRunning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Шаг \(index). \(step.name). \(statusText)")
    }

    // MARK: - Части

    private var header: some View {
        HStack(spacing: 5) {
            indicator
            NetCheckerTrafficUI_MethodBadge(method: step.request.method)
            Spacer(minLength: 0)
        }
    }

    private var path: some View {
        Text(step.request.url.path.isEmpty ? "/" : step.request.url.path)
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var status: some View {
        Text(statusText)
            .font(.caption2)
            .foregroundStyle(statusColor)
            .lineLimit(2)
    }

    private var badges: some View {
        HStack(spacing: 4) {
            if isFireAndForget {
                chip("не ждём", color: .orange)
            }
            if let condition = step.condition {
                chip(condition.summary, color: .purple)
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .lineLimit(1)
    }

    private var indicator: some View {
        ZStack {
            Circle()
                .fill(indicatorColor)
                .frame(width: 18, height: 18)

            // Состояние передаётся не только цветом
            switch state {
            case .succeeded:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            case .failed:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            case .skipped:
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            default:
                Text("\(index)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Состояние

    private var isRunning: Bool { state == .running }

    private var isDimmed: Bool {
        state == .pending || state == .notRun || state == .skipped
    }

    /// Шаг не выполнялся — рамка пунктиром
    private var isUnexecuted: Bool {
        state == .pending || state == .notRun || state == .skipped
    }

    private var statusText: String {
        switch state {
        case .pending: return "ожидает"
        case .running: return "выполняется…"
        case .succeeded:
            guard let code = outcome?.statusCode else { return "готово" }
            return "\(code) · \(durationText)"
        case .failed(let message): return message
        case .skipped: return "пропущен"
        case .notRun: return "не запускался"
        }
    }

    private var durationText: String {
        let duration = outcome?.duration ?? 0
        return duration < 1
            ? "\(Int(duration * 1000)) мс"
            : String(format: "%.2f с", duration)
    }

    private var statusColor: Color {
        if case .failed = state { return .red }
        return .secondary
    }

    private var indicatorColor: Color {
        switch state {
        case .succeeded: return .green
        case .failed: return .red
        case .running: return .accentColor
        case .skipped: return .secondary
        default: return isFireAndForget ? .orange : Color.secondary.opacity(0.55)
        }
    }

    private var borderColor: Color {
        switch state {
        case .succeeded: return .green.opacity(0.5)
        case .failed: return .red
        case .running: return .accentColor
        default: return isFireAndForget ? .orange.opacity(0.6) : Color.secondary.opacity(0.2)
        }
    }
}
