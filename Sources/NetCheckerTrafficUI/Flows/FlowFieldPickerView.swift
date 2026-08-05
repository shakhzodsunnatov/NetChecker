import SwiftUI
import NetCheckerTrafficCore

/// Выбор поля из настоящего ответа шага.
///
/// Раньше путь вводился руками, и опечатка всплывала только падением шага
/// в прогоне. Здесь видно, что реально пришло, и промахнуться нечем.
struct FlowResponseFieldPicker: View {
    let response: ResponseData?
    let onPick: (FlowJSONField) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    private var fields: [FlowJSONField] {
        FlowJSONFields.fields(in: response?.body).filter(FlowJSONFields.isSelectable)
    }

    var body: some View {
        Group {
            if response == nil {
                notRunYet
            } else if fields.isEmpty {
                noFields
            } else {
                list
            }
        }
        .navigationTitle("Выбрать значение")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(fields) { field in
                    Button {
                        onPick(field)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.path)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(.primary)

                                Text(field.value)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Поля ответа")
            } footer: {
                Text("Нажмите на поле — оно станет значением, доступным следующим шагам.")
            }
        }
    }

    private var notRunYet: some View {
        FlowHintView(
            icon: "play.circle",
            title: "Сценарий ещё не запускался",
            message: "Запустите его один раз — тогда здесь появятся поля настоящего ответа, и значение можно будет выбрать, а не вводить путём."
        )
    }

    private var noFields: some View {
        FlowHintView(
            icon: "doc",
            title: "В ответе нет полей JSON",
            message: "Тело ответа пустое или это не JSON. Значение можно взять из заголовка ответа."
        )
    }
}

/// Выбор поля тела запроса — куда подставлять значение
struct FlowRequestFieldPicker: View {
    let request: RequestData?
    let onPick: (String) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss

    private var keys: [String] {
        FlowJSONFields.topLevelKeys(in: request?.body)
    }

    var body: some View {
        Group {
            if keys.isEmpty {
                FlowHintView(
                    icon: "curlybraces",
                    title: "В теле запроса нет полей",
                    message: "Тело пустое или это не JSON. Значение можно подставить в заголовок, путь или query-параметр."
                )
            } else {
                List {
                    Section("Поля тела запроса") {
                        ForEach(keys, id: \.self) { key in
                            Button {
                                onPick(key)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(key)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Куда подставить")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
    }
}

/// Пояснение вместо пустого экрана
struct FlowHintView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
