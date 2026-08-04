import SwiftUI
import NetCheckerTrafficCore

/// Состояние повтора запроса, выполняемого без ухода с экрана
enum InlineRetryState: Equatable {
    case idle
    case running
    case finished(status: Int?, duration: TimeInterval, size: Int64, error: String?)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Панель повтора запроса прямо на экране детали.
///
/// Раньше «Retry Original» отправлял запрос и выбрасывал результат: новая
/// запись появлялась в общем списке, и её нужно было искать вручную, уйдя
/// с открытого запроса. Теперь прогресс и итог видны на месте.
struct InlineRetryPanel: View {
    let state: InlineRetryState
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .running:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Повтор запроса…")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .transition(.move(edge: .top).combined(with: .opacity))

        case let .finished(status, duration, size, error):
            HStack(spacing: 10) {
                Image(systemName: error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error == nil ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    if let error = error {
                        Text("Повтор не удался")
                            .font(.caption.weight(.medium))
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        HStack(spacing: 6) {
                            Text("Повтор выполнен")
                                .font(.caption.weight(.medium))
                            if let status = status {
                                NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
                            }
                        }
                        Text("\(Self.durationText(duration)) · \(NetCheckerTrafficUI_ByteText.string(size))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        duration < 1
            ? String(format: "%.0f мс", duration * 1000)
            : String(format: "%.2f с", duration)
    }
}

/// Форматирование размеров для компактных панелей
enum NetCheckerTrafficUI_ByteText {
    static func string(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) Б" }
        if bytes < 1024 * 1024 { return String(format: "%.1f КБ", Double(bytes) / 1024) }
        return String(format: "%.1f МБ", Double(bytes) / (1024 * 1024))
    }
}
