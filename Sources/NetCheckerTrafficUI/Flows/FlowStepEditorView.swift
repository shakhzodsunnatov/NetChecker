import SwiftUI
import NetCheckerTrafficCore

/// Настройка шага: зависимости, условие, передача значений, проверка.
///
/// Здесь же задаются параллельность и развилки: порядок определяется
/// зависимостями, отдельного переключателя режима нет.
struct FlowStepEditorView: View {
    let flowId: UUID
    let stepId: UUID

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FlowStore.shared

    @State private var isAddingOutput = false
    @State private var isAddingInput = false

    private var flow: Flow? { store.flow(id: flowId) }
    private var step: FlowStep? { flow?.step(id: stepId) }

    var body: some View {
        Group {
            if let flow = flow, let step = step {
                form(flow: flow, step: step)
            } else {
                Text("Шаг удалён").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройка шага")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    // MARK: - Форма

    private func form(flow: Flow, step: FlowStep) -> some View {
        List {
            dependenciesSection(flow: flow, step: step)
            conditionSection(flow: flow, step: step)
            outputsSection(step: step)
            inputsSection(flow: flow, step: step)
            checksSection(step: step)
        }
        .sheet(isPresented: $isAddingOutput) {
            NavigationStack {
                FlowOutputEditor { output in
                    var updated = step
                    updated.outputs.append(output)
                    save(updated)
                }
            }
        }
        .sheet(isPresented: $isAddingInput) {
            NavigationStack {
                FlowInputEditor(availableNames: flow.availableValueNames(before: step.id)) { input in
                    var updated = step
                    updated.inputs.append(input)
                    save(updated)
                }
            }
        }
    }

    private func dependenciesSection(flow: Flow, step: FlowStep) -> some View {
        Section {
            let candidates = flow.possibleDependencies(for: step.id)

            if candidates.isEmpty {
                Text("Раньше этого шага ничего нет")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates) { candidate in
                    Button {
                        toggleDependency(candidate.id, on: step)
                    } label: {
                        HStack {
                            Image(systemName: step.dependsOn.contains(candidate.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.dependsOn.contains(candidate.id)
                                                 ? Color.accentColor : .secondary)
                            Text(candidate.name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Ждать завершения")
        } footer: {
            Text(step.dependsOn.isEmpty
                 ? "Ничего не отмечено — шаг стартует сразу, одновременно с такими же."
                 : "Шаг запустится, когда завершатся все отмеченные.")
        }
    }

    private func conditionSection(flow: Flow, step: FlowStep) -> some View {
        Section {
            if let condition = step.condition {
                LabeledContent("Условие", value: condition.summary)
                Button(role: .destructive) {
                    var updated = step
                    updated.condition = nil
                    save(updated)
                } label: {
                    Label("Убрать условие", systemImage: "minus.circle")
                }
            } else {
                NavigationLink {
                    FlowConditionEditor(availableNames: flow.availableValueNames(before: step.id)) { condition in
                        var updated = step
                        updated.condition = condition
                        save(updated)
                    }
                } label: {
                    Label("Добавить условие", systemImage: "arrow.triangle.branch")
                }
                .disabled(flow.availableValueNames(before: step.id).isEmpty)
            }
        } header: {
            Text("Условие")
        } footer: {
            Text("Ложное условие пропускает шаг — это не ошибка. Два шага от одного родителя с противоположными условиями дают развилку.")
        }
    }

    private func outputsSection(step: FlowStep) -> some View {
        Section {
            ForEach(step.outputs) { output in
                LabeledContent(output.name, value: output.source.summary)
                    .font(.callout)
            }
            .onDelete { offsets in
                var updated = step
                updated.outputs.remove(atOffsets: offsets)
                save(updated)
            }

            Button {
                isAddingOutput = true
            } label: {
                Label("Извлечь значение", systemImage: "plus")
            }
        } header: {
            Text("Из ответа")
        } footer: {
            Text("Значения станут доступны следующим шагам под этими именами.")
        }
    }

    private func inputsSection(flow: Flow, step: FlowStep) -> some View {
        Section {
            ForEach(step.inputs) { input in
                LabeledContent(input.name, value: input.target.summary)
                    .font(.callout)
            }
            .onDelete { offsets in
                var updated = step
                updated.inputs.remove(atOffsets: offsets)
                save(updated)
            }

            Button {
                isAddingInput = true
            } label: {
                Label("Подставить значение", systemImage: "plus")
            }
            .disabled(flow.availableValueNames(before: step.id).isEmpty)
        } header: {
            Text("В запрос")
        } footer: {
            Text(flow.availableValueNames(before: step.id).isEmpty
                 ? "Подставлять нечего: предыдущие шаги ничего не извлекают."
                 : "Если значения не окажется в ответе, шаг упадёт с его именем — вместо пустой подстановки.")
        }
    }

    private func checksSection(step: FlowStep) -> some View {
        Section {
            Toggle("Проверять статус", isOn: Binding(
                get: { step.expectedStatusCode != nil },
                set: { isOn in
                    var updated = step
                    updated.expectedStatusCode = isOn ? 200 : nil
                    save(updated)
                }
            ))

            if let expected = step.expectedStatusCode {
                Stepper("Ожидаю \(expected)", value: Binding(
                    get: { expected },
                    set: { value in
                        var updated = step
                        updated.expectedStatusCode = value
                        save(updated)
                    }
                ), in: 100...599)
            }

            Stepper(step.delay > 0 ? "Пауза \(Int(step.delay)) с" : "Без паузы", value: Binding(
                get: { Int(step.delay) },
                set: { value in
                    var updated = step
                    updated.delay = TimeInterval(value)
                    save(updated)
                }
            ), in: 0...60)
        } header: {
            Text("Проверка и пауза")
        } footer: {
            Text("Пауза нужна бэкендам, которым требуется время на обработку предыдущего шага.")
        }
    }

    // MARK: - Сохранение

    private func toggleDependency(_ id: UUID, on step: FlowStep) {
        var updated = step
        if let index = updated.dependsOn.firstIndex(of: id) {
            updated.dependsOn.remove(at: index)
        } else {
            updated.dependsOn.append(id)
        }
        save(updated)
    }

    private func save(_ step: FlowStep) {
        guard var flow = flow else { return }
        flow.update(step)
        store.update(flow)
    }
}
