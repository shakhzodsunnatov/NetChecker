import SwiftUI
import NetCheckerTrafficCore

/// Экран сценария: свободное полотно с шагами и управление прогоном.
public struct NetCheckerTrafficUI_FlowCanvasView: View {
    let flow: Flow

    @StateObject private var runner = FlowRunner()
    @State private var selectedStep: FlowStep?
    @State private var isAddingSteps = false
    @State private var connecting: FlowConnectTarget?
    @State private var editingGroup: FlowGroupReference?

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var isFullScreen = false
    @State private var namingGroup: FlowGroupKind?
    @State private var groupName = ""

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
            if !isFullScreen {
                runBar
                refusal
            }

            if current.steps.isEmpty {
                emptyState
            } else {
                graph
            }

            if isSelecting {
                selectionBar
            }
        }
        .navigationTitle(current.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(isFullScreen)
        #endif
        .toolbar { toolbarItems }
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
        .sheet(item: $editingGroup) { reference in
            NavigationStack {
                FlowGroupEditorView(flowId: current.id, groupId: reference.id)
            }
        }
        .sheet(isPresented: $isAddingSteps) {
            NavigationStack {
                FlowStepPickerView { records in
                    appendSteps(from: records)
                }
            }
        }
        .alert("Название блока", isPresented: Binding(
            get: { namingGroup != nil },
            set: { if !$0 { namingGroup = nil } }
        )) {
            TextField("Загрузка профиля", text: $groupName)
                .accessibilityIdentifier("netchecker.newGroupName")
            Button("Создать") { createGroup() }
            Button("Отмена", role: .cancel) { namingGroup = nil }
        } message: {
            Text(namingGroup?.explanation ?? "")
        }
    }

    // MARK: - Полотно

    private var graph: some View {
        FlowGraphView(
            flow: current,
            outcomes: runner.outcomes,
            isRunning: runner.isRunning,
            selection: $selection,
            isSelecting: isSelecting,
            isFullScreen: isFullScreen,
            onSelect: { selectedStep = $0 },
            onConnect: { source, target in
                connecting = FlowConnectTarget(sourceId: source, targetId: target)
            },
            onDelete: removeStep,
            onDuplicate: duplicate,
            onOpenGroup: { editingGroup = FlowGroupReference(id: $0.id) },
            onStartSelecting: startSelecting,
            onToggleFullScreen: { isFullScreen.toggle() }
        )
        .overlay(alignment: .topLeading) {
            if isFullScreen { fullScreenBar }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isSelecting {
                Button("Готово") { stopSelecting() }
            } else {
                Button {
                    isAddingSteps = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("netchecker.addFlowStep")

                Menu {
                    Button {
                        startSelecting(nil)
                    } label: {
                        Label("Выбрать шаги", systemImage: "checkmark.circle")
                    }
                    .disabled(current.steps.isEmpty)

                    Button {
                        SharePresenter.present(items: [FlowExporter.export(current)])
                    } label: {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                    .disabled(current.steps.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("netchecker.flowMenu")
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
                    Text(progressText)
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

    /// Сколько шагов уже отработало: «выполняется…» ничего не говорит
    /// о том, застрял прогон или идёт
    private var progressText: String {
        let done = runner.outcomes.values.filter { $0.state.isFinished }.count
        return "Выполняется… \(done) из \(current.steps.count)"
    }

    @ViewBuilder
    private var refusal: some View {
        if let reason = runner.refusalReason {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
        }
    }

    /// В полноэкранном режиме панели нет — запуск и выход остаются плавающими
    private var fullScreenBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) {
                    isFullScreen = false
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Выйти из полноэкранного режима")

            Button {
                Task { await runner.run(current) }
            } label: {
                HStack(spacing: 5) {
                    if runner.isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(runner.isRunning ? progressText : "Запустить")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(runner.isRunning)
        }
        .padding(12)
    }

    // MARK: - Выделение

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "Отметьте шаги" : "Выбрано \(selection.count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selection.isEmpty ? .secondary : .primary)

            Spacer()

            Menu {
                ForEach(FlowGroupKind.allCases, id: \.self) { kind in
                    Button {
                        groupName = suggestedGroupName(for: kind)
                        namingGroup = kind
                    } label: {
                        Label(kind.title, systemImage: kind.systemImage)
                    }
                }
            } label: {
                Label("В блок", systemImage: "square.dashed.inset.filled")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(selection.count < 2)
            .accessibilityIdentifier("netchecker.groupSelection")

            Button {
                duplicateSelection()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .disabled(selection.isEmpty)
            .accessibilityLabel("Дублировать выбранные")

            Button(role: .destructive) {
                deleteSelection()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(selection.isEmpty ? Color.secondary : Color.red)
            }
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("netchecker.deleteSelection")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startSelecting(_ stepId: UUID?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isSelecting = true
            selection = stepId.map { [$0] } ?? []
        }
    }

    private func stopSelecting() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isSelecting = false
            selection = []
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

    // MARK: - Изменение сценария

    /// Удаление вместе со ссылками: иначе остались бы зависимости
    /// от несуществующего шага
    private func removeStep(_ id: UUID) {
        var updated = current
        updated.removeStep(id: id)
        store.update(updated)
    }

    private func deleteSelection() {
        var updated = current
        updated.removeSteps(ids: selection)
        store.update(updated)
        stopSelecting()
    }

    private func duplicate(_ id: UUID) {
        var updated = current
        updated.duplicateStep(id: id)
        store.update(updated)
    }

    private func duplicateSelection() {
        var updated = current
        for id in selection { updated.duplicateStep(id: id) }
        store.update(updated)
        stopSelecting()
    }

    private func createGroup() {
        guard let kind = namingGroup, selection.count >= 2 else {
            namingGroup = nil
            return
        }

        var updated = current
        let name = groupName.trimmingCharacters(in: .whitespaces)
        let group = updated.addGroup(
            name: name.isEmpty ? kind.title : name,
            kind: kind
        )

        // Порядок в сценарии задаёт порядок внутри блока: для очереди
        // он важен, а произвольный порядок множества был бы случайным
        for step in updated.steps where selection.contains(step.id) {
            updated.addStep(step.id, toGroup: group.id)
        }

        store.update(updated)
        namingGroup = nil
        stopSelecting()
    }

    /// Имя не повторяет режим: он и так подписан рядом на полотне
    private func suggestedGroupName(for kind: FlowGroupKind) -> String {
        let taken = Set(current.groups.map(\.name))
        return Flow.uniqueName(for: "Блок", avoiding: taken)
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

/// Обёртка для `.sheet(item:)`: навешивать Identifiable на UUID нельзя —
/// однажды это сделает сам Foundation
struct FlowGroupReference: Identifiable {
    let id: UUID
}
