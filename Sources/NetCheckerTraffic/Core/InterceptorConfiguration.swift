import Foundation

/// Конфигурация перехватчика трафика
public struct InterceptorConfiguration: Sendable {
    // MARK: - Interception Level

    /// Уровень перехвата
    public var level: InterceptionLevel

    /// Включать в Release build (опасно!)
    public var enableInRelease: Bool

    // MARK: - Capture Filters

    /// Перехватывать только эти хосты (nil = все)
    public var captureHosts: Set<String>?

    /// Игнорировать эти хосты
    public var ignoreHosts: Set<String>

    /// Перехватывать только эти методы (nil = все)
    public var captureMethods: Set<HTTPMethod>?

    /// Игнорировать пути по regex паттернам
    public var ignorePathPatterns: [String]

    /// Минимальный размер body для захвата (0 = всё)
    public var minBodySizeToCapture: Int

    /// Максимальный размер body для захвата (bytes)
    public var maxBodySizeToCapture: Int

    // MARK: - Storage

    /// Максимальное количество записей
    public var maxRecords: Int

    /// Сохранять на диск
    public var persistToDisk: Bool

    /// Период хранения (nil = бесконечно)
    public var retentionPeriod: TimeInterval?

    /// Захватывать тело ответа
    public var captureResponseBody: Bool

    /// Захватывать тело запроса
    public var captureRequestBody: Bool

    // MARK: - Security / Redaction

    /// Заголовки для редактирования (маскировки)
    public var redactHeaders: Set<String>

    /// JSON поля для редактирования
    public var redactBodyFields: Set<String>

    /// Query параметры для редактирования
    public var redactQueryParams: Set<String>

    /// Строка замены для редактирования
    public var redactionString: String

    // MARK: - SSL Configuration

    /// SSL конфигурация
    public var ssl: SSLConfiguration

    // MARK: - UI

    /// Включить жест встряхивания для открытия
    public var enableShakeGesture: Bool

    /// Показывать floating badge
    public var showFloatingBadge: Bool

    /// Уведомлять при ошибках
    public var enableNotificationOnError: Bool

    // MARK: - Callbacks

    /// Динамическая фильтрация (вызывается для каждого запроса)
    public var shouldIntercept: (@Sendable (URLRequest) -> Bool)?

    // MARK: - Initialization

    public init(
        level: InterceptionLevel = .full,
        enableInRelease: Bool = false,
        captureHosts: Set<String>? = nil,
        ignoreHosts: Set<String> = [],
        captureMethods: Set<HTTPMethod>? = nil,
        ignorePathPatterns: [String] = [],
        minBodySizeToCapture: Int = 0,
        maxBodySizeToCapture: Int = 10 * 1024 * 1024, // 10 MB
        maxRecords: Int = 1000,
        persistToDisk: Bool = false,
        retentionPeriod: TimeInterval? = nil,
        captureResponseBody: Bool = true,
        captureRequestBody: Bool = true,
        redactHeaders: Set<String>? = nil,
        redactBodyFields: Set<String>? = nil,
        redactQueryParams: Set<String>? = nil,
        redactionString: String = "***REDACTED***",
        ssl: SSLConfiguration = SSLConfiguration(),
        enableShakeGesture: Bool = true,
        showFloatingBadge: Bool = false,
        enableNotificationOnError: Bool = true,
        shouldIntercept: (@Sendable (URLRequest) -> Bool)? = nil
    ) {
        self.level = level
        self.enableInRelease = enableInRelease
        self.captureHosts = captureHosts
        self.ignoreHosts = ignoreHosts
        self.captureMethods = captureMethods
        self.ignorePathPatterns = ignorePathPatterns
        self.minBodySizeToCapture = minBodySizeToCapture
        self.maxBodySizeToCapture = maxBodySizeToCapture
        self.maxRecords = maxRecords
        self.persistToDisk = persistToDisk
        self.retentionPeriod = retentionPeriod
        self.captureResponseBody = captureResponseBody
        self.captureRequestBody = captureRequestBody
        self.redactHeaders = redactHeaders ?? HeaderFormatter.sensitiveHeaders
        self.redactBodyFields = redactBodyFields ?? JSONFormatter.sensitiveFields
        self.redactQueryParams = redactQueryParams ?? ["api_key", "apikey", "access_token", "secret", "key"]
        self.redactionString = redactionString
        self.ssl = ssl
        self.enableShakeGesture = enableShakeGesture
        self.showFloatingBadge = showFloatingBadge
        self.enableNotificationOnError = enableNotificationOnError
        self.shouldIntercept = shouldIntercept
    }

