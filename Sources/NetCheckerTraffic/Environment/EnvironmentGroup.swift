import Foundation

/// Result of environment rewriting (URL + headers)
public struct EnvironmentRewriteResult: Sendable {
    /// Rewritten URL (nil if no rewrite needed)
    public let url: URL?

    /// Headers to apply (merged with existing headers)
    public let headers: [String: String]

    /// SSL trust mode for this environment
    public let sslTrustMode: EnvironmentSSLMode

    /// Source environment that was applied
    public let environment: Environment?

    public init(
        url: URL? = nil,
        headers: [String: String] = [:],
        sslTrustMode: EnvironmentSSLMode = .strict,
        environment: Environment? = nil
    ) {
        self.url = url
        self.headers = headers
        self.sslTrustMode = sslTrustMode
        self.environment = environment
    }

    /// No rewrite needed
    public static let none = EnvironmentRewriteResult()

    /// Whether any modification is needed
    public var hasModifications: Bool {
        url != nil || !headers.isEmpty
    }
}

/// Group of environments for one host/API
public struct EnvironmentGroup: Codable, Sendable, Identifiable {
    /// Group identifier
    public var id: UUID

    /// Group name
    public var name: String

    /// Pattern for matching (host or wildcard)
    public var sourcePattern: String

    /// List of environments
    public var environments: [Environment]

    /// Active environment ID
    public var activeEnvironmentId: UUID?

    /// Created date
    public var createdAt: Date

    /// Last modified date
    public var modifiedAt: Date

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        name: String,
        sourcePattern: String,
        environments: [Environment] = [],
        activeEnvironmentId: UUID? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sourcePattern = sourcePattern
        self.environments = environments
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt

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

    /// Active environment
    public var activeEnvironment: Environment? {
        guard let id = activeEnvironmentId else { return environments.first }
        return environments.first { $0.id == id }
    }

    /// Default environment
    public var defaultEnvironment: Environment? {
        environments.first { $0.isDefault } ?? environments.first
    }

    /// Is current environment production (default)
    public var isProductionActive: Bool {
        activeEnvironment?.isDefault == true
    }

    /// Is group empty
    public var isEmpty: Bool {
        environments.isEmpty
    }

    /// Environment count
    public var environmentCount: Int {
        environments.count
    }

    // MARK: - Matching Methods

    /// Check if URL matches this group
    public func matches(url: URL) -> Bool {
        guard let host = url.host else { return false }
        return matches(host: host)
    }

    /// Check if host matches this group
    public func matches(host: String) -> Bool {
        let pattern = sourcePattern.lowercased()
        let testHost = host.lowercased()

        // Exact match
        if pattern == testHost {
            return true
        }

        // Wildcard match at start (*.example.com)
        if pattern.hasPrefix("*") {
            let suffix = pattern.dropFirst()
            return testHost.hasSuffix(suffix)
        }

        // Wildcard match at end (example.*)
        if pattern.hasSuffix("*") {
            let prefix = pattern.dropLast()
            return testHost.hasPrefix(prefix)
        }

        // Contains wildcard match
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

    // MARK: - URL Rewriting

    /// Rewrite URL according to active environment (returns full result with headers)
    public func rewrite(_ url: URL) -> EnvironmentRewriteResult {
        guard matches(url: url) else { return .none }
        guard let active = activeEnvironment else { return .none }

        var rewrittenURL: URL? = nil

        // Only rewrite URL if host is different
        if active.baseURL.host != url.host {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = active.scheme
            components?.host = active.host
            components?.port = active.port
            rewrittenURL = components?.url
        }

        return EnvironmentRewriteResult(
            url: rewrittenURL,
            headers: active.headers,
            sslTrustMode: active.sslTrustMode,
            environment: active
        )
    }

    /// Legacy: Rewrite URL only (for backward compatibility)
    public func rewriteURL(_ url: URL) -> URL? {
        rewrite(url).url
    }

    // MARK: - Mutating Methods

    /// Update modified date
    public mutating func touch() {
        modifiedAt = Date()
    }

    /// Add environment
    public mutating func addEnvironment(_ environment: Environment) {
        environments.append(environment)

        if environment.isDefault || activeEnvironmentId == nil {
            activeEnvironmentId = environment.id
        }
        touch()
    }

    /// Update environment
    public mutating func updateEnvironment(_ environment: Environment) {
        guard let index = environments.firstIndex(where: { $0.id == environment.id }) else { return }
        var updated = environment
        updated.touch()
        environments[index] = updated
        touch()
    }

    /// Remove environment
    public mutating func removeEnvironment(id: UUID) {
        environments.removeAll { $0.id == id }

        if activeEnvironmentId == id {
            activeEnvironmentId = environments.first?.id
        }
        touch()
    }

    /// Set active environment by ID
    public mutating func setActive(id: UUID) {
        guard environments.contains(where: { $0.id == id }) else { return }
        activeEnvironmentId = id
        touch()
    }

    /// Set active environment by name
    public mutating func setActive(name: String) {
        guard let env = environments.first(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        activeEnvironmentId = env.id
        touch()
    }

    /// Reorder environments
    public mutating func moveEnvironment(from source: IndexSet, to destination: Int) {
        // Manual implementation since Array.move/remove(atOffsets:) is only in SwiftUI
        var items = environments
        let movedItems = source.map { items[$0] }

        // Remove items from highest index to lowest to maintain indices
        for index in source.sorted().reversed() {
            items.remove(at: index)
        }

        let insertIndex = destination > (source.first ?? 0) ? destination - source.count : destination
        items.insert(contentsOf: movedItems, at: max(0, min(insertIndex, items.count)))
        environments = items
        touch()
    }
}
