import SwiftUI
import NetCheckerTrafficCore

/// Настройка блока: имя, режим, состав и порядок внутри.
///
/// Переключение режима сразу переписывает зависимости участников,
/// поэтому результат виден на полотне без отдельного «применить».
struct FlowGroupEditorView: View {
    let flowId: UUID
    let groupId: UUID

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FlowStore.shared

    @State private var isAddingSteps = false
    @State private var isConfirmingRemoval = false

    private var flow: Flow? { store.flow(id: flowId) }
    private var group: FlowGroup? { flow?.group(id: groupId) }
    private var members: [FlowStep] {
        guard let flow = flow, let group = group else { return [] }
        return flow.steps(in: group)
    }

    var body: some View {
        Group {
            if let group = group {
                form(group)
            } else {
                Text("Блок удалён").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Блок")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
        .sheet(isPresented: $isAddingSteps) {
            NavigationStack {
                FlowStepPickerView { records in
                    addSteps(from: records)
                }
            }
        }
    }

    // MARK: - Форма

    private func form(_ group: FlowGroup) -> some View {
        List {
            Section {
                TextField("Имя блока", text: Binding(
                    get: { group.name },
                    set: { rename($0) }
                ))
                .accessibilityIdentifier("netchecker.groupName")
            } header: {
                Text("Название")
            }

            Section {
                Picker("Режим", selection: Binding(
                    get: { group.kind },
                    set: { setKind($0) }
                )) {
                    ForEach(FlowGroupKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Как выполняется")
            } footer: {
                Text(group.kind.explanation)
            }

            membersSection(group)
            dangerSection(group)
        }
    }

    private func membersSection(_ group: FlowGroup) -> some View {
        Section {
            if members.isEmpty {
                Text("В блоке пока пусто")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(members.enumerated()), id: \.element.id) { offset, step in
                    memberRow(step, position: offset, group: group)
                }
            }

            Button {
                isAddingSteps = true
            } label: {
                Label("Добавить шаги из трафика", systemImage: "plus")
            }
        } header: {
            Text(group.kind == .sequence ? "Порядок внутри" : "Что внутри")
        } footer: {
            Text(group.kind == .sequence
                 ? "Стрелка поднимает шаг выше по очереди."
                 : "Все шаги блока уходят одновременно, порядок значения не имеет.")
        }
    }

    private func memberRow(_ step: FlowStep, position: Int, group: FlowGroup) -> some View {
        HStack(spacing: 10) {
            if group.kind == .sequence {
                Text("\(position + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(group.kind.tint.opacity(0.16))
                    .foregroundStyle(group.kind.tint)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(step.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(step.request.url.host ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if group.kind == .sequence && position > 0 {
                Button {
                    move(step.id, to: position - 1)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Поднять «\(step.name)» выше")
            }

            Button {
                takeOut(step.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Вынуть «\(step.name)» из блока")
        }
    }

    private func dangerSection(_ group: FlowGroup) -> some View {
        Section {
            Button {
                dissolve()
            } label: {
                Label("Распустить блок", systemImage: "rectangle.dashed")
            }

            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Label("Удалить вместе с шагами", systemImage: "trash")
            }
            .confirmationDialog(
                "Удалить блок и \(members.count) шаг(ов)?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) { removeWithSteps() }
                Button("Отмена", role: .cancel) {}
            }
        } footer: {
            Text("Роспуск убирает только рамку: шаги и порядок, который блок расставил, остаются.")
        }
    }

    // MARK: - Действия

    private func rename(_ name: String) {
        guard var flow = flow else { return }
        flow.renameGroup(id: groupId, to: name)
        store.update(flow)
    }

    private func setKind(_ kind: FlowGroupKind) {
        guard var flow = flow else { return }
        flow.setKind(kind, forGroup: groupId)
        store.update(flow)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func move(_ stepId: UUID, to position: Int) {
        guard var flow = flow else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            flow.moveStep(stepId, inGroup: groupId, to: position)
            store.update(flow)
        }
    }

    private func takeOut(_ stepId: UUID) {
        guard var flow = flow else { return }
        withAnimation {
            flow.removeStep(stepId, fromGroup: groupId)
            store.update(flow)
        }
    }

    private func dissolve() {
        guard var flow = flow else { return }
        flow.dissolveGroup(id: groupId)
        store.update(flow)
        dismiss()
    }

    private func removeWithSteps() {
        guard var flow = flow else { return }
        flow.removeGroup(id: groupId)
        store.update(flow)
        dismiss()
    }

    private func addSteps(from records: [TrafficRecord]) {
        guard var flow = flow, !records.isEmpty else { return }

        for record in records {
            let step = FlowStep(
                name: "\(record.request.method.rawValue) \(record.path)",
                request: record.request
            )
            flow.steps.append(step)
            flow.addStep(step.id, toGroup: groupId)
        }
        store.update(flow)
    }
}
