import Foundation

/// Фильтр для записей трафика
public struct TrafficFilter: Codable, Sendable {
    // MARK: - Text Search

    /// Поиск по тексту (URL, headers, body)
    public var searchText: String?

    /// Поиск по хосту
    public var host: String?

    /// Поиск по пути
    public var path: String?

    /// Поиск в теле запроса/ответа
    public var bodyContains: String?

    // MARK: - Type Filters

    /// Фильтр по методам
    public var methods: Set<HTTPMethod>?

    /// Фильтр по диапазону статус-кодов
    public var statusCodeRange: ClosedRange<Int>?

    /// Фильтр по категориям статусов
    public var statusCategories: Set<StatusCategory>?

    /// Фильтр по типам контента
    public var contentTypes: Set<ContentTypeFilter>?

    // MARK: - State Filters

    /// Фильтр по состояниям
    public var onlyPending: Bool = false

    /// Только ошибки (4xx/5xx и network errors)
    public var onlyErrors: Bool = false

    /// Только медленные запросы
    public var onlySlowRequests: Bool = false

    /// Порог для медленных запросов (секунды)
    public var slowThreshold: TimeInterval = 3.0

    /// Только из кэша
    public var onlyCached: Bool = false

    // MARK: - Time Filters

    /// Начало периода
    public var from: Date?

    /// Конец периода
    public var to: Date?

    /// Последние N минут
    public var lastMinutes: Int?

    // MARK: - Source Filters

    /// Только first-party (наш бэкенд)
    public var onlyFirstParty: Bool = false

    /// Только third-party
    public var onlyThirdParty: Bool = false

    /// Конкретные хосты
    public var hosts: Set<String>?

    /// Исключить хосты
    public var excludeHosts: Set<String>?

    // MARK: - Sorting

    /// Поле для сортировки
    public var sortBy: SortField = .timestamp

    /// Порядок сортировки
    public var sortOrder: SortOrder = .descending

    // MARK: - Initialization

    public init() {}

    // MARK: - Apply Filter

    /// Применить фильтр к записям
    public func apply(to records: [TrafficRecord]) -> [TrafficRecord] {
        var result = records

        // Text search
        if let searchText = searchText, !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            result = result.filter { record in
                record.url.absoluteString.lowercased().contains(lowercased) ||
                record.request.headers.values.contains { $0.lowercased().contains(lowercased) } ||
                record.request.bodyString?.lowercased().contains(lowercased) == true ||
                record.response?.bodyString?.lowercased().contains(lowercased) == true
            }
        }

        // Host filter
        if let host = host, !host.isEmpty {
            result = result.filter { $0.host.lowercased().contains(host.lowercased()) }
        }

        // Path filter
        if let path = path, !path.isEmpty {
            result = result.filter { $0.path.lowercased().contains(path.lowercased()) }
        }

        // Body contains
        if let bodyContains = bodyContains, !bodyContains.isEmpty {
            let lowercased = bodyContains.lowercased()
            result = result.filter { record in
                record.request.bodyString?.lowercased().contains(lowercased) == true ||
                record.response?.bodyString?.lowercased().contains(lowercased) == true
            }
        }

        // Methods filter
        if let methods = methods, !methods.isEmpty {
            result = result.filter { methods.contains($0.method) }
        }

        // Status code range
        if let range = statusCodeRange {
            result = result.filter { record in
                guard let statusCode = record.statusCode else { return false }
                return range.contains(statusCode)
            }
        }

        // Status categories
        if let categories = statusCategories, !categories.isEmpty {
            result = result.filter { record in
                guard let category = record.statusCategory else { return false }
                return categories.contains(category)
            }
        }

        // Content types
        if let contentTypes = contentTypes, !contentTypes.isEmpty {
            result = result.filter { record in
                guard let contentType = record.response?.contentType else { return false }
                return contentTypes.contains { $0.matches(contentType) }
            }
        }

        // Only pending
        if onlyPending {
            result = result.filter {
                if case .pending = $0.state { return true }
                return false
            }
        }

        // Only errors
        if onlyErrors {
            result = result.filter { $0.isError }
        }

        // Only slow requests
        if onlySlowRequests {
            result = result.filter { $0.duration >= slowThreshold }
        }

        // Only cached
        if onlyCached {
            result = result.filter { $0.response?.isFromCache == true }
        }

