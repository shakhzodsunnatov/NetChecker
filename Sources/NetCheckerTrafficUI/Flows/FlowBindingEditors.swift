import SwiftUI
import NetCheckerTrafficCore

/// Что извлечь из ответа шага
struct FlowOutputEditor: View {
    let onSave: (FlowOutput) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable {
        case json = "Поле JSON"
        case header = "Заголовок"
    }

    @State private var name = ""
    @State private var kind: Kind = .json
    @State private var path = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !path.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("token", text: $name)
                    .plainInput()
                    .accessibilityIdentifier("netchecker.outputName")
            } header: {
                Text("Имя значения")
            } footer: {
                Text("Под этим именем значение будет доступно следующим шагам.")
            }

            Section {
                Picker("Откуда", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField(kind == .json ? "data.order.id" : "X-Trace", text: $path)
                    .plainInput()
            } header: {
                Text("Источник")
            } footer: {
                Text(kind == .json
                     ? "Путь по телу ответа, сегменты через точку."
                     : "Имя заголовка ответа.")
            }
        }
        .navigationTitle("Извлечь значение")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") {
                    let trimmedPath = path.trimmingCharacters(in: .whitespaces)
                    onSave(
                        FlowOutput(
                            name: name.trimmingCharacters(in: .whitespaces),
                            source: kind == .json ? .jsonPath(trimmedPath) : .header(trimmedPath)
                        )
                    )
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }
}

/// Куда подставить значение в запрос шага
struct FlowInputEditor: View {
    /// Имена, объявленные предыдущими шагами. Выбор из списка вместо
    /// свободного ввода: опечатка в имени привела бы к падению шага в рантайме
    let availableNames: [String]
    let onSave: (FlowInput) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable {
        case header = "Заголовок"
        case path = "Путь"
        case query = "Параметр"
        case body = "Тело"
    }

    @State private var name: String = ""
    @State private var kind: Kind = .header
    @State private var target = ""

    private var isValid: Bool {
        !name.isEmpty && !target.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Значение") {
                Picker("Значение", selection: $name) {
                    ForEach(availableNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section {
                Picker("Куда", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                TextField(placeholder, text: $target)
                    .plainInput()
            } header: {
                Text("Назначение")
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Подставить значение")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if name.isEmpty { name = availableNames.first ?? "" }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") {
                    let trimmed = target.trimmingCharacters(in: .whitespaces)
                    let destination: FlowValueTarget
                    switch kind {
                    case .header: destination = .header(trimmed)
                    case .path: destination = .pathPlaceholder(trimmed)
                    case .query: destination = .queryItem(trimmed)
                    case .body: destination = .bodyField(trimmed)
                    }
                    onSave(FlowInput(name: name, target: destination))
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }

    private var placeholder: String {
        switch kind {
        case .header: return "Authorization"
        case .path: return "orderId"
        case .query: return "id"
        case .body: return "orderId"
        }
    }

    private var footer: String {
        switch kind {
        case .header: return "Имя заголовка запроса."
        case .path: return "Имя плейсхолдера в URL: /orders/{orderId}/pay."
        case .query: return "Имя query-параметра."
        case .body: return "Поле JSON-тела верхнего уровня."
        }
    }
}

/// Условие выполнения шага
struct FlowConditionEditor: View {
    let availableNames: [String]
    let onSave: (FlowCondition) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var op: FlowConditionOperator = .equals
    @State private var operand = ""

    private var isValid: Bool {
        !name.isEmpty && (!op.needsOperand || !operand.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        Form {
            Section("Значение") {
                Picker("Значение", selection: $name) {
                    ForEach(availableNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Проверка") {
                Picker("Оператор", selection: $op) {
                    ForEach(FlowConditionOperator.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)

                if op.needsOperand {
                    TextField("значение", text: $operand)
                        .plainInput()
                }
            }
        }
        .navigationTitle("Условие")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if name.isEmpty { name = availableNames.first ?? "" }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Готово") {
                    onSave(
                        FlowCondition(
                            valueName: name,
                            operator: op,
                            operand: op.needsOperand ? operand.trimmingCharacters(in: .whitespaces) : nil
                        )
                    )
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }
}

// MARK: - Общее

private extension View {
    /// Технические поля не должны автокапитализироваться и исправляться
    func plainInput() -> some View {
        #if os(iOS)
        return self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        return self.autocorrectionDisabled()
        #endif
    }
}
