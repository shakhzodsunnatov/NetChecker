import Foundation

/// Тип операции от AI-инструмента
public enum MCPOperationType: String, Codable, Sendable, CaseIterable, Hashable {
    // MARK: - Сетевые операции

    /// API-вызов
    case apiCall

    /// Получение вебхука
    case webhookReceived

    // MARK: - Файловые операции

    /// Чтение файла
    case fileRead

    /// Запись файла
    case fileWrite

    /// Удаление файла
    case fileDelete

    // MARK: - Кодогенерация

    /// Генерация кода
    case codeGeneration

    /// Рефакторинг
    case codeRefactor

    /// Исправление бага
    case codeFix

    // MARK: - Тестирование

    /// Запуск теста
    case testExecution

    /// Результат assert
    case testAssertion

    // MARK: - Сборка

    /// Начало сборки
    case buildStart

    /// Завершение сборки
    case buildComplete

    /// Ошибка сборки
    case buildError

    // MARK: - Прочее

    /// Выполнение команды
    case commandExecution

    /// Валидация схемы
    case schemaValidation

    /// Произвольная операция
    case custom

    // MARK: - Computed Properties

    /// Отображаемое имя
    public var displayName: String {
        switch self {
        case .apiCall: return "API Call"
        case .webhookReceived: return "Webhook"
        case .fileRead: return "File Read"
        case .fileWrite: return "File Write"
        case .fileDelete: return "File Delete"
        case .codeGeneration: return "Code Gen"
        case .codeRefactor: return "Refactor"
        case .codeFix: return "Code Fix"
        case .testExecution: return "Test Run"
        case .testAssertion: return "Assertion"
        case .buildStart: return "Build Start"
        case .buildComplete: return "Build Done"
        case .buildError: return "Build Error"
        case .commandExecution: return "Command"
        case .schemaValidation: return "Schema"
        case .custom: return "Custom"
        }
    }

    /// SF Symbol для иконки
    public var systemImage: String {
        switch self {
        case .apiCall: return "network"
        case .webhookReceived: return "arrow.down.circle"
        case .fileRead: return "doc.text"
        case .fileWrite: return "doc.text.fill"
        case .fileDelete: return "trash"
        case .codeGeneration: return "chevron.left.forwardslash.chevron.right"
        case .codeRefactor: return "arrow.triangle.2.circlepath"
        case .codeFix: return "wrench"
        case .testExecution: return "checkmark.shield"
        case .testAssertion: return "exclamationmark.triangle"
        case .buildStart: return "hammer"
        case .buildComplete: return "hammer.fill"
        case .buildError: return "xmark.octagon"
        case .commandExecution: return "terminal"
        case .schemaValidation: return "doc.badge.gearshape"
        case .custom: return "ellipsis.circle"
        }
    }

    /// Цвет для UI (имя системного цвета)
    public var colorName: String {
        switch self {
        case .apiCall, .webhookReceived: return "blue"
        case .fileRead, .fileWrite, .fileDelete: return "orange"
        case .codeGeneration, .codeRefactor, .codeFix: return "purple"
        case .testExecution, .testAssertion: return "green"
        case .buildStart, .buildComplete: return "teal"
        case .buildError: return "red"
        case .commandExecution: return "gray"
        case .schemaValidation: return "yellow"
        case .custom: return "secondary"
        }
    }

    /// Является ли операция сетевой
    public var isNetworkRelated: Bool {
        switch self {
        case .apiCall, .webhookReceived:
            return true
        default:
            return false
        }
    }
}

/// Серьёзность MCP-записи
public enum MCPSeverity: String, Codable, Sendable, Hashable, Comparable {
    case debug
    case info
    case warning
    case error
    case critical

    public var displayName: String {
        rawValue.capitalized
    }

    public var systemImage: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    public var colorName: String {
        switch self {
        case .debug: return "gray"
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        case .critical: return "red"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        case .critical: return 4
        }
    }

    public static func < (lhs: MCPSeverity, rhs: MCPSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
