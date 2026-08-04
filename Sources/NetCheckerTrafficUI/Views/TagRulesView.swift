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

    @ObservedObject private var archive = TaggedRequestArchive.shared

    /// Теги с количеством помеченных запросов.
    ///
    /// Считаем по архиву: он переживает перезапуск, а живой трафик — нет.
    /// Идентификаторы совпадают, поэтому одна запись не считается дважды.
    private var tags: [(name: String, count: Int)] {
        var byTag: [String: Set<UUID>] = [:]

        for record in store.records {
            for tag in record.metadata.tags {
                byTag[tag, default: []].insert(record.id)
            }
        }
        for archived in archive.requests {
            for tag in archived.tags {
                byTag[tag, default: []].insert(archived.id)
            }
        }

        var counts = byTag.mapValues(\.count)
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

    /// Удалить тег: снять его с живых записей, из архива и забыть имя
    private func deleteTags(at offsets: IndexSet) {
        for index in offsets {
            let name = tags[index].name
            store.removeTag(name, from: store.records.map(\.id))
            archive.removeTag(name)
            tagger.forgetTag(name)
        }
    }
}

// MARK: - Запросы одного тега

/// Список запросов, помеченных конкретным тегом
struct TaggedRequestsView: View {
    let tag: String

    @ObservedObject private var store = TrafficStore.shared
    @ObservedObject private var archive = TaggedRequestArchive.shared

    /// Записи текущей сессии
    private var liveRecords: [TrafficRecord] {
        store.records.filter { $0.metadata.tags.contains(tag) }
    }

    /// Сохранённые с прошлых запусков — те, которых нет среди живых
    private var archivedOnly: [ArchivedRequest] {
        let liveIds = Set(liveRecords.map(\.id))
        return archive.requests(withTag: tag).filter { !liveIds.contains($0.id) }
    }

    var body: some View {
        List {
            if !liveRecords.isEmpty {
                Section {
                    ForEach(liveRecords, id: \.compositeId) { record in
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
                } header: {
                    Text("Текущая сессия")
                }
            }

            if !archivedOnly.isEmpty {
                Section {
                    ForEach(archivedOnly) { archived in
                        ArchivedRequestRow(request: archived)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    archive.remove(id: archived.id)
                                } label: {
                                    Label("Убрать", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("Сохранённые ранее")
                } footer: {
                    Text("Помеченные запросы переживают перезапуск. Тело ответа не сохраняется — запрос остаётся целиком, его можно повторить.")
                }
            }
        }
        // .insetGrouped недоступен на macOS, которую пакет поддерживает
        .overlay {
            if liveRecords.isEmpty && archivedOnly.isEmpty {
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

/// Строка сохранённого запроса — данных меньше, чем у живой записи
struct ArchivedRequestRow: View {
    let request: ArchivedRequest

    var body: some View {
        HStack(spacing: 10) {
            NetCheckerTrafficUI_MethodBadge(method: request.method)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.path)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text(request.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let status = request.statusCode {
                NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
            }
        }
        .padding(.vertical, 2)
    }
}
