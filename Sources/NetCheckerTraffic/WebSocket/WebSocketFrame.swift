import Foundation

/// Направление передачи кадра
public enum WebSocketDirection: String, Codable, Sendable, CaseIterable {
    /// Отправлен приложением
    case outgoing
    /// Получен от сервера
    case incoming

    public var symbolName: String {
        switch self {
        case .outgoing: return "arrow.up.circle.fill"
        case .incoming: return "arrow.down.circle.fill"
        }
    }
}

/// Тип содержимого кадра
public enum WebSocketFrameKind: String, Codable, Sendable {
    case text
    case binary
    case ping
    case pong
    case close
    /// Ошибка при отправке или получении
    case error

    public var label: String {
        switch self {
        case .text: return "Text"
        case .binary: return "Binary"
        case .ping: return "Ping"
        case .pong: return "Pong"
        case .close: return "Close"
        case .error: return "Error"
        }
    }
}

/// Один кадр WebSocket-соединения
public struct WebSocketFrame: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let direction: WebSocketDirection
    public let kind: WebSocketFrameKind

    /// Текстовое содержимое (для `.text`, `.close`, `.error`)
    public let text: String?

    /// Двоичное содержимое (для `.binary`, `.ping`, `.pong`)
    public let data: Data?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        direction: WebSocketDirection,
        kind: WebSocketFrameKind,
        text: String? = nil,
        data: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.kind = kind
        self.text = text
        self.data = data
    }

    // MARK: - Computed

    /// Размер полезной нагрузки в байтах
    public var size: Int {
        if let data = data { return data.count }
        if let text = text { return text.utf8.count }
        return 0
    }

    /// Похоже ли содержимое на JSON
    public var isJSON: Bool {
        guard kind == .text, let text = text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    /// Краткое содержимое для строки списка
    public var preview: String {
        if let text = text {
            let flattened = text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return flattened.count > 120 ? String(flattened.prefix(120)) + "…" : flattened
        }
        if let data = data {
            return "\(data.count) байт двоичных данных"
        }
        return kind.label
    }
}

// MARK: - Построение из сообщений URLSession

public extension WebSocketFrame {
    /// Кадр из сообщения `URLSessionWebSocketTask`
    static func message(
        _ message: URLSessionWebSocketTask.Message,
        direction: WebSocketDirection
    ) -> WebSocketFrame {
        switch message {
        case .string(let text):
            return WebSocketFrame(direction: direction, kind: .text, text: text)

        case .data(let data):
            return WebSocketFrame(direction: direction, kind: .binary, data: data)

        @unknown default:
            return WebSocketFrame(
                direction: direction,
                kind: .error,
                text: "Неизвестный тип сообщения"
            )
        }
    }

    /// Кадр ошибки
    static func failure(_ error: Error, direction: WebSocketDirection) -> WebSocketFrame {
        WebSocketFrame(direction: direction, kind: .error, text: error.localizedDescription)
    }
}
