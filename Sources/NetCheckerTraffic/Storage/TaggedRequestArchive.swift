import Foundation

/// Сохранённый помеченный запрос.
///
/// Хранит запрос целиком — его должно хватать, чтобы повторить вызов
/// или собрать из него сценарий. Тело ответа не сохраняется: это самая
/// объёмная часть, а для повтора она не нужна.
public struct ArchivedRequest: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let method: HTTPMethod
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
    public let statusCode: Int?
    public var tags: [String]

    public var host: String { url.host ?? "" }
    public var path: String { url.path.isEmpty ? "/" : url.path }

    /// Восстановить данные запроса для повтора или сценария
    public var requestData: RequestData {
        RequestData(url: url, method: method, headers: headers, body: body)
    }

    init(record: TrafficRecord, maxBodySize: Int) {
        self.id = record.id
        self.timestamp = record.timestamp
        self.method = record.request.method
        self.url = record.request.url
        self.headers = record.request.headers
        self.statusCode = record.statusCode
        self.tags = record.metadata.tags

        // Огромное тело незачем таскать между запусками
        if let body = record.request.body, body.count <= maxBodySize {
            self.body = body
        } else {
            self.body = nil
        }
    }
}

/// Хранилище помеченных запросов, переживающих перезапуск приложения.
///
/// Обычный трафик живёт только в памяти — это правильно, его много и он
/// быстро теряет ценность. Но пометив запрос, пользователь сказал «этот важен»:
/// после перезапуска экран тега оказывался пустым, а собрать из помеченного
/// сценарий было уже нельзя.
@MainActor
public final class TaggedRequestArchive: ObservableObject {
    public static let shared = TaggedRequestArchive()

    /// Сохранённые запросы, новые в начале
    @Published public private(set) var requests: [ArchivedRequest] = [] {
        didSet { persist() }
    }

    /// Предел числа сохранённых запросов
    public var maxRequests = 300

    /// Предел размера тела запроса
    public var maxBodySize = 64 * 1024

    private let storageKey = "NetCheckerTaggedRequests"

    private init() {
        load()
    }

    // MARK: - Доступ

    public func requests(withTag tag: String) -> [ArchivedRequest] {
        requests.filter { $0.tags.contains(tag) }
    }

    public func request(id: UUID) -> ArchivedRequest? {
        requests.first { $0.id == id }
    }

    public var usedTags: [String] {
        Array(Set(requests.flatMap(\.tags))).sorted()
    }

    // MARK: - Изменение

    /// Сохранить или обновить запись после пометки
    public func store(_ record: TrafficRecord) {
        guard !record.metadata.tags.isEmpty else {
            remove(id: record.id)
            return
        }

        let archived = ArchivedRequest(record: record, maxBodySize: maxBodySize)

        if let index = requests.firstIndex(where: { $0.id == record.id }) {
            requests[index] = archived
        } else {
            requests.insert(archived, at: 0)
            if requests.count > maxRequests {
                requests.removeLast(requests.count - maxRequests)
            }
        }
    }

    /// Снять тег со всех сохранённых записей
    public func removeTag(_ tag: String) {
        for index in requests.indices {
            requests[index].tags.removeAll { $0 == tag }
        }
        // Запись без тегов больше незачем хранить
        requests.removeAll { $0.tags.isEmpty }
    }

    public func remove(id: UUID) {
        requests.removeAll { $0.id == id }
    }

    public func clear() {
        requests.removeAll()
    }

    // MARK: - Персистентность

    private func persist() {
        guard let data = try? JSONEncoder().encode(requests) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([ArchivedRequest].self, from: data) else {
            return
        }
        requests = stored
    }
}