    // MARK: - Presets

    /// Конфигурация по умолчанию
    public static var `default`: InterceptorConfiguration {
        InterceptorConfiguration()
    }

    /// Минимальная конфигурация (только базовый перехват)
    public static var minimal: InterceptorConfiguration {
        InterceptorConfiguration(
            level: .basic,
            captureResponseBody: false,
            captureRequestBody: false
        )
    }

    /// Полная конфигурация для отладки
    public static var debug: InterceptorConfiguration {
        InterceptorConfiguration(
            level: .full,
            showFloatingBadge: true,
            enableNotificationOnError: true
        )
    }
}

// MARK: - Interception Level

public enum InterceptionLevel: String, Sendable, CaseIterable {
    /// Базовый: только URLSession.shared
    case basic

    /// Полный: все URLSession через swizzling
    case full

    /// Ручной: только явно настроенные URLSession
    case manual

    public var displayName: String {
        switch self {
        case .basic: return "Basic (shared session only)"
        case .full: return "Full (all sessions)"
        case .manual: return "Manual (explicit only)"
        }
    }

    public var description: String {
        switch self {
        case .basic:
            return "Intercepts only URLSession.shared requests"
        case .full:
            return "Intercepts all URLSession requests via method swizzling"
        case .manual:
            return "Only intercepts explicitly configured sessions"
        }
    }
}

// MARK: - SSL Configuration

public struct SSLConfiguration: Sendable {
    /// Режим доверия SSL
    public var trustMode: SSLTrustMode

    /// Логировать детали сертификата
    public var logCertificateDetails: Bool

    /// Показывать SSL warnings в UI
    public var showSSLWarningsInUI: Bool

    /// Bypass SSL pinning для указанных хостов (только DEBUG)
    public var bypassPinningForHosts: Set<String>

    public init(
        trustMode: SSLTrustMode = .strict,
        logCertificateDetails: Bool = true,
        showSSLWarningsInUI: Bool = true,
        bypassPinningForHosts: Set<String> = []
    ) {
        self.trustMode = trustMode
        self.logCertificateDetails = logCertificateDetails
        self.showSSLWarningsInUI = showSSLWarningsInUI
        self.bypassPinningForHosts = bypassPinningForHosts
    }
}

// MARK: - SSL Trust Mode

public enum SSLTrustMode: Sendable {
    /// Стандартная iOS проверка
    case strict

    /// Разрешить самоподписанные для указанных хостов
    case allowSelfSigned(hosts: Set<String>)

    /// Разрешить просроченные для указанных хостов
    case allowExpired(hosts: Set<String>)

    /// Разрешить несоответствие hostname для указанных хостов
    case allowInvalidHost(hosts: Set<String>)

    /// Отключить ВСЮ проверку (ОПАСНО, только DEBUG)
    case allowAll(iUnderstandTheRisk: Bool)

    /// Режим для работы с прокси (Charles/Proxyman)
    case allowProxy(proxyHosts: Set<String>)

    /// Кастомная проверка
    case custom(@Sendable (SecTrust, String) -> Bool)

    public var displayName: String {
        switch self {
        case .strict: return "Strict"
        case .allowSelfSigned: return "Allow Self-Signed"
        case .allowExpired: return "Allow Expired"
        case .allowInvalidHost: return "Allow Invalid Host"
        case .allowAll: return "Allow All (UNSAFE)"
        case .allowProxy: return "Proxy Mode"
        case .custom: return "Custom"
        }
    }

    /// Является ли режим небезопасным
    public var isUnsafe: Bool {
        switch self {
        case .strict, .custom:
            return false
        case .allowSelfSigned, .allowExpired, .allowInvalidHost, .allowAll, .allowProxy:
            return true
        }
    }
}
