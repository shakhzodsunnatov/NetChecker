import Foundation
import Combine

/// Хранилище WebSocket-соединений
@MainActor
public final class WebSocketStore: ObservableObject {
    // MARK: - Singleton

    public static let shared = WebSocketStore()

    // MARK: - Published Properties

    /// Соединения, новые в начале
    @Published public private(set) var connections: [WebSocketRecord] = []

    // MARK: - Configuration

    /// Максимум хранимых соединений
    public var maxConnections: Int = 50

    /// Максимум кадров на соединение
    public var maxFramesPerConnection: Int = 500

    /// Ведётся ли запись
    public var isRecordingEnabled: Bool = true

    // MARK: - Computed

    public var count: Int { connections.count }

    public var activeCount: Int {
        connections.filter { $0.state.isActive }.count
    }

    public var totalFrameCount: Int {
        connections.reduce(0) { $0 + $1.frames.count }
    }

    private init() {}

    // MARK: - Lifecycle

    /// Зарегистрировать новое соединение и получить его идентификатор
    @discardableResult
    public func open(url: URL, requestHeaders: [String: String] = [:]) -> UUID {
        let id = UUID()
        register(id: id, url: url, requestHeaders: requestHeaders)
        return id
    }

    /// Зарегистрировать соединение с заранее известным идентификатором.
    /// Нужно обёртке, которая создаёт идентификатор до обращения к хранилищу.
    public func register(id: UUID, url: URL, requestHeaders: [String: String] = [:]) {
        guard isRecordingEnabled else { return }
        guard !connections.contains(where: { $0.id == id }) else { return }

        var record = WebSocketRecord(
            id: id,
            url: url,
            requestHeaders: requestHeaders,
            maxFrames: maxFramesPerConnection
        )
        record.markOpen()

        connections.insert(record, at: 0)

        if connections.count > maxConnections {
            connections.removeLast(connections.count - maxConnections)
        }
    }

    /// Записать кадр в соединение
    public func append(_ frame: WebSocketFrame, to id: UUID) {
        guard isRecordingEnabled, let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].append(frame)
    }

    /// Отметить соединение закрытым
    public func close(id: UUID, code: Int, reason: String?) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].markClosed(code: code, reason: reason)
    }

    /// Отметить соединение упавшим
    public func fail(id: UUID, message: String) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].markFailed(message)
    }

    // MARK: - Access

    public func connection(id: UUID) -> WebSocketRecord? {
        connections.first { $0.id == id }
    }

    /// Очистить все соединения
    public func clear() {
        connections.removeAll()
    }

    /// Удалить одно соединение
    public func remove(id: UUID) {
        connections.removeAll { $0.id == id }
    }
}
