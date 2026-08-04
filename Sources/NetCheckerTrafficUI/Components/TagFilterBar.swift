import SwiftUI
import NetCheckerTrafficCore

/// Полоса тегов над списком трафика.
///
/// Один тап — список сводится к помеченным запросам, повторный — снимает
/// фильтр. Показываются только теги, которые реально встречаются в записях,
/// иначе полоса быстро зарастает мусором.
struct TagFilterBar: View {
    @Binding var selected: Set<String>
    let tags: [String]
    let counts: [String: Int]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(
                            title: tag,
                            count: counts[tag] ?? 0,
                            isSelected: selected.contains(tag)
                        ) {
                            toggle(tag)
                        }
                    }

                    if !selected.isEmpty {
                        Button {
                            selected.removeAll()
                        } label: {
                            Label("Сбросить", systemImage: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) {
            selected.remove(tag)
        } else {
            selected.insert(tag)
        }
    }
}

/// Чип тега с количеством помеченных запросов
struct TagChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Меню пометки: существующие теги плюс создание нового
struct TagAssignmentMenu: View {
    let ids: Set<UUID>
    let onCreateNew: () -> Void

    @ObservedObject private var store = TrafficStore.shared
    @ObservedObject private var tagger = TrafficTagger.shared

    init(ids: Set<UUID>, onCreateNew: @escaping () -> Void) {
        self.ids = ids
        self.onCreateNew = onCreateNew
    }

    var body: some View {
        ForEach(tagger.knownTags, id: \.self) { tag in
            Button {
                if store.allRecords(ids, haveTag: tag) {
                    store.removeTag(tag, from: ids)
                } else {
                    store.addTag(tag, to: ids)
                }
            } label: {
                Label(
                    tag,
                    systemImage: store.allRecords(ids, haveTag: tag) ? "checkmark.circle.fill" : "circle"
                )
            }
        }

        if !tagger.knownTags.isEmpty {
            Divider()
        }

        Button {
            onCreateNew()
        } label: {
            Label("Новый тег…", systemImage: "plus")
        }
    }
}

/// Обёртка для `.sheet(item:)`: набор идентификаторов сам по себе
/// не является `Identifiable`
struct TagTarget: Identifiable {
    let ids: Set<UUID>
    var id: String { ids.map(\.uuidString).sorted().joined() }

    init(_ ids: Set<UUID>) {
        self.ids = ids
    }
}

/// Диалог создания тега при пометке
struct NewTagSheet: View {
    let ids: Set<UUID>
    let onDone: () -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("NewFeatureFlow", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                } header: {
                    Text("Имя тега")
                } footer: {
                    Text("Тег получат \(ids.count) \(Self.requestWord(ids.count)). Имя сохранится и будет предлагаться дальше.")
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
                    Button("Пометить") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        TrafficTagger.shared.registerTag(trimmed)
                        TrafficStore.shared.addTag(trimmed, to: ids)
                        onDone()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private static func requestWord(_ count: Int) -> String {
        let remainder10 = count % 10
        let remainder100 = count % 100

        if remainder10 == 1 && remainder100 != 11 { return "запрос" }
        if (2...4).contains(remainder10) && !(12...14).contains(remainder100) { return "запроса" }
        return "запросов"
    }
}
