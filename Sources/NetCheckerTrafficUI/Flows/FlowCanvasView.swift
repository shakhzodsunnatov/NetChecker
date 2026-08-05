import SwiftUI
import NetCheckerTrafficCore

/// Экран сценария: свободное полотно с шагами и управление прогоном.
public struct NetCheckerTrafficUI_FlowCanvasView: View {
    let flow: Flow

    @StateObject private var runner = FlowRunner()
    @State private var selectedStep: FlowStep?
    @State private var isAddingSteps = false
    @State private var connecting: FlowConnectTarget?

    /// Пара шагов, между которыми настраивается передача значения
    struct FlowConnectTarget: Identifiable {
        let sourceId: UUID
        let targetId: UUID
        var id: String { "\(sourceId)-\(targetId)" }
    }

    @ObservedObject private var store = FlowStore.shared

    public init(flow: Flow) {
        self.flow = flow
    }

    /// Актуальная версия сценария: шаги могут добавляться во время работы
    private var current: Flow {
        store.flow(id: flow.id) ?? flow
    }

    public var body: some View {
        VStack(spacing: 0) {
            runBar

            if let reason = runner.refusalReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
            }

            if current.steps.isEmpty {
                emptyState
            } else {
                FlowGraphView(
                    flow: current,
                    outcomes: runner.outcomes,
                    isRunning: runner.isRunning,
                    onSelect: { selectedStep = $0 },
                    onConnect: { source, target in
                        connecting = FlowConnectTarget(sourceId: source, targetId: target)
                    },
                    onDelete: removeStep
                )
            }
        }
        .navigationTitle(current.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isAddingSteps = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("netchecker.addFlowStep")

                Button {
                    SharePresenter.present(items: [FlowExporter.export(current)])
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(current.steps.isEmpty)
            }
        }
        .sheet(item: $selectedStep) { step in
            NavigationStack {
                NetCheckerTrafficUI_FlowStepDetailView(
                    step: current.step(id: step.id) ?? step,
                    outcome: runner.outcomes[step.id],
                    flowId: current.id,
                    previousResponses: runner.outcomes.compactMapValues(\.response),
                    onRetry: { Task { await runner.retry(from: step.id, in: current) } },
                    onSkip: { Task { await runner.skip(step.id, in: current) } }
                )
            }
        }
        .sheet(item: $connecting) { pair in
            NavigationStack {
                FlowConnectView(
                    flowId: current.id,
                    sourceStepId: pair.sourceId,
                    targetStepId: pair.targetId,
                    sourceResponse: runner.outcomes[pair.sourceId]?.response
                )
            }
        }
        .sheet(isPresented: $isAddingSteps) {
            NavigationStack {
                FlowStepPickerView { records in
                    appendSteps(from: records)
                }
            }
        }
    }

    // MARK: - Панель прогона

    private var runBar: some View {
        Button {
            Task { await runner.run(current) }
        } label: {
            HStack(spacing: 6) {
                Spacer()
                if runner.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Выполняется…")
                } else {
                    Image(systemName: "play.fill")
                    Text("Запустить")
                }
                Spacer()
            }
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .disabled(runner.isRunning || current.steps.isEmpty)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text("В сценарии нет шагов")
                .font(.headline)

            Text("Добавьте запросы из пойманного трафика — порядок выбора задаст порядок шагов.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                isAddingSteps = true
            } label: {
                Label("Добавить шаги", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Изменение сценария

    /// Удаление вместе со ссылками: иначе остались бы зависимости
    /// от несуществующего шага
    private func removeStep(_ id: UUID) {
        var updated = current
        updated.removeStep(id: id)
        store.update(updated)
    }

    private func appendSteps(from records: [TrafficRecord]) {
        guard !records.isEmpty else { return }

        var updated = current
        for record in records {
            updated.steps.append(
                FlowStep(
                    name: "\(record.request.method.rawValue) \(record.path)",
                    request: record.request,
                    dependsOn: updated.steps.last.map { [$0.id] } ?? []
                )
            )
        }
        store.update(updated)
    }
}