        // Time filters
        if let from = from {
            result = result.filter { $0.timestamp >= from }
        }
        if let to = to {
            result = result.filter { $0.timestamp <= to }
        }
        if let minutes = lastMinutes {
            let cutoff = Date().addingTimeInterval(-TimeInterval(minutes * 60))
            result = result.filter { $0.timestamp >= cutoff }
        }

        // Source filters
        if onlyFirstParty {
            result = result.filter { !$0.metadata.isThirdParty }
        }
        if onlyThirdParty {
            result = result.filter { $0.metadata.isThirdParty }
        }

        // Hosts filter
        if let hosts = hosts, !hosts.isEmpty {
            let lowercasedHosts = Set(hosts.map { $0.lowercased() })
            result = result.filter { lowercasedHosts.contains($0.host.lowercased()) }
        }

        // Exclude hosts
        if let excludeHosts = excludeHosts, !excludeHosts.isEmpty {
            let lowercasedHosts = Set(excludeHosts.map { $0.lowercased() })
            result = result.filter { !lowercasedHosts.contains($0.host.lowercased()) }
        }

        // Sorting
        result = sort(result)

        return result
    }

    private func sort(_ records: [TrafficRecord]) -> [TrafficRecord] {
        let sorted: [TrafficRecord]

        switch sortBy {
        case .timestamp:
            sorted = records.sorted { $0.timestamp < $1.timestamp }
        case .duration:
            sorted = records.sorted { $0.duration < $1.duration }
        case .size:
            sorted = records.sorted { $0.responseSize < $1.responseSize }
        case .statusCode:
            sorted = records.sorted { ($0.statusCode ?? 0) < ($1.statusCode ?? 0) }
        case .host:
            sorted = records.sorted { $0.host < $1.host }
        case .method:
            sorted = records.sorted { $0.method.rawValue < $1.method.rawValue }
        }

        return sortOrder == .ascending ? sorted : sorted.reversed()
    }
}

// MARK: - Sort Field

public enum SortField: String, Codable, Sendable, CaseIterable {
    case timestamp
    case duration
    case size
    case statusCode
    case host
    case method

    public var displayName: String {
        switch self {
        case .timestamp: return "Time"
        case .duration: return "Duration"
        case .size: return "Size"
        case .statusCode: return "Status"
        case .host: return "Host"
        case .method: return "Method"
        }
    }
}

// MARK: - Sort Order

public enum SortOrder: String, Codable, Sendable {
    case ascending
    case descending

    public var systemImage: String {
        switch self {
        case .ascending: return "arrow.up"
        case .descending: return "arrow.down"
        }
    }

    public mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

// MARK: - Content Type Filter

public enum ContentTypeFilter: String, Codable, Sendable, CaseIterable {
    case json
    case xml
    case html
    case image
    case text
    case other

    public func matches(_ contentType: ContentType) -> Bool {
        switch self {
        case .json:
            return contentType == .json
        case .xml:
            return contentType == .xml
        case .html:
            return contentType == .html
        case .image:
            if case .image = contentType { return true }
            return false
        case .text:
            return contentType == .plainText
        case .other:
            switch contentType {
            case .json, .xml, .html, .plainText, .image:
                return false
            default:
                return true
            }
        }
    }

    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        case .html: return "HTML"
        case .image: return "Images"
        case .text: return "Text"
        case .other: return "Other"
        }
    }
}

// MARK: - Presets

public extension TrafficFilter {
    /// Все запросы
    static var all: TrafficFilter {
        TrafficFilter()
    }

    /// Только ошибки
    static var errorsOnly: TrafficFilter {
        var filter = TrafficFilter()
        filter.onlyErrors = true
        return filter
    }

    /// Медленные запросы
    static func slowRequests(threshold: TimeInterval = 3.0) -> TrafficFilter {
        var filter = TrafficFilter()
        filter.onlySlowRequests = true
        filter.slowThreshold = threshold
        return filter
    }

    /// Только API запросы (исключает статику)
    static var apiOnly: TrafficFilter {
        var filter = TrafficFilter()
        filter.contentTypes = [.json, .xml]
        return filter
    }

    /// Запросы за последние N минут
    static func recent(minutes: Int) -> TrafficFilter {
        var filter = TrafficFilter()
        filter.lastMinutes = minutes
        return filter
    }

    /// Фильтр по хосту
    static func host(_ host: String) -> TrafficFilter {
        var filter = TrafficFilter()
        filter.host = host
        return filter
    }
}
