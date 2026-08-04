import SwiftUI
import NetCheckerTrafficCore

/// Теги и помеченные ими запросы.
///
/// Экран отвечает на вопрос «что я пометил как NewFeatureFlow», а не
/// «по какому паттерну помечать будущие запросы»: помечают вручную из списка
/// трафика, поэтому смотреть здесь нужно результат, а не правила.
public struct NetCheckerTrafficUI_TagRulesView: View {
    @ObservedObject private var store = TrafficStore.shared
    @ObservedObject private var tagger = TrafficTagger.shared

    public init() {}

    /// Теги с количеством помеченных запросов
    private var tags: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in store.records {
            for tag in record.metadata.tags {
                counts[tag, default: 0] += 1
            }
        }

        // Имена без записей тоже показываем — тег мог остаться после очистки
        for name in tagger.knownTags where counts[name] == nil {
            counts[name] = 0
        }

        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.name < $1.name }
    }

    public var body: some View {
        List {
            if tags.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    ForEach(tags, id: \.name) { tag in
                        NavigationLink {
                            TaggedRequestsView(tag: tag.name)
                        } label: {
                            HStack {
                                Label(tag.name, systemImage: "tag.fill")
                                Spacer()
                                Text("\(tag.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteTags)
                } header: {
                    Text("Теги")
                } footer: {
                    Text("Пометить запросы можно долгим нажатием в списке трафика или через «Пометить несколько».")
                }
            }
        }
        .navigationTitle("Flow Tags")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Пока ничего не помечено")
                .font(.headline)

            Text("В списке трафика задержите палец на запросе, чтобы навесить тег, или выберите «Пометить несколько» для группы.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Удалить тег: снять его со всех записей и забыть имя
    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            let name = tags[index].name
            store.removeTag(name, from: store.records.map(\.id))
            tagger.forgetTag(name)
        }
    }
}

// MARK: - Запросы одного тега

/// Список запросов, помеченных конкретным тегом
struct TaggedRequestsView: View {
    let tag: String

    @ObservedObject private var store = TrafficStore.shared

    private var records: [TrafficRecord] {
        store.records.filter { $0.metadata.tags.contains(tag) }
    }

    var body: some View {
        List {
            ForEach(records, id: \.compositeId) { record in
                NavigationLink {
                    NetCheckerTrafficUI_TrafficDetailView(record: record)
                } label: {
                    TrafficRecordRow(record: record)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.removeTag(tag, from: [record.id])
                    } label: {
                        Label("Снять тег", systemImage: "tag.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if records.isEmpty {
                Text("Нет запросов с этим тегом")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(tag)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
