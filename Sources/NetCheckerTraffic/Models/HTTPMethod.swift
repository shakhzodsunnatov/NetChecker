import Foundation

/// HTTP-методы для сетевых запросов
public enum HTTPMethod: String, Codable, Sendable, CaseIterable, Hashable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    case trace = "TRACE"
    case connect = "CONNECT"

    // MARK: - Initialization

    /// Создать из строки метода
    public init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "GET": self = .get
        case "POST": self = .post
        case "PUT": self = .put
        case "DELETE": self = .delete
        case "PATCH": self = .patch
        case "HEAD": self = .head
        case "OPTIONS": self = .options
        case "TRACE": self = .trace
        case "CONNECT": self = .connect
        default: return nil
        }
    }

    /// Создать из URLRequest
    public init(from request: URLRequest) {
        if let method = request.httpMethod, let parsed = HTTPMethod(rawValue: method) {
            self = parsed
        } else {
            self = .get
        }
    }

    // MARK: - Properties

    /// Цвет для отображения в UI
    public var colorName: String {
        switch self {
        case .get: return "blue"
        case .post: return "green"
        case .put: return "orange"
        case .delete: return "red"
        case .patch: return "purple"
        case .head: return "gray"
        case .options: return "gray"
        case .trace: return "gray"
        case .connect: return "gray"
        }
    }

    /// Имеет ли метод обычно тело запроса
    public var hasRequestBody: Bool {
        switch self {
        case .post, .put, .patch:
            return true
        case .get, .delete, .head, .options, .trace, .connect:
            return false
        }
    }

    /// Является ли метод безопасным (не изменяет данные)
    public var isSafe: Bool {
        switch self {
        case .get, .head, .options, .trace:
            return true
        case .post, .put, .delete, .patch, .connect:
            return false
        }
    }

    /// Является ли метод идемпотентным
    public var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete, .head, .options, .trace:
            return true
        case .post, .patch, .connect:
            return false
        }
    }

    /// SF Symbol для метода
    public var systemImage: String {
        switch self {
        case .get: return "arrow.down.circle"
        case .post: return "arrow.up.circle"
        case .put: return "arrow.up.arrow.down.circle"
        case .delete: return "trash.circle"
        case .patch: return "pencil.circle"
        case .head: return "info.circle"
        case .options: return "questionmark.circle"
        case .trace: return "magnifyingglass.circle"
        case .connect: return "link.circle"
        }
    }
}
