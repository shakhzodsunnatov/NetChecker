import SwiftUI
import NetCheckerTrafficCore

/// Управление правилами пометки трафика.
///
/// Идея: назвать поток — скажем, `NewFeatureFlow` — и перечислить, какие
/// эндпоинты к нему относятся. Дальше список трафика фильтруется по этому
/// имени, вместо того чтобы выискивать нужные вызовы глазами.
public struct NetCheckerTrafficUI_TagRulesView: View {
    @ObservedObject private var tagger = TrafficTagger.shared
    @State private var isAdding = false

    public init() {}

    public var body: some View {
        List {
            if tagger.rules.isEmpty {
                // ContentUnavailableView появился только в iOS 17,
                // а пакет поддерживает iOS 16
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)

                        Text("Нет правил пометки")
                            .font(.headline)

                        Text("Назовите поток и перечислите его эндпоинты — список трафика можно будет свести к одной фиче.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                ForEach(groupedRules, id: \.tag) { group in
                    Section(group.tag) {
                        ForEach(group.rules) { rule in
                            TagRuleRow(rule: rule) { updated in
                                tagger.updateRule(updated)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                tagger.removeRule(id: group.rules[index].id)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    tagger.reapplyToStoredTraffic()
                } label: {
                    Label("Применить к записанному трафику", systemImage: "arrow.clockwise")
                }
                .disabled(tagger.rules.isEmpty)
            } footer: {
                Text("Новые правила помечают только последующие запросы. Эта кнопка проставит теги и на то, что уже записано.")
            }

            if !tagger.rules.isEmpty {
                Section {
                    Button(role: .destructive) {
                        tagger.clearRules()
                    } label: {
                        Label("Удалить все правила", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Flow Tags")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                AddTagRuleView { rule in
                    tagger.addRule(rule)
                }
            }
        }
    }

    private var groupedRules: [(tag: String, rules: [TrafficTagRule])] {
        Dictionary(grouping: tagger.rules, by: \.tag)
            .map { (tag: $0.key, rules: $0.value) }
            .sorted { $0.tag < $1.tag }
    }
}

// MARK: - Строка правила

private struct TagRuleRow: View {
    let rule: TrafficTagRule
    let onToggle: (TrafficTagRule) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.urlPattern)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)

                if let method = rule.method {
                    Text(method.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { isOn in
                    var updated = rule
                    updated.isEnabled = isOn
                    onToggle(updated)
                }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Добавление правила

private struct AddTagRuleView: View {
    let onSave: (TrafficTagRule) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var tagger = TrafficTagger.shared

    @State private var tag = ""
    @State private var urlPattern = ""
    @State private var method: HTTPMethod?

    private var isValid: Bool {
        !tag.trimmingCharacters(in: .whitespaces).isEmpty && !urlPattern.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("NewFeatureFlow", text: $tag)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } header: {
                Text("Имя потока")
            } footer: {
                Text("Все совпавшие запросы получат этот тег и будут фильтроваться вместе.")
            }

            if !tagger.knownTags.isEmpty {
                Section("Существующие потоки") {
                    ForEach(tagger.knownTags, id: \.self) { known in
                        Button(known) { tag = known }
                            .contentShape(Rectangle())
                    }
                }
            }

            Section {
                TextField("*/api/checkout/*", text: $urlPattern)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                Picker("Метод", selection: $method) {
                    Text("Любой").tag(HTTPMethod?.none)
                    ForEach(HTTPMethod.allCases, id: \.rawValue) { item in
                        Text(item.rawValue).tag(HTTPMethod?.some(item))
                    }
                }
            } header: {
                Text("Совпадение")
            } footer: {
                Text("Подстрока URL или шаблон с «*».")
            }
        }
        .navigationTitle("Новый тег")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Добавить") {
                    onSave(
                        TrafficTagRule(
                            tag: tag.trimmingCharacters(in: .whitespaces),
                            urlPattern: urlPattern,
                            method: method
                        )
                    )
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }
}
