import Foundation

/// Группа окружений для одного хоста/API
public struct EnvironmentGroup: Codable, Sendable, Identifiable {
    /// Идентификатор группы
    public var id: UUID

    /// Название группы
    public var name: String

    /// Паттерн для matching (хост или wildcard)
    public var sourcePattern: String

    /// Список окружений
    public var environments: [Environment]

    /// ID активного окружения
    public var activeEnvironmentId: UUID?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        name: String,
        sourcePattern: String,
        environments: [Environment] = [],
        activeEnvironmentId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.sourcePattern = sourcePattern
        self.environments = environments

        // Set active to default or first
        if let activeId = activeEnvironmentId {
            self.activeEnvironmentId = activeId
        } else if let defaultEnv = environments.first(where: { $0.isDefault }) {
            self.activeEnvironmentId = defaultEnv.id
        } else {
            self.activeEnvironmentId = environments.first?.id
        }
    }

    // MARK: - Computed Properties

    /// Активное окружение
    public var activeEnvironment: Environment? {
        guard let id = activeEnvironmentId else { return environments.first }
        return environments.first { $0.id == id }
    }

    /// Окружение по умолчанию
    public var defaultEnvironment: Environment? {
        environments.first { $0.isDefault } ?? environments.first
    }

    /// Является ли текущее окружение production (default)
    public var isProductionActive: Bool {
        activeEnvironment?.isDefault == true
    }

    // MARK: - Methods

    /// Проверить, соответствует ли URL этой группе
    public func matches(url: URL) -> Bool {
        guard let host = url.host else { return false }
        return matches(host: host)
    }

    /// Проверить, соответствует ли хост этой группе
    public func matches(host: String) -> Bool {
        let pattern = sourcePattern.lowercased()
        let testHost = host.lowercased()

        // Exact match
        if pattern == testHost {
            return true
        }

        // Wildcard match
        if pattern.hasPrefix("*") {
            let suffix = pattern.dropFirst()
            return testHost.hasSuffix(suffix)
        }

        // Contains match
        if pattern.contains("*") {
            let components = pattern.components(separatedBy: "*")
            var remaining = testHost

            for component in components where !component.isEmpty {
                if let range = remaining.range(of: component) {
                    remaining = String(remaining[range.upperBound...])
                } else {
                    return false
                }
            }
            return true
        }

        return false
    }

    /// Переписать URL согласно активному окружению
    public func rewriteURL(_ url: URL) -> URL? {
        guard matches(url: url) else { return nil }
        guard let active = activeEnvironment else { return nil }
        guard active.baseURL.host != url.host else { return nil } // Same host, no rewrite needed

        // Build new URL
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = active.scheme
        components?.host = active.host
        components?.port = active.port

        return components?.url
    }

    // MARK: - Mutating Methods

    /// Добавить окружение
    public mutating func addEnvironment(_ environment: Environment) {
        environments.append(environment)

        if environment.isDefault || activeEnvironmentId == nil {
            activeEnvironmentId = environment.id
        }
    }

    /// Удалить окружение
    public mutating func removeEnvironment(id: UUID) {
        environments.removeAll { $0.id == id }

        if activeEnvironmentId == id {
            activeEnvironmentId = environments.first?.id
        }
    }

    /// Установить активное окружение
    public mutating func setActive(id: UUID) {
        guard environments.contains(where: { $0.id == id }) else { return }
        activeEnvironmentId = id
    }

    /// Установить активное окружение по имени
    public mutating func setActive(name: String) {
        guard let env = environments.first(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        activeEnvironmentId = env.id
    }
}
