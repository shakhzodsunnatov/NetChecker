import Foundation
import Combine

/// Хранилище окружений
@MainActor
public final class EnvironmentStore: ObservableObject {
    // MARK: - Singleton

    public static let shared = EnvironmentStore()

    // MARK: - Published Properties

    /// Все группы окружений
    @Published public private(set) var groups: [EnvironmentGroup] = []

    /// Quick overrides (временные подмены)
    @Published public private(set) var quickOverrides: [String: QuickOverride] = [:]

    // MARK: - Properties

    private let userDefaultsKey = "NetCheckerEnvironments"
    private var overrideTimers: [String: Task<Void, Never>] = [:]

    // MARK: - Initialization

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - Group Management

    /// Добавить группу
    public func addGroup(_ group: EnvironmentGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
        saveToUserDefaults()
    }

    /// Удалить группу
    public func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        saveToUserDefaults()
    }

    /// Получить группу по имени
    public func group(named name: String) -> EnvironmentGroup? {
        groups.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Получить группу для хоста
    public func group(for host: String) -> EnvironmentGroup? {
        groups.first { $0.matches(host: host) }
    }

    // MARK: - Environment Switching

    /// Переключить окружение в группе
    public func switchEnvironment(group groupName: String, to environmentName: String) {
        guard let index = groups.firstIndex(where: { $0.name.lowercased() == groupName.lowercased() }) else {
            return
        }

        groups[index].setActive(name: environmentName)
        saveToUserDefaults()
    }

    /// Переключить окружение в группе по ID
    public func switchEnvironment(groupId: UUID, to environmentId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
            return
        }

        groups[index].setActive(id: environmentId)
        saveToUserDefaults()
    }

    /// Получить активное окружение для группы
    public func activeEnvironment(for groupName: String) -> Environment? {
        group(named: groupName)?.activeEnvironment
    }

    /// Получить любое активное окружение (первое найденное)
    public var activeEnvironment: Environment? {
        groups.compactMap { $0.activeEnvironment }.first
    }

    /// Добавить окружение в группу
    public func addEnvironment(_ environment: Environment, to groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].addEnvironment(environment)
        saveToUserDefaults()
    }

    /// Удалить окружение из группы
    public func removeEnvironment(_ environmentId: UUID, from groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].removeEnvironment(id: environmentId)
        saveToUserDefaults()
    }

    // MARK: - Quick Overrides

    /// Добавить quick override
    public func addQuickOverride(
        from sourceHost: String,
        to targetHost: String,
        autoDisableAfter: TimeInterval? = nil
    ) {
        let override = QuickOverride(
            sourceHost: sourceHost.lowercased(),
            targetHost: targetHost,
            createdAt: Date(),
            expiresAt: autoDisableAfter.map { Date().addingTimeInterval($0) }
        )

        quickOverrides[sourceHost.lowercased()] = override

        // Setup auto-disable timer
        if let timeout = autoDisableAfter {
            cancelOverrideTimer(for: sourceHost)

            let task = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    self.removeQuickOverride(for: sourceHost)
                }
            }
            overrideTimers[sourceHost.lowercased()] = task
        }
    }

    /// Удалить quick override
    public func removeQuickOverride(for host: String) {
        cancelOverrideTimer(for: host)
        quickOverrides.removeValue(forKey: host.lowercased())
    }

    /// Удалить все quick overrides
    public func clearQuickOverrides() {
        for host in quickOverrides.keys {
            cancelOverrideTimer(for: host)
        }
        quickOverrides.removeAll()
    }

    /// Get the first quick override URL (convenience for UI)
    public var quickOverrideURL: URL? {
        quickOverrides.values.first.flatMap { URL(string: $0.targetHost) }
    }

    /// Clear single quick override (convenience for UI)
    public func clearQuickOverride() {
        clearQuickOverrides()
    }

    private func cancelOverrideTimer(for host: String) {
        overrideTimers[host.lowercased()]?.cancel()
        overrideTimers.removeValue(forKey: host.lowercased())
    }

    // MARK: - URL Rewriting

    /// Переписать URL согласно активным окружениям и overrides
    public func rewriteURL(_ url: URL?) -> URL? {
        guard let url = url, let host = url.host else { return nil }

        // Check quick overrides first
        if let override = quickOverrides[host.lowercased()] {
            if let expiresAt = override.expiresAt, expiresAt < Date() {
                // Expired, remove it
                quickOverrides.removeValue(forKey: host.lowercased())
            } else {
                return override.rewriteURL(url)
            }
        }

        // Check environment groups
        if let group = group(for: host) {
            return group.rewriteURL(url)
        }

        return nil
    }

    // MARK: - Variables

    /// Получить переменную из активного окружения
    public func variable(_ key: String) -> String? {
        for group in groups {
            if let env = group.activeEnvironment,
               let value = env.variables[key] {
                return value
            }
        }
        return nil
    }

    /// Получить все переменные
    public func allVariables() -> [String: String] {
        var result: [String: String] = [:]
        for group in groups {
            if let env = group.activeEnvironment {
                for (key, value) in env.variables {
                    result[key] = value
                }
            }
        }
        return result
    }

    // MARK: - Persistence

    private func saveToUserDefaults() {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([EnvironmentGroup].self, from: data) else {
            return
        }
        groups = decoded
    }

    // MARK: - Import/Export

    /// Экспортировать в JSON
    public func exportToJSON() -> Data? {
        let exportData = EnvironmentExportData(groups: groups)
        return try? JSONEncoder().encode(exportData)
    }

    /// Импортировать из JSON
    public func importFromJSON(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(EnvironmentExportData.self, from: data)
        groups = decoded.groups
        saveToUserDefaults()
    }

    /// Сбросить все на Production
    public func resetToProduction() {
        for index in groups.indices {
            if let defaultEnv = groups[index].defaultEnvironment {
                groups[index].activeEnvironmentId = defaultEnv.id
            }
        }
        clearQuickOverrides()
        saveToUserDefaults()
    }
}

// MARK: - Quick Override

public struct QuickOverride: Codable, Sendable {
    public let sourceHost: String
    public let targetHost: String
    public let createdAt: Date
    public let expiresAt: Date?

    /// Переписать URL
    public func rewriteURL(_ url: URL) -> URL? {
        guard url.host?.lowercased() == sourceHost.lowercased() else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Parse target host
        if targetHost.contains("://") {
            if let targetURL = URL(string: targetHost) {
                components?.scheme = targetURL.scheme
                components?.host = targetURL.host
                components?.port = targetURL.port
            }
        } else {
            components?.host = targetHost
        }

        return components?.url
    }
}

// MARK: - Export Data

private struct EnvironmentExportData: Codable {
    let version: Int = 1
    let groups: [EnvironmentGroup]
}
