import Foundation

/// Повторная отправка запросов
public struct RequestRetrier {
    /// Повторить запрос как есть
    public static func retry(record: TrafficRecord) async -> RetryResult {
        return await retry(request: record.request)
    }

    /// Повторить запрос с другим URL
    public static func retry(record: TrafficRecord, withURL newURL: URL) async -> RetryResult {
        var modifiedRequest = record.request
        modifiedRequest = RequestData(
            url: newURL,
            method: modifiedRequest.method,
            headers: modifiedRequest.headers,
            body: modifiedRequest.body,
            cachePolicy: modifiedRequest.cachePolicy,
            timeoutInterval: modifiedRequest.timeoutInterval
        )
        return await retry(request: modifiedRequest)
    }

    /// Повторить запрос с другим хостом
    public static func retry(record: TrafficRecord, withHost newHost: String) async -> RetryResult {
        guard var components = URLComponents(url: record.url, resolvingAgainstBaseURL: false) else {
            return RetryResult(error: TrafficError(
                code: -1,
                domain: "NetChecker",
                localizedDescription: "Invalid URL"
            ))
        }

        components.host = newHost
        guard let newURL = components.url else {
            return RetryResult(error: TrafficError(
                code: -1,
                domain: "NetChecker",
                localizedDescription: "Could not construct URL"
            ))
        }

        return await retry(record: record, withURL: newURL)
    }

    /// Повторить запрос с другим окружением
    public static func retry(record: TrafficRecord, withEnvironment env: Environment) async -> RetryResult {
        return await retry(record: record, withURL: env.baseURL.appendingPathComponent(record.path))
    }

    /// Повторить RequestData
    public static func retry(request: RequestData) async -> RetryResult {
        let startTime = Date()

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.allHTTPHeaderFields = request.headers
        urlRequest.httpBody = request.body

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return RetryResult(error: TrafficError(
                    code: -1,
                    domain: "NetChecker",
                    localizedDescription: "Invalid response"
                ))
            }

            let duration = Date().timeIntervalSince(startTime)

            return RetryResult(
                originalRequest: request,
                response: ResponseData(from: httpResponse, body: data),
                duration: duration
            )

        } catch {
            return RetryResult(
                originalRequest: request,
                error: TrafficError(from: error)
            )
        }
    }
}

// MARK: - Retry Result

public struct RetryResult: Sendable {
    /// Оригинальный запрос
    public var originalRequest: RequestData?

    /// Ответ
    public var response: ResponseData?

    /// Ошибка
    public var error: TrafficError?

    /// Длительность
    public var duration: TimeInterval

    /// Время выполнения
    public var timestamp: Date

    public init(
        originalRequest: RequestData? = nil,
        response: ResponseData? = nil,
        error: TrafficError? = nil,
        duration: TimeInterval = 0
    ) {
        self.originalRequest = originalRequest
        self.response = response
        self.error = error
        self.duration = duration
        self.timestamp = Date()
    }

    /// Успешен ли результат
    public var isSuccess: Bool {
        error == nil && response?.isSuccess == true
    }

    /// Статус-код
    public var statusCode: Int? {
        response?.statusCode
    }

    /// Форматированная длительность
    public var formattedDuration: String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}
