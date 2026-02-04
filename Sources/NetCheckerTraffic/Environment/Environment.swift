import Foundation

/// Модель окружения (Production, Staging, Development, etc.)
public struct Environment: Codable, Sendable, Identifiable, Hashable {
    /// Уникальный идентификатор
    public var id: UUID

    /// Название окружения
    public var name: String

    /// Emoji для отображения
    public var emoji: String

    /// Базовый URL
    public var baseURL: URL

    /// Дополнительные заголовки для этого окружения
    public var headers: [String: String]

    /// Режим SSL
    public var sslTrustModeName: String

    /// Является ли окружением по умолчанию
    public var isDefault: Bool

    /// Переменные окружения
    public var variables: [String: String]

    /// Заметки
    public var notes: String?

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🌐",
        baseURL: URL,
        headers: [String: String] = [:],
        sslTrustModeName: String = "strict",
        isDefault: Bool = false,
        variables: [String: String] = [:],
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.baseURL = baseURL
        self.headers = headers
        self.sslTrustModeName = sslTrustModeName
        self.isDefault = isDefault
        self.variables = variables
        self.notes = notes
    }

    // MARK: - Convenience Initializers

    public init(name: String, url: String) {
        self.init(
            name: name,
            baseURL: URL(string: url)!
        )
    }

    public init(name: String, emoji: String, url: String) {
        self.init(
            name: name,
            emoji: emoji,
            baseURL: URL(string: url)!
        )
    }

    // MARK: - Computed Properties

    /// Хост из базового URL
    public var host: String {
        baseURL.host ?? ""
    }

    /// Схема (http/https)
    public var scheme: String {
        baseURL.scheme ?? "https"
    }

    /// Порт
    public var port: Int? {
        baseURL.port
    }

    /// Полный базовый URL как строка
    public var baseURLString: String {
        baseURL.absoluteString
    }

    /// Краткое описание для списка
    public var displayText: String {
        "\(emoji) \(name)"
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
            sslTrustModeName: "strict",
            isDefault: true
        )
    }

    /// Staging preset
    static func staging(baseURL: URL) -> Environment {
        Environment(
            name: "Staging",
            emoji: "🟡",
            baseURL: baseURL,
            sslTrustModeName: "strict"
        )
    }

    /// Development preset
    static func development(baseURL: URL) -> Environment {
        Environment(
            name: "Development",
            emoji: "🔧",
            baseURL: baseURL,
            sslTrustModeName: "allowSelfSigned"
        )
    }

    /// Local preset
    static func local(baseURL: URL) -> Environment {
        Environment(
            name: "Local",
            emoji: "💻",
            baseURL: baseURL,
            sslTrustModeName: "allowAll"
        )
    }
}
