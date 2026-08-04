import Foundation

/// Состояние WebSocket-соединения
public enum WebSocketConnectionState: Codable, Sendable, Hashable {
    /// Соединение устанавливается
    case connecting
    /// Соединение открыто
    case open
    /// Соединение закрыто
    case closed(code: Int, reason: String?)
    /// Соединение завершилось ошибкой
    case failed(String)

    public var label: String {
        switch self {
        case .connecting: return "Connecting"
        case .open: return "Open"
        case .closed: return "Closed"
        case .failed: return "Failed"
        }
    }

    public var isActive: Bool {
        switch self {
        case .connecting, .open: return true
        case .closed, .failed: return false
        }
    }
}

/// Запись об одном WebSocket-соединении.
///
/// Отдельный тип, а не `TrafficRecord`: у сокета нет пары «запрос — ответ»,
/// есть долгоживущее соединение и поток кадров в обе стороны.
public struct WebSocketRecord: Identifiable, Sendable, Hashable {
    public let id: UUID

    /// Адрес соединения
    public let url: URL

    /// Заголовки рукопожатия
    public var requestHeaders: [String: String]

    /// Когда соединение открылось
    public let openedAt: Date

    /// Когда соединение закрылось
    public var closedAt: Date?

    /// Текущее состояние
    public var state: WebSocketConnectionState

    /// Кадры в хронологическом порядке
    public private(set) var frames: [WebSocketFrame]

    /// Сколько кадров было отброшено при достижении лимита
    public private(set) var droppedFrameCount: Int

    /// Предел хранимых кадров
    public var maxFrames: Int

    public init(
        id: UUID = UUID(),
        url: URL,
        requestHeaders: [String: String] = [:],
        openedAt: Date = Date(),
        state: WebSocketConnectionState = .connecting,
        maxFrames: Int = 500
    ) {
        self.id = id
        self.url = url
        self.requestHeaders = requestHeaders
        self.openedAt = openedAt
        self.closedAt = nil
        self.state = state
        self.frames = []
        self.droppedFrameCount = 0
        self.maxFrames = max(1, maxFrames)
    }

    // MARK: - Computed

    public var host: String { url.host ?? "" }

    public var path: String { url.path.isEmpty ? "/" : url.path }

    /// Длительность соединения
    public var duration: TimeInterval {
        (closedAt ?? Date()).timeIntervalSince(openedAt)
    }

    public var sentFrameCount: Int {
        frames.filter { $0.direction == .outgoing }.count
    }

    public var receivedFrameCount: Int {
        frames.filter { $0.direction == .incoming }.count
    }

    /// Суммарный объём переданных данных
    public var totalBytes: Int {
        frames.reduce(0) { $0 + $1.size }
    }

    public var hasErrors: Bool {
        if case .failed = state { return true }
        return frames.contains { $0.kind == .error }
    }

    // MARK: - Mutating

    /// Добавить кадр, соблюдая лимит
    public mutating func append(_ frame: WebSocketFrame) {
        frames.append(frame)

        if frames.count > maxFrames {
            let excess = frames.count - maxFrames
            frames.removeFirst(excess)
            droppedFrameCount += excess
        }
    }

    /// Отметить соединение открытым
    public mutating func markOpen() {
        state = .open
    }

    /// Отметить соединение закрытым
    public mutating func markClosed(code: Int, reason: String?) {
        state = .closed(code: code, reason: reason)
        closedAt = Date()
    }

    /// Отметить соединение упавшим
    public mutating func markFailed(_ message: String) {
        state = .failed(message)
        closedAt = Date()
    }
}
