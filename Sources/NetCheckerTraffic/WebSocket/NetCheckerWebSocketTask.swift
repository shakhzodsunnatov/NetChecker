import Foundation

/// Записывающая обёртка над `URLSessionWebSocketTask`.
///
/// ## Почему обёртка, а не swizzling
///
/// Весь остальной перехват NetChecker построен на `URLProtocol`, но
/// `URLSessionWebSocketTask` проходит мимо цепочки протоколов целиком.
/// Подмена методов тоже не подходит: в рантайме задача является экземпляром
/// приватного `__NSURLSessionWebSocketTask`, который переопределяет
/// `sendMessage:completionHandler:`, `receiveMessageWithCompletionHandler:`
/// и `cancelWithCloseCode:reason:`. Swizzling публичного
/// `URLSessionWebSocketTask` не выполнится никогда, а подмена приватного класса
/// по имени ломается на обновлениях ОС и создаёт риск при ревью в App Store.
///
/// Обёртка требует одного слова в коде приложения и работает всегда:
///
/// ```swift
/// let task = session.netCheckerWebSocketTask(with: url)
/// task.resume()
/// try await task.send(.string("hello"))
/// let message = try await task.receive()
/// task.cancel(with: .goingAway, reason: nil)
/// ```
public final class NetCheckerWebSocketTask: @unchecked Sendable {

    /// Обёрнутая системная задача
    public let task: URLSessionWebSocketTask

    /// Идентификатор записи в `WebSocketStore`
    public let recordId: UUID

    /// Записывать ли кадры
    private let isRecording: Bool

    // MARK: - Initialization

    /// Обернуть существующую задачу
    public init(_ task: URLSessionWebSocketTask, recording: Bool = true) {
        self.task = task
        self.isRecording = recording

        let rawURL = task.originalRequest?.url ?? URL(string: "wss://unknown")!
        let url = Self.webSocketScheme(for: rawURL)
        let headers = task.originalRequest?.allHTTPHeaderFields ?? [:]
        let id = UUID()
        self.recordId = id

        guard recording else { return }

        // Регистрация соединения выполняется на главном акторе,
        // а инициализатор может быть вызван откуда угодно
        Task { @MainActor in
            WebSocketStore.shared.register(id: id, url: url, requestHeaders: headers)
        }
    }

    // MARK: - Lifecycle

    /// Начать соединение
    public func resume() {
        task.resume()
    }

    /// Закрыть соединение
    public func cancel(
        with closeCode: URLSessionWebSocketTask.CloseCode = .goingAway,
        reason: Data? = nil
    ) {
        task.cancel(with: closeCode, reason: reason)

        guard isRecording else { return }

        let id = recordId
        let code = closeCode.rawValue
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }

        Task { @MainActor in
            WebSocketStore.shared.append(
                WebSocketFrame(direction: .outgoing, kind: .close, text: text ?? "Код \(code)"),
                to: id
            )
            WebSocketStore.shared.close(id: id, code: code, reason: text)
        }
    }

    // MARK: - Передача кадров

    /// Отправить сообщение
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        do {
            try await task.send(message)
            record(WebSocketFrame.message(message, direction: .outgoing))
        } catch {
            record(WebSocketFrame.failure(error, direction: .outgoing))
            fail(error)
            throw error
        }
    }

    /// Получить сообщение
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        do {
            let message = try await task.receive()
            record(WebSocketFrame.message(message, direction: .incoming))
            return message
        } catch {
            record(WebSocketFrame.failure(error, direction: .incoming))
            fail(error)
            throw error
        }
    }

    /// Отправить ping и дождаться pong
    public func sendPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        record(WebSocketFrame(direction: .outgoing, kind: .ping))
        record(WebSocketFrame(direction: .incoming, kind: .pong))
    }

    // MARK: - Private

    private func record(_ frame: WebSocketFrame) {
        guard isRecording else { return }
        let id = recordId
        Task { @MainActor in
            WebSocketStore.shared.append(frame, to: id)
        }
    }

    /// Вернуть URL WebSocket-схему.
    ///
    /// `URLSession.webSocketTask(with:)` нормализует `wss://` в `https://`,
    /// а `ws://` — в `http://`: под капотом это тот же транспорт. В инспекторе
    /// показывать HTTP-схему для сокета сбивает с толку, поэтому возвращаем исходную.
    private static func webSocketScheme(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return url
        }

        return components.url ?? url
    }

    private func fail(_ error: Error) {
        guard isRecording else { return }
        let id = recordId
        let message = error.localizedDescription
        Task { @MainActor in
            WebSocketStore.shared.fail(id: id, message: message)
        }
    }
}

// MARK: - Создание из URLSession

public extension URLSession {
    /// Создать WebSocket-задачу, кадры которой попадают в инспектор NetChecker
    func netCheckerWebSocketTask(with url: URL) -> NetCheckerWebSocketTask {
        NetCheckerWebSocketTask(webSocketTask(with: url))
    }

    /// Создать WebSocket-задачу из запроса
    func netCheckerWebSocketTask(with request: URLRequest) -> NetCheckerWebSocketTask {
        NetCheckerWebSocketTask(webSocketTask(with: request))
    }

    /// Создать WebSocket-задачу с указанием протоколов
    func netCheckerWebSocketTask(with url: URL, protocols: [String]) -> NetCheckerWebSocketTask {
        NetCheckerWebSocketTask(webSocketTask(with: url, protocols: protocols))
    }
}
