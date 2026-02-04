import Foundation

/// Категория HTTP статус-кода
public enum StatusCategory: String, Codable, Sendable, CaseIterable, Comparable {
    case informational  // 1xx
    case success        // 2xx
    case redirect       // 3xx
    case clientError    // 4xx
    case serverError    // 5xx
    case unknown

    // MARK: - Initialization

    /// Создать из статус-кода
    public init(statusCode: Int) {
        switch statusCode {
        case 100..<200: self = .informational
        case 200..<300: self = .success
        case 300..<400: self = .redirect
        case 400..<500: self = .clientError
        case 500..<600: self = .serverError
        default: self = .unknown
        }
    }

    // MARK: - Comparable

    public static func < (lhs: StatusCategory, rhs: StatusCategory) -> Bool {
        let order: [StatusCategory] = [.success, .informational, .redirect, .clientError, .serverError, .unknown]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }

    // MARK: - Properties

    /// Название категории
    public var displayName: String {
        switch self {
        case .informational: return "Informational"
        case .success: return "Success"
        case .redirect: return "Redirect"
        case .clientError: return "Client Error"
        case .serverError: return "Server Error"
        case .unknown: return "Unknown"
        }
    }

    /// Краткое описание
    public var shortDescription: String {
        switch self {
        case .informational: return "1xx"
        case .success: return "2xx"
        case .redirect: return "3xx"
        case .clientError: return "4xx"
        case .serverError: return "5xx"
        case .unknown: return "???"
        }
    }

    /// Цвет для отображения
    public var colorName: String {
        switch self {
        case .informational: return "blue"
        case .success: return "green"
        case .redirect: return "yellow"
        case .clientError: return "orange"
        case .serverError: return "red"
        case .unknown: return "gray"
        }
    }

    /// Является ли категория ошибкой
    public var isError: Bool {
        switch self {
        case .clientError, .serverError:
            return true
        case .informational, .success, .redirect, .unknown:
            return false
        }
    }

    /// Является ли категория успешной
    public var isSuccess: Bool {
        self == .success
    }

    /// SF Symbol для категории
    public var systemImage: String {
        switch self {
        case .informational: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .redirect: return "arrow.triangle.turn.up.right.circle.fill"
        case .clientError: return "exclamationmark.triangle.fill"
        case .serverError: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    /// Emoji для категории
    public var emoji: String {
        switch self {
        case .informational: return "🔵"
        case .success: return "🟢"
        case .redirect: return "🟡"
        case .clientError: return "🟠"
        case .serverError: return "🔴"
        case .unknown: return "⚪"
        }
    }
}

// MARK: - Status Code Helpers

public extension Int {
    /// Категория для статус-кода
    var statusCategory: StatusCategory {
        StatusCategory(statusCode: self)
    }

    /// Является ли статус-код успешным
    var isSuccessStatusCode: Bool {
        (200..<300).contains(self)
    }

    /// Является ли статус-код ошибкой
    var isErrorStatusCode: Bool {
        self >= 400
    }

    /// Стандартное сообщение для статус-кода
    var statusMessage: String {
        HTTPURLResponse.localizedString(forStatusCode: self)
    }
}
