import SwiftUI
import NetCheckerTrafficCore

/// Граф сценария по уровням и управление прогоном.
///
/// Строка — уровень выполнения: всё в ней идёт одновременно, поэтому
/// параллельность видна без подписей. Уровни вычисляются из связей,
/// раскладку не задают руками, и прокрутка остаётся только вертикальной.
public struct NetCheckerTrafficUI_FlowCanvasView: View {
    let flow: Flow

    @StateObject private var runner = FlowRunner()
    @State private var selectedStep: FlowStep?
    @State private var isAddingSteps = false

    @ObservedObject private var store = FlowStore.shared

    public init(flow: Flow) {
        self.flow = flow
    }

    /// Актуальная версия сценария: шаги могут добавляться во время работы
    private var current: Flow {
        store.flow(id: flow.id) ?? flow
    }

    private var levels: [[FlowStep]] { current.levels() }

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
                graph
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
                    step: step,
                    outcome: runner.outcomes[step.id],
                    onRetry: { Task { await runner.retry(from: step.id, in: current) } },
                    onSkip: { Task { await runner.skip(step.id, in: current) } }
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

    // MARK: - Граф

    private var graph: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    if index > 0 {
                        FlowEdgeView(labels: valueLabels(into: level), state: edgeState(for: level))
                    }
                    levelRow(level, startingIndex: startIndex(of: index))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
    }

    /// Больше двух узлов не помещаются в ширину телефона, поэтому такая
    /// строка прокручивается вбок сама по себе — остальной экран неподвижен
    @ViewBuilder
    private func levelRow(_ level: [FlowStep], startingIndex: Int) -> some View {
        if level.count > 2 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    nodes(level, startingIndex: startingIndex, fixedWidth: 158)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                nodes(level, startingIndex: startingIndex, fixedWidth: nil)
            }
        }
    }

    private func nodes(_ level: [FlowStep], startingIndex: Int, fixedWidth: CGFloat?) -> some View {
        ForEach(Array(level.enumerated()), id: \.element.id) { offset, step in
            FlowNodeView(
                step: step,
                outcome: runner.outcomes[step.id],
                index: startingIndex + offset + 1,
                isFireAndForget: current.isFireAndForget(step),
                incomingValues: distantInputs(for: step)
            )
            .frame(width: fixedWidth)
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .onTapGesture { selectedStep = step }
        }
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

    // MARK: - Вспомогательное

    private func startIndex(of levelIndex: Int) -> Int {
        levels.prefix(levelIndex).reduce(0) { $0 + $1.count }
    }

    /// Значения, приходящие не с соседнего уровня — показываются строкой в узле
    private func distantInputs(for step: FlowStep) -> [String] {
        guard let levelIndex = levels.firstIndex(where: { level in
            level.contains { $0.id == step.id }
        }), levelIndex > 0 else { return [] }

        let adjacent = Set(levels[levelIndex - 1].map(\.id))
        let distant = step.dependsOn.filter { !adjacent.contains($0) && current.step(id: $0) != nil }
        guard !distant.isEmpty else { return [] }

        return step.inputs.map(\.name)
    }

    private func valueLabels(into level: [FlowStep]) -> [String] {
        Array(Set(level.flatMap { $0.inputs.map(\.name) })).sorted()
    }

    private func edgeState(for level: [FlowStep]) -> FlowEdgeState {
        let states = level.compactMap { runner.outcomes[$0.id]?.state }

        if states.contains(where: { if case .failed = $0 { return true } else { return false } }) {
            return .failed
        }
        if states.contains(.notRun) { return .notRun }
        if states.contains(.succeeded) { return .active }
        return .idle
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
