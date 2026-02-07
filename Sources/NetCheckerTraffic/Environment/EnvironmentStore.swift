import Foundation
import Combine

/// Environment store - manages environment groups, switching, and URL rewriting
@MainActor
public final class EnvironmentStore: ObservableObject {
    // MARK: - Singleton

    public static let shared = EnvironmentStore()

    // MARK: - Published Properties

    /// All environment groups
    @Published public private(set) var groups: [EnvironmentGroup] = []

    /// Quick overrides (temporary redirects)
    @Published public private(set) var quickOverrides: [String: QuickOverride] = [:]

    // MARK: - Properties

    private let userDefaultsKey = "NetCheckerEnvironments"
    private var overrideTimers: [String: Task<Void, Never>] = [:]

    // MARK: - Initialization

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - State Properties

    /// Whether there are any configured groups
    public var hasGroups: Bool {
        !groups.isEmpty
    }

    /// Whether there are any configured environments
    public var hasEnvironments: Bool {
        groups.contains { !$0.environments.isEmpty }
    }

    /// Total environment count across all groups
    public var totalEnvironmentCount: Int {
        groups.reduce(0) { $0 + $1.environments.count }
    }

    /// Whether any quick override is active
    public var hasActiveOverride: Bool {
        !quickOverrides.isEmpty
    }

    // MARK: - Group Management

    /// Add or update a group
    public func addGroup(_ group: EnvironmentGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
        saveToUserDefaults()
    }

    /// Update existing group
    public func updateGroup(_ group: EnvironmentGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        var updated = group
        updated.touch()
        groups[index] = updated
        saveToUserDefaults()
    }

