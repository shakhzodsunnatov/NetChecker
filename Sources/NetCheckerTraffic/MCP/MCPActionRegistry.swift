import Foundation

/// Действие, которое AI может вызвать через MCP
public struct MCPAction: Sendable {
    /// Уникальный тег для вызова
    public let tag: String

    /// Человекочитаемое имя
    public let name: String

    /// Описание что делает действие
    public let actionDescription: String

    /// Названия параметров (для документации AI)
    public let parameterNames: [String]

    /// Обработчик — принимает параметры, возвращает результат
    private let handler: @Sendable ([String: String]) async throws -> String

    public init(
        tag: String,
        name: String,
        description: String,
        parameters: [String] = [],
        handler: @escaping @Sendable ([String: String]) async throws -> String
    ) {
        self.tag = tag
        self.name = name
        self.actionDescription = description
        self.parameterNames = parameters
        self.handler = handler
    }

    /// Выполнить действие
    public func execute(params: [String: String]) async throws -> String {
        try await handler(params)
    }
}

/// Реестр действий, доступных AI через MCP
@MainActor
public final class MCPActionRegistry: ObservableObject {
    public static let shared = MCPActionRegistry()

    /// Зарегистрированные действия
    @Published public private(set) var actions: [String: MCPAction] = [:]

    private init() {}

    /// Все действия в виде массива
    public var allActions: [MCPAction] { Array(actions.values).sorted { $0.tag < $1.tag } }

    /// Получить действие по тегу
    public func action(for tag: String) -> MCPAction? { actions[tag] }

    /// Зарегистрировать одно действие
    public func register(_ action: MCPAction) {
        actions[action.tag] = action
        print("[NetChecker MCP] Триггер зарегистрирован: \(action.tag) — \(action.name)")
    }

    /// Зарегистрировать несколько действий
    public func register(_ newActions: [MCPAction]) {
        for action in newActions { register(action) }
    }

    /// Удалить действие
    public func unregister(tag: String) {
        actions.removeValue(forKey: tag)
    }

    /// Удалить все действия
    public func unregisterAll() {
        actions.removeAll()
    }
}

// MARK: - Convenience: быстрая регистрация

extension MCPActionRegistry {
    /// Зарегистрировать простое действие без параметров
    public func register(
        tag: String,
        name: String,
        description: String,
        handler: @escaping @Sendable () async throws -> String
    ) {
        register(MCPAction(
            tag: tag,
            name: name,
            description: description,
            handler: { _ in try await handler() }
        ))
    }

    /// Зарегистрировать действие с параметрами
    public func register(
        tag: String,
        name: String,
        description: String,
        parameters: [String],
        handler: @escaping @Sendable ([String: String]) async throws -> String
    ) {
        register(MCPAction(
            tag: tag,
            name: name,
            description: description,
            parameters: parameters,
            handler: handler
        ))
    }
}
