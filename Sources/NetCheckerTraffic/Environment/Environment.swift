import Foundation

/// SSL Trust Mode for environment configuration (simplified version)
public enum EnvironmentSSLMode: String, Codable, Sendable, CaseIterable, Hashable {
    case strict = "strict"
    case allowSelfSigned = "allowSelfSigned"
    case allowExpired = "allowExpired"
    case allowAll = "allowAll"

    public var displayName: String {
        switch self {
        case .strict: return "Strict (Production)"
        case .allowSelfSigned: return "Allow Self-Signed"
        case .allowExpired: return "Allow Expired"
        case .allowAll: return "Allow All (Insecure)"
        }
    }

    public var description: String {
        switch self {
        case .strict: return "Only trust valid certificates"
        case .allowSelfSigned: return "Trust self-signed certificates"
        case .allowExpired: return "Trust expired certificates"
        case .allowAll: return "Trust all certificates (development only)"
        }
    }

    /// Convert to full SSLTrustMode with host
    public func toSSLTrustMode(for host: String) -> SSLTrustMode {
        switch self {
        case .strict:
            return .strict
        case .allowSelfSigned:
            return .allowSelfSigned(hosts: [host])
        case .allowExpired:
            return .allowExpired(hosts: [host])
        case .allowAll:
            return .allowAll(iUnderstandTheRisk: true)
        }
    }
}

/// Model for environment (Production, Staging, Development, etc.)
public struct Environment: Codable, Sendable, Identifiable, Hashable {
    /// Unique identifier
    public var id: UUID

    /// Environment name
    public var name: String

    /// Emoji for display
    public var emoji: String

    /// Base URL
    public var baseURL: URL

    /// Additional headers for this environment
    public var headers: [String: String]

    /// SSL trust mode
    public var sslTrustMode: EnvironmentSSLMode

    /// Is this the default environment
    public var isDefault: Bool

    /// Environment variables
    public var variables: [String: String]

    /// Notes
    public var notes: String?

    /// Created date
    public var createdAt: Date

    /// Last modified date
    public var modifiedAt: Date

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🌐",
        baseURL: URL,
        headers: [String: String] = [:],
        sslTrustMode: EnvironmentSSLMode = .strict,
        isDefault: Bool = false,
        variables: [String: String] = [:],
        notes: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.baseURL = baseURL
        self.headers = headers
        self.sslTrustMode = sslTrustMode
        self.isDefault = isDefault
        self.variables = variables
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    // MARK: - Convenience Initializers

    /// Create environment from URL string (returns nil if URL is invalid)
    public init?(name: String, urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(name: name, baseURL: url)
    }

    /// Create environment with emoji from URL string (returns nil if URL is invalid)
    public init?(name: String, emoji: String, urlString: String) {
        guard let url = URL(string: urlString) else { return nil }
        self.init(name: name, emoji: emoji, baseURL: url)
    }