    /// Remove group by ID
    public func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        saveToUserDefaults()
    }

    /// Get group by name
    public func group(named name: String) -> EnvironmentGroup? {
        groups.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Get group for host
    public func group(for host: String) -> EnvironmentGroup? {
        groups.first { $0.matches(host: host) }
    }

    /// Get group by ID
    public func group(id: UUID) -> EnvironmentGroup? {
        groups.first { $0.id == id }
    }

    // MARK: - Environment Switching

    /// Switch environment in group by names
    public func switchEnvironment(group groupName: String, to environmentName: String) {
        guard let index = groups.firstIndex(where: { $0.name.lowercased() == groupName.lowercased() }) else {
            return
        }

        groups[index].setActive(name: environmentName)
        saveToUserDefaults()
    }

    /// Switch environment in group by IDs
    public func switchEnvironment(groupId: UUID, to environmentId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else {
            return
        }

        groups[index].setActive(id: environmentId)
        saveToUserDefaults()
    }

    /// Get active environment for group
    public func activeEnvironment(for groupName: String) -> Environment? {
        group(named: groupName)?.activeEnvironment
    }

    /// Get first active environment (convenience for single-group setups)
    public var activeEnvironment: Environment? {
        groups.compactMap { $0.activeEnvironment }.first
    }

    // MARK: - Environment Management

    /// Add environment to group
    public func addEnvironment(_ environment: Environment, to groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].addEnvironment(environment)
        saveToUserDefaults()
    }

    /// Update environment in group
    public func updateEnvironment(_ environment: Environment, in groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].updateEnvironment(environment)
        saveToUserDefaults()
    }

    /// Remove environment from group
    public func removeEnvironment(_ environmentId: UUID, from groupId: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[index].removeEnvironment(id: environmentId)
        saveToUserDefaults()
    }

    /// Get environment by ID from any group
    public func environment(id: UUID) -> (environment: Environment, groupId: UUID)? {
        for group in groups {
            if let env = group.environments.first(where: { $0.id == id }) {
                return (env, group.id)
            }
        }
        return nil
    }

    // MARK: - Quick Overrides

    /// Add quick override (redirects sourceHost to targetURL)
    public func addQuickOverride(
        from sourceHost: String,
        to targetURL: String,
        autoDisableAfter: TimeInterval? = nil
    ) {
        let normalizedSource = sourceHost.lowercased()

        let override = QuickOverride(
            sourceHost: normalizedSource,
            targetHost: targetURL,
            createdAt: Date(),
            expiresAt: autoDisableAfter.map { Date().addingTimeInterval($0) }
        )

        quickOverrides[normalizedSource] = override

        // Setup auto-disable timer
        if let timeout = autoDisableAfter {
            cancelOverrideTimer(for: normalizedSource)

            let task = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    self.removeQuickOverride(for: normalizedSource)
                }
            }
            overrideTimers[normalizedSource] = task
        }
    }

    /// Remove quick override for host
    public func removeQuickOverride(for host: String) {
        let normalized = host.lowercased()
        cancelOverrideTimer(for: normalized)
        quickOverrides.removeValue(forKey: normalized)
    }

    /// Clear all quick overrides
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

    // MARK: - URL and Header Rewriting

    /// Rewrite request according to active environments and overrides
    /// Returns rewritten URL and headers to apply
    public func rewrite(_ url: URL?) -> EnvironmentRewriteResult {
        guard let url = url, let host = url.host else { return .none }

        let normalizedHost = host.lowercased()

        // Check quick overrides first (they have priority)
        if let override = quickOverrides[normalizedHost] {
            if let expiresAt = override.expiresAt, expiresAt < Date() {
                // Expired, remove it
                quickOverrides.removeValue(forKey: normalizedHost)
            } else {
                // Apply quick override
                return EnvironmentRewriteResult(
                    url: override.rewriteURL(url),
                    headers: [:],
                    sslTrustMode: .allowAll,
                    environment: nil
                )
            }
        }

        // Check environment groups
        if let group = group(for: host) {
            return group.rewrite(url)
        }

        return .none
    }

    /// Legacy: Rewrite URL only (for backward compatibility)
    public func rewriteURL(_ url: URL?) -> URL? {
        rewrite(url).url
    }

    // MARK: - Variables

    /// Get variable from active environments
    public func variable(_ key: String) -> String? {
        for group in groups {
            if let env = group.activeEnvironment,
               let value = env.variables[key] {
                return value
            }
        }
        return nil
    }

    /// Get all variables from all active environments
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

    /// Export to JSON data
    public func exportToJSON() -> Data? {
        let exportData = EnvironmentExportData(groups: groups)
        return try? JSONEncoder().encode(exportData)
    }

    /// Import from JSON data
    public func importFromJSON(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(EnvironmentExportData.self, from: data)
        groups = decoded.groups
        saveToUserDefaults()
    }

    /// Reset all environments to production (default)
    public func resetToProduction() {
        for index in groups.indices {
            if let defaultEnv = groups[index].defaultEnvironment {
                groups[index].activeEnvironmentId = defaultEnv.id
            }
        }
        clearQuickOverrides()
        saveToUserDefaults()
    }

    /// Clear all data
    public func clearAll() {
        groups.removeAll()
        clearQuickOverrides()
        saveToUserDefaults()
    }
}

// MARK: - Quick Override

public struct QuickOverride: Codable, Sendable {
    /// Source host to match (normalized to lowercase)
    public let sourceHost: String

    /// Target URL or host to redirect to
    public let targetHost: String

    /// When this override was created
    public let createdAt: Date

    /// When this override expires (nil = never)
    public let expiresAt: Date?

    /// Whether this override has expired
    public var isExpired: Bool {
        if let expiresAt = expiresAt {
            return expiresAt < Date()
        }
        return false
    }

    /// Rewrite URL to target
    public func rewriteURL(_ url: URL) -> URL? {
        guard url.host?.lowercased() == sourceHost.lowercased() else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Parse target host - can be full URL or just host
        if targetHost.contains("://") {
            if let targetURL = URL(string: targetHost) {
                components?.scheme = targetURL.scheme
                components?.host = targetURL.host
                components?.port = targetURL.port
            }
        } else {
            // Just a host, possibly with port
            if targetHost.contains(":") {
                let parts = targetHost.split(separator: ":")
                if parts.count == 2 {
                    components?.host = String(parts[0])
                    components?.port = Int(parts[1])
                }
            } else {
                components?.host = targetHost
            }
        }

        return components?.url
    }
}

// MARK: - Export Data

private struct EnvironmentExportData: Codable {
    let version: Int
    let groups: [EnvironmentGroup]

    init(groups: [EnvironmentGroup]) {
        self.version = 1
        self.groups = groups
    }
}
