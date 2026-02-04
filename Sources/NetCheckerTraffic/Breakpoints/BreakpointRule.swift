import Foundation

/// Правило breakpoint
public struct BreakpointRule: Codable, Sendable, Identifiable {
    /// Идентификатор
    public var id: UUID

    /// Название правила
    public var name: String

    /// Включено ли правило
    public var isEnabled: Bool

    /// Критерии соответствия
    public var matching: BreakpointMatching

    /// Направление (request/response/both)
    public var direction: BreakpointDirection

    /// Автоматическое продолжение через N секунд
    public var autoResume: TimeInterval?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        matching: BreakpointMatching,
        direction: BreakpointDirection = .request,
        autoResume: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matching = matching
        self.direction = direction
        self.autoResume = autoResume
    }

    // MARK: - Methods

    /// Проверить соответствие запроса
    public func matches(request: URLRequest) -> Bool {
        guard isEnabled else { return false }
        return matching.matches(request: request)
    }
}

// MARK: - Breakpoint Direction

public enum BreakpointDirection: String, Codable, Sendable, CaseIterable {
    /// Остановить перед отправкой запроса
    case request

    /// Остановить перед доставкой ответа
    case response

    /// Остановить в обоих направлениях
    case both

    public var displayName: String {
        switch self {
        case .request: return "Request"
        case .response: return "Response"
        case .both: return "Both"
        }
    }

    public var systemImage: String {
        switch self {
        case .request: return "arrow.up.circle"
        case .response: return "arrow.down.circle"
        case .both: return "arrow.up.arrow.down.circle"
        }
    }
}

// MARK: - Breakpoint Matching

public struct BreakpointMatching: Codable, Sendable {
    /// URL паттерн
    public var urlPattern: String?

    /// HTTP метод (nil = любой)
    public var method: HTTPMethod?

    /// Хост
    public var host: String?

    public init(
        urlPattern: String? = nil,
        method: HTTPMethod? = nil,
        host: String? = nil
    ) {
        self.urlPattern = urlPattern
        self.method = method
        self.host = host
    }

    /// Проверить соответствие
    public func matches(request: URLRequest) -> Bool {
        // Check URL pattern
        if let pattern = urlPattern {
            guard let url = request.url else { return false }

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
        }

        // Check method
        if let method = method {
            if HTTPMethod(from: request) != method {
                return false
            }
        }

        // Check host
        if let host = host {
            guard let requestHost = request.url?.host else { return false }
            if requestHost.lowercased() != host.lowercased() {
                return false
            }
        }

        return true
    }

    // MARK: - Convenience

    public static func url(_ pattern: String) -> BreakpointMatching {
        BreakpointMatching(urlPattern: pattern)
    }

    public static func host(_ host: String) -> BreakpointMatching {
        BreakpointMatching(host: host)
    }
}
