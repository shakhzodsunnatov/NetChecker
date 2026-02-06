import Foundation

/// Правило мока
public struct MockRule: Codable, Sendable, Identifiable {
    /// Идентификатор
    public var id: UUID

    /// Название правила
    public var name: String

    /// Включено ли правило
    public var isEnabled: Bool

    /// Приоритет (выше = проверяется раньше)
    public var priority: Int

    /// Критерии соответствия
    public var matching: MockMatching

    /// Действие при срабатывании
    public var action: MockAction

    /// Лимиты
    public var limits: MockLimits?

    /// Счетчик срабатываний
    public var activationCount: Int

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        priority: Int = 0,
        matching: MockMatching,
        action: MockAction,
        limits: MockLimits? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.priority = priority
        self.matching = matching
        self.action = action
        self.limits = limits
        self.activationCount = 0
    }

    // MARK: - Methods

    /// Проверить соответствие запроса
    public func matches(request: URLRequest) -> Bool {
        guard isEnabled else { return false }

        // Check limits
        if let limits = limits {
            if let maxActivations = limits.maxActivations, activationCount >= maxActivations {
                return false
            }
            if let expiresAt = limits.expiresAt, expiresAt < Date() {
                return false
            }
        }

        return matching.matches(request: request)
    }
}

// MARK: - Mock Matching

public struct MockMatching: Codable, Sendable {
    /// URL паттерн (regex или wildcard)
    public var urlPattern: String?

    /// HTTP метод (nil = любой)
    public var method: HTTPMethod?

    /// Хост
    public var host: String?

    /// Требуемые заголовки
    public var headers: [String: String]?

    /// Body содержит
    public var bodyContains: String?

    public init(
        urlPattern: String? = nil,
        method: HTTPMethod? = nil,
        host: String? = nil,
        headers: [String: String]? = nil,
        bodyContains: String? = nil
    ) {
        self.urlPattern = urlPattern
        self.method = method
        self.host = host
        self.headers = headers
        self.bodyContains = bodyContains
    }

    /// Проверить соответствие
    public func matches(request: URLRequest) -> Bool {
        // Check URL pattern
        if let pattern = urlPattern {
            guard let url = request.url else { return false }

            if pattern.contains("*") {
                // Wildcard matching
                let regexPattern = pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")

                if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                    let urlString = url.absoluteString
                    let range = NSRange(urlString.startIndex..., in: urlString)
                    if regex.firstMatch(in: urlString, options: [], range: range) == nil {
                        return false
                    }
                }
            } else {
                // Exact match
                if !url.absoluteString.lowercased().contains(pattern.lowercased()) {
                    return false
                }
            }
        }

        // Check method
        if let method = method {
            if HTTPMethod(from: request) != method {
                return false
            }
        }

        // Check host
        if let host = host {
            guard let requestHost = request.url?.host?.lowercased(),
                  requestHost == host.lowercased() else {
                return false
            }
        }

        // Check headers
        if let requiredHeaders = headers {
            guard let requestHeaders = request.allHTTPHeaderFields else { return false }

            for (key, value) in requiredHeaders {
                guard let headerValue = requestHeaders[key], headerValue == value else {
                    return false
                }
            }
        }

        // Check body contains
        if let bodyContains = bodyContains {
            guard let body = request.httpBody,
                  let bodyString = String(data: body, encoding: .utf8),
                  bodyString.contains(bodyContains) else {
                return false
            }
        }

        return true
    }

    // MARK: - Convenience Initializers

    public static func url(_ pattern: String) -> MockMatching {
        MockMatching(urlPattern: pattern)
    }

    public static func url(_ pattern: String, method: HTTPMethod) -> MockMatching {
        MockMatching(urlPattern: pattern, method: method)
    }
}

// MARK: - Mock Action

public enum MockAction: Codable, Sendable {
    /// Вернуть mock response
    case respond(MockResponse)

    /// Вернуть ошибку
    case error(MockError)

    /// Только задержка (ответ реальный)
    case delay(seconds: TimeInterval)

    /// Пропустить в сеть
    case passthrough

    /// Модифицировать реальный ответ
    case modifyResponse(statusCode: Int?, headers: [String: String]?)
}

// MARK: - Mock Response

public struct MockResponse: Codable, Sendable {
    /// Статус-код
    public var statusCode: Int

    /// Заголовки
    public var headers: [String: String]

    /// Тело ответа
    public var body: Data?

    /// Задержка перед ответом
    public var delay: TimeInterval?

    /// Override request body (for passthrough or recording)
    public var requestBodyOverride: Data?

    public init(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: Data? = nil,
        delay: TimeInterval? = nil,
        requestBodyOverride: Data? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.delay = delay
        self.requestBodyOverride = requestBodyOverride
    }

    // MARK: - Convenience Initializers

    public static func json(_ json: String, statusCode: Int = 200) -> MockResponse {
        MockResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: json.data(using: .utf8)
        )
    }

    public static func json(_ object: Encodable, statusCode: Int = 200) -> MockResponse? {
        guard let data = try? JSONEncoder().encode(object) else { return nil }
        return MockResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    public static func empty(statusCode: Int = 200) -> MockResponse {
        MockResponse(statusCode: statusCode)
    }
}

// MARK: - Mock Error

public enum MockError: Codable, Sendable, Hashable {
    case noConnection
    case timeout
    case dnsFailure
    case sslError
    case custom(code: Int, domain: String, description: String)

    public var nsError: NSError {
        switch self {
        case .noConnection:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        case .timeout:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        case .dnsFailure:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        case .sslError:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorSecureConnectionFailed)
        case .custom(let code, let domain, let description):
            return NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: description])
        }
    }
}

// MARK: - Mock Limits

public struct MockLimits: Codable, Sendable {
    /// Максимальное количество срабатываний
    public var maxActivations: Int?

    /// Истекает в
    public var expiresAt: Date?

    public init(maxActivations: Int? = nil, expiresAt: Date? = nil) {
        self.maxActivations = maxActivations
        self.expiresAt = expiresAt
    }

    public static func once() -> MockLimits {
        MockLimits(maxActivations: 1)
    }

    public static func times(_ count: Int) -> MockLimits {
        MockLimits(maxActivations: count)
    }

    public static func until(_ date: Date) -> MockLimits {
        MockLimits(expiresAt: date)
    }
}
