import Foundation

/// Состояние записи трафика
public enum TrafficRecordState: Codable, Sendable, Hashable {
    case pending
    case completed
    case failed(TrafficError)
    case cancelled
    case mocked

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .mocked: return "Mocked"
        }
    }

    public var systemImage: String {
        switch self {
        case .pending: return "clock"
        case .completed: return "checkmark.circle"
        case .failed: return "xmark.circle"
        case .cancelled: return "nosign"
        case .mocked: return "theatermasks"
        }
    }

    public var isFinished: Bool {
        switch self {
        case .pending:
            return false
        case .completed, .failed, .cancelled, .mocked:
            return true
        }
    }
}

/// Полная запись сетевого запроса
public struct TrafficRecord: Codable, Sendable, Identifiable, Hashable {
    // MARK: - Identity

    /// Уникальный идентификатор
    public let id: UUID

    /// Временная метка начала запроса
    public let timestamp: Date

    // MARK: - State

    /// Общая длительность запроса
    public var duration: TimeInterval

    /// Состояние записи
    public var state: TrafficRecordState

    // MARK: - Request/Response

    /// Данные запроса
    public let request: RequestData

    /// Данные ответа (nil если pending/failed)
    public var response: ResponseData?

    // MARK: - Timing & Security

    /// Детальные тайминги
    public var timings: RequestTimings?

    /// Информация о безопасности
    public var security: SecurityInfo?

    // MARK: - Error & Metadata

    /// Ошибка (если state == .failed)
    public var error: TrafficError?

    /// Метаданные
    public var metadata: TrafficMetadata

    /// История редиректов
    public var redirects: [RedirectHop]

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        duration: TimeInterval = 0,
        state: TrafficRecordState = .pending,
        request: RequestData,
        response: ResponseData? = nil,
        timings: RequestTimings? = nil,
        security: SecurityInfo? = nil,
        error: TrafficError? = nil,
        metadata: TrafficMetadata? = nil,
        redirects: [RedirectHop] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.state = state
        self.request = request
        self.response = response
        self.timings = timings
        self.security = security
        self.error = error
        self.metadata = metadata ?? TrafficMetadata(from: request.url)
        self.redirects = redirects
    }

    /// Создать из URLRequest
    public init(from urlRequest: URLRequest) {
        self.id = UUID()
        self.timestamp = Date()
        self.duration = 0
        self.state = .pending
        self.request = RequestData(from: urlRequest)
        self.response = nil
        self.timings = nil
        self.security = nil
        self.error = nil
        self.metadata = TrafficMetadata(from: urlRequest.url ?? URL(string: "about:blank")!)
        self.redirects = []
    }

    // MARK: - Computed Properties

    /// URL запроса
    public var url: URL {
        request.url
    }

    /// HTTP-метод
    public var method: HTTPMethod {
        request.method
    }

    /// Статус-код ответа
    public var statusCode: Int? {
        response?.statusCode
    }

    /// Категория статуса
    public var statusCategory: StatusCategory? {
        response?.statusCategory
    }

    /// Хост
    public var host: String {
        metadata.host
    }

    /// Путь
    public var path: String {
        metadata.path
    }

    /// Является ли запрос успешным
    public var isSuccess: Bool {
        if case .completed = state {
            return response?.isSuccess ?? false
        }
        return false
    }

    /// Является ли запрос ошибкой
    public var isError: Bool {
        if case .failed = state { return true }
        return response?.isError ?? false
    }

    /// Форматированная длительность
    public var formattedDuration: String {
        formatDuration(duration)
    }

    /// Размер запроса
    public var requestSize: Int64 {
        request.bodySize
    }

    /// Размер ответа
    public var responseSize: Int64 {
        response?.bodySize ?? 0
    }

    /// Общий размер
    public var totalSize: Int64 {
        requestSize + responseSize
    }

    /// Форматированный размер ответа
    public var formattedResponseSize: String {
        ByteCountFormatter.string(fromByteCount: responseSize, countStyle: .file)
    }

    /// Composite ID that includes state for SwiftUI diffing
    /// This ensures the row updates when the record state changes
    public var compositeId: String {
        "\(id.uuidString)-\(state.displayName)-\(statusCode ?? 0)"
    }

    /// Краткое описание для списка
    public var shortDescription: String {
        "\(method.rawValue) \(path)"
    }

    /// Полное описание
    public var fullDescription: String {
        var desc = "\(method.rawValue) \(url.absoluteString)"
        if let status = statusCode {
            desc += " → \(status)"
        }
        desc += " (\(formattedDuration))"
        return desc
    }

    // MARK: - Mutating Methods

    /// Завершить запрос с ответом
    public mutating func complete(
        with response: ResponseData,
        timings: RequestTimings? = nil,
        security: SecurityInfo? = nil
    ) {
        self.response = response
        self.timings = timings
        self.security = security
        self.duration = Date().timeIntervalSince(timestamp)
        self.state = .completed
    }

    /// Пометить как неудавшийся
    public mutating func fail(with error: Error) {
        self.error = TrafficError(from: error)
        self.duration = Date().timeIntervalSince(timestamp)
        self.state = .failed(self.error!)
    }

    /// Пометить как отмененный
    public mutating func cancel() {
        self.duration = Date().timeIntervalSince(timestamp)
        self.state = .cancelled
    }

    /// Пометить как мок
    public mutating func markAsMocked() {
        self.state = .mocked
    }

    /// Добавить редирект
    public mutating func addRedirect(_ hop: RedirectHop) {
        redirects.append(hop)
    }

    // MARK: - Private

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 0.001 {
            return "<1 ms"
        } else if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.2f s", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%d min %.0f s", minutes, seconds)
        }
    }
}

// MARK: - Hashable

extension TrafficRecord {
    public static func == (lhs: TrafficRecord, rhs: TrafficRecord) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Comparable by Timestamp

extension TrafficRecord: Comparable {
    public static func < (lhs: TrafficRecord, rhs: TrafficRecord) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}
