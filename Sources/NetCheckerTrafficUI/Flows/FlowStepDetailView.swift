import SwiftUI
import NetCheckerTrafficCore

/// Разбор шага и действия восстановления
public struct NetCheckerTrafficUI_FlowStepDetailView: View {
    let step: FlowStep
    let outcome: FlowStepOutcome?
    let onRetry: () -> Void
    let onSkip: () -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    public init(
        step: FlowStep,
        outcome: FlowStepOutcome?,
        onRetry: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.step = step
        self.outcome = outcome
        self.onRetry = onRetry
        self.onSkip = onSkip
    }

    private var hasFailed: Bool {
        if case .failed = outcome?.state { return true }
        return false
    }

    public var body: some View {
        List {
            Section("Запрос") {
                LabeledContent("Метод", value: step.request.method.rawValue)
                LabeledContent("URL") {
                    Text(step.request.url.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
            }

            if let condition = step.condition {
                Section("Условие") {
                    Text(condition.summary)
                        .font(.system(.subheadline, design: .monospaced))
                }
            }

            if let outcome = outcome {
                resultSection(outcome)

                if !outcome.substitutions.isEmpty {
                    substitutionsSection(outcome)
                }
            }

            if hasFailed {
                recoverySection
            }
        }
        .navigationTitle(step.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    // MARK: - Секции

    private func resultSection(_ outcome: FlowStepOutcome) -> some View {
        Section("Результат") {
            if let status = outcome.statusCode {
                LabeledContent("Статус") {
                    NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
                }
            }

            LabeledContent("Длительность",
                           value: String(format: "%.0f мс", outcome.duration * 1000))

            if case .failed(let message) = outcome.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func substitutionsSection(_ outcome: FlowStepOutcome) -> some View {
        Section {
            ForEach(outcome.substitutions.sorted(by: { $0.key < $1.key }), id: \.key) { name, value in
                LabeledContent(name) {
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Подставлено")
        } footer: {
            Text("Чаще всего ломается именно подстановка, а не сам запрос.")
        }
    }

    private var recoverySection: some View {
        Section {
            Button {
                onRetry()
                dismiss()
            } label: {
                Label("Повторить с этого шага", systemImage: "arrow.clockwise")
            }

            Button {
                onSkip()
                dismiss()
            } label: {
                Label("Пропустить шаг", systemImage: "forward")
            }
        } footer: {
            Text("Значения предыдущих шагов сохранены — логиниться заново не нужно.")
        }
    }
}