    // MARK: - Codable (backward compatibility with sslTrustModeName)

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, baseURL, headers, sslTrustMode, sslTrustModeName
        case isDefault, variables, notes, createdAt, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "🌐"
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]

        // Support both old sslTrustModeName (String) and new sslTrustMode (enum)
        if let mode = try? container.decode(EnvironmentSSLMode.self, forKey: .sslTrustMode) {
            sslTrustMode = mode
        } else if let modeName = try? container.decode(String.self, forKey: .sslTrustModeName) {
            sslTrustMode = EnvironmentSSLMode(rawValue: modeName) ?? .strict
        } else {
            sslTrustMode = .strict
        }

        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        variables = try container.decodeIfPresent([String: String].self, forKey: .variables) ?? [:]
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(headers, forKey: .headers)
        try container.encode(sslTrustMode, forKey: .sslTrustMode)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(variables, forKey: .variables)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
    }

    // MARK: - Computed Properties

    /// Host from base URL
    public var host: String {
        baseURL.host ?? ""
    }

    /// Scheme (http/https)
    public var scheme: String {
        baseURL.scheme ?? "https"
    }

    /// Port
    public var port: Int? {
        baseURL.port
    }

    /// Full base URL as string
    public var baseURLString: String {
        baseURL.absoluteString
    }

    /// Short description for list
    public var displayText: String {
        "\(emoji) \(name)"
    }

    /// Has custom headers configured
    // MARK: - Токен

    /// Заголовки, в которых обычно живёт токен доступа
    public static let tokenHeaderNames = ["authorization", "x-api-key", "x-auth-token", "api-key"]

    /// Токен окружения — значение первого найденного заголовка авторизации.
    ///
    /// Токен физически хранится в `headers`: перехватчик и так подставляет их
    /// в запрос, поэтому отдельного механизма не нужно. Это свойство лишь
    /// даёт ему имя, чтобы токен можно было показать и отредактировать
    /// как самостоятельную сущность, а не искать среди прочих заголовков.
    public var token: String? {
        get {
            for (key, value) in headers where Self.tokenHeaderNames.contains(key.lowercased()) {
                return value
            }
            return nil
        }
        set {
            let existing = headers.keys.first { Self.tokenHeaderNames.contains($0.lowercased()) }

            guard let newValue = newValue, !newValue.isEmpty else {
                if let existing = existing { headers.removeValue(forKey: existing) }
                return
            }

            headers[existing ?? "Authorization"] = newValue
        }
    }

    /// Имя заголовка, в котором лежит токен
    public var tokenHeaderName: String? {
        headers.keys.first { Self.tokenHeaderNames.contains($0.lowercased()) }
    }

    /// У окружения задан свой токен
    public var hasToken: Bool {
        token?.isEmpty == false
    }

    /// Токен для показа: середина скрыта, начало и конец видны,
    /// чтобы отличить один токен от другого, не раскрывая его целиком
    public var maskedToken: String? {
        guard let token = token, !token.isEmpty else { return nil }

        // Схема вроде "Bearer " остаётся видимой — она не секрет
        let parts = token.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let scheme = parts.count == 2 ? String(parts[0]) + " " : ""
        let secret = parts.count == 2 ? String(parts[1]) : token

        guard secret.count > 10 else { return scheme + String(repeating: "•", count: max(secret.count, 3)) }

        return scheme + secret.prefix(4) + "…" + secret.suffix(4)
    }

    public var hasHeaders: Bool {
        !headers.isEmpty
    }

    /// Has variables configured
    public var hasVariables: Bool {
        !variables.isEmpty
    }

    // MARK: - Mutating Methods

    /// Update modified date
    public mutating func touch() {
        modifiedAt = Date()
    }

    /// Add or update header
    public mutating func setHeader(_ value: String, forKey key: String) {
        headers[key] = value
        touch()
    }

    /// Remove header
    public mutating func removeHeader(forKey key: String) {
        headers.removeValue(forKey: key)
        touch()
    }

    /// Add or update variable
    public mutating func setVariable(_ value: String, forKey key: String) {
        variables[key] = value
        touch()
    }

    /// Remove variable
    public mutating func removeVariable(forKey key: String) {
        variables.removeValue(forKey: key)
        touch()
    }
}

// MARK: - Presets

public extension Environment {
    /// Production preset
    static func production(baseURL: URL) -> Environment {
        Environment(
            name: "Production",
            emoji: "🟢",
            baseURL: baseURL,
            sslTrustMode: .strict,
            isDefault: true
        )
    }

    /// Staging preset
    static func staging(baseURL: URL) -> Environment {
        Environment(
            name: "Staging",
            emoji: "🟡",
            baseURL: baseURL,
            sslTrustMode: .strict
        )
    }

    /// Development preset
    static func development(baseURL: URL) -> Environment {
        Environment(
            name: "Development",
            emoji: "🔧",
            baseURL: baseURL,
            sslTrustMode: .allowSelfSigned
        )
    }

    /// Local preset
    static func local(port: Int = 8080) -> Environment? {
        guard let url = URL(string: "http://localhost:\(port)") else { return nil }
        return Environment(
            name: "Local",
            emoji: "💻",
            baseURL: url,
            sslTrustMode: .allowAll
        )
    }

    /// Create from preset type
    static func from(preset: EnvironmentPresetType, baseURL: URL) -> Environment {
        switch preset {
        case .production:
            return production(baseURL: baseURL)
        case .staging:
            return staging(baseURL: baseURL)
        case .development:
            return development(baseURL: baseURL)
        case .local:
            return Environment(
                name: "Local",
                emoji: "💻",
                baseURL: baseURL,
                sslTrustMode: .allowAll
            )
        case .custom:
            return Environment(
                name: "Custom",
                emoji: "⚙️",
                baseURL: baseURL,
                sslTrustMode: .strict
            )
        }
    }
}

// MARK: - Preset Type

public enum EnvironmentPresetType: String, CaseIterable, Sendable {
    case production
    case staging
    case development
    case local
    case custom

    public var displayName: String {
        rawValue.capitalized
    }

    public var defaultEmoji: String {
        switch self {
        case .production: return "🟢"
        case .staging: return "🟡"
        case .development: return "🔧"
        case .local: return "💻"
        case .custom: return "⚙️"
        }
    }

    public var defaultSSLMode: EnvironmentSSLMode {
        switch self {
        case .production, .staging: return .strict
        case .development: return .allowSelfSigned
        case .local, .custom: return .allowAll
        }
    }
}
