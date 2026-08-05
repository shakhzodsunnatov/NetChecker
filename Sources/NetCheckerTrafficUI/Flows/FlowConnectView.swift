import SwiftUI
import NetCheckerTrafficCore

/// Прямое соединение значения с местом в следующем запросе.
///
/// Раньше связь настраивалась двумя формами в разных экранах, и ни в одной
/// не было видно, что с чем соединяется. Здесь ответ одного шага и запрос
/// другого лежат рядом: нажали значение сверху, нажали место снизу —
/// между ними протянулся провод.
struct FlowConnectView: View {
    let flowId: UUID
    let sourceStepId: UUID
    let targetStepId: UUID
    let sourceResponse: ResponseData?

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FlowStore.shared

    @State private var pickedField: FlowJSONField?
    @State private var justConnected: String?
    @Namespace private var wire

    private var flow: Flow? { store.flow(id: flowId) }
    private var source: FlowStep? { flow?.step(id: sourceStepId) }
    private var target: FlowStep? { flow?.step(id: targetStepId) }

    private var fields: [FlowJSONField] {
        FlowJSONFields.fields(in: sourceResponse?.body).filter(FlowJSONFields.isSelectable)
    }

    private var slots: [FlowRequestSlot] {
        target.map { FlowRequestSlots.slots(in: $0.request) } ?? []
    }

    /// Значение, которое уже кладётся в это место запроса
    private func boundValue(for slot: FlowRequestSlot) -> String? {
        target?.inputs.first { $0.target == slot.target }?.name
    }

    private func subtitle(for slot: FlowRequestSlot, bound: String?) -> String {
        if let bound = bound {
            return "\(slot.kindTitle) · сюда идёт «\(bound)»"
        }
        if let value = slot.currentValue {
            return "\(slot.kindTitle) · сейчас \(value)"
        }
        return slot.kindTitle
    }

    /// Уже настроенные связи между этой парой шагов
    private var existing: [(value: String, slot: String)] {
        guard let target = target, let source = source else { return [] }
        let published = Set(source.outputs.map(\.name))

        return target.inputs
            .filter { published.contains($0.name) }
            .map { ($0.name, $0.target.summary) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                instruction

                sourcePane
                bridge
                targetPane

                if !existing.isEmpty {
                    existingSection
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color.secondary.opacity(0.06))
        .navigationTitle("Связать значения")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }
            }
        }
    }

    // MARK: - Подсказка

    private var instruction: some View {
        VStack(spacing: 4) {
            Text(pickedField == nil
                 ? "Нажмите значение из ответа"
                 : "Теперь выберите, куда его положить")
                .font(.subheadline.weight(.semibold))

            Text(pickedField == nil
                 ? "Ниже — то, что вернул шаг «\(source?.name ?? "")»"
                 : "«\(pickedField?.suggestedName ?? "")» = \(pickedField?.value ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: pickedField)
    }

    // MARK: - Ответ

    private var sourcePane: some View {
        paneCard(
            title: source?.name ?? "Шаг",
            subtitle: "что вернул",
            icon: "arrow.down.circle.fill",
            tint: .green
        ) {
            if sourceResponse == nil {
                hint("Шаг ещё не выполнялся. Запустите сценарий — здесь появится настоящий ответ.")
            } else if fields.isEmpty {
                hint("В ответе нет подходящих полей.")
            } else {
                ForEach(fields) { field in
                    valueRow(field)
                }
            }
        }
    }

    private func valueRow(_ field: FlowJSONField) -> some View {
        let isPicked = pickedField?.path == field.path

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                pickedField = isPicked ? nil : field
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPicked ? "circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isPicked ? Color.accentColor : Color.secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(field.suggestedName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(field.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(isPicked ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Мост между панелями

    private var bridge: some View {
        ZStack {
            // Провод «живой» только когда значение выбрано — иначе он
            // обещал бы связь, которой ещё нет
            Rectangle()
                .fill(pickedField == nil
                      ? Color.secondary.opacity(0.25)
                      : Color.accentColor)
                .frame(width: 2)

            if let picked = pickedField {
                Text(picked.suggestedName)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .matchedGeometryEffect(id: "wire", in: wire)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .frame(height: 44)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: pickedField)
    }

    // MARK: - Запрос

    private var targetPane: some View {
        paneCard(
            title: target?.name ?? "Шаг",
            subtitle: "куда положить",
            icon: "arrow.up.circle.fill",
            tint: .accentColor
        ) {
            if slots.isEmpty {
                hint("В этом запросе некуда подставлять.")
            } else {
                ForEach(slots) { slot in
                    slotRow(slot)
                }
            }
        }
        .opacity(pickedField == nil ? 0.55 : 1)
        .animation(.easeOut(duration: 0.2), value: pickedField)
    }

    private func slotRow(_ slot: FlowRequestSlot) -> some View {
        let isEnabled = pickedField != nil
        let isFresh = justConnected == slot.id
        let bound = boundValue(for: slot)

        return Button {
            connect(to: slot)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isFresh
                      ? "checkmark.circle.fill"
                      : (bound != nil ? "link.circle.fill" : slot.systemImage))
                    .font(.system(size: 13))
                    .foregroundStyle(isFresh ? Color.green : (bound != nil ? Color.accentColor : Color.secondary))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(subtitle(for: slot, bound: bound))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isEnabled {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(isFresh ? Color.green.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: - Уже связанное

    private var existingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("УЖЕ СВЯЗАНО")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            ForEach(existing, id: \.value) { item in
                HStack(spacing: 8) {
                    Text(item.value)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Text(item.slot)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        disconnect(item.value)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 14)
        .padding(.top, 18)
    }

    // MARK: - Общее оформление

    private func paneCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            content()
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: - Действия

    private func connect(to slot: FlowRequestSlot) {
        guard let picked = pickedField,
              var flow = flow,
              var source = source,
              var target = target else { return }

        let name = uniqueName(for: picked.suggestedName, in: flow)

        // В одно место запроса кладётся одно значение. Без этого две
        // подстановки в один и тот же плейсхолдер тихо перетирали бы
        // друг друга, и на полотне висели бы два провода вместо одного
        target.inputs.removeAll { $0.target == slot.target }

        // Значение объявляется у источника и подставляется у получателя —
        // одним действием, чтобы связь не приходилось собирать из двух мест
        source.outputs.append(FlowOutput(name: name, source: .jsonPath(picked.path)))
        target.inputs.append(FlowInput(name: name, target: slot.target))

        // Зависимость появляется сама: без неё значение не успеет появиться
        if !target.dependsOn.contains(source.id) {
            target.dependsOn.append(source.id)
        }

        flow.update(source)
        flow.update(target)
        store.update(flow)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
            justConnected = slot.id
            pickedField = nil
        }

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        // Отметка о свежей связи гаснет сама
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { justConnected = nil }
        }
    }

    private func disconnect(_ name: String) {
        guard var flow = flow, var source = source, var target = target else { return }

        source.outputs.removeAll { $0.name == name }
        target.inputs.removeAll { $0.name == name }

        flow.update(source)
        flow.update(target)
        store.update(flow)
    }

    /// Имя должно быть уникальным: два значения с одним именем
    /// перетирали бы друг друга в контексте прогона
    private func uniqueName(for base: String, in flow: Flow) -> String {
        let taken = Set(flow.steps.flatMap { $0.outputs.map(\.name) })
        guard taken.contains(base) else { return base }

        var index = 2
        while taken.contains("\(base)\(index)") { index += 1 }
        return "\(base)\(index)"
    }
}
