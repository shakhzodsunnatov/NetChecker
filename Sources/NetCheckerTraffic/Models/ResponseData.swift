import Foundation

/// Данные HTTP-ответа
public struct ResponseData: Codable, Sendable, Hashable {
    /// HTTP статус-код
    public var statusCode: Int

    /// Категория статуса
    public var statusCategory: StatusCategory

    /// Заголовки ответа
    public var headers: [String: String]

    /// Тело ответа
    public var body: Data?

    /// Размер тела в байтах
    public var bodySize: Int64

    /// Тип контента
    public var contentType: ContentType?

    /// MIME-тип
    public var mimeType: String?

    /// Ответ из кэша
    public var isFromCache: Bool

    /// Cookies из ответа (Set-Cookie)
    public var cookies: [HTTPCookieData]

    /// URL после редиректов
    public var finalURL: URL?

    // MARK: - Initialization

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data? = nil,
        mimeType: String? = nil,
        isFromCache: Bool = false,
        cookies: [HTTPCookieData] = [],
        finalURL: URL? = nil
    ) {
        self.statusCode = statusCode
        self.statusCategory = StatusCategory(statusCode: statusCode)
        self.headers = headers
        self.body = body
        self.bodySize = Int64(body?.count ?? 0)
        self.contentType = ContentType(headers: headers)
        self.mimeType = mimeType ?? headers["Content-Type"]
        self.isFromCache = isFromCache
        self.cookies = cookies
        self.finalURL = finalURL
    }

    /// Создать из HTTPURLResponse
    public init(from response: HTTPURLResponse, body: Data?, isFromCache: Bool = false) {
        self.statusCode = response.statusCode
        self.statusCategory = StatusCategory(statusCode: response.statusCode)

        // Extract headers
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let keyStr = key as? String, let valueStr = value as? String {
                headers[keyStr] = valueStr
            }
        }
        self.headers = headers

        self.body = body
        self.bodySize = Int64(body?.count ?? 0)
        self.contentType = ContentType(mimeType: response.mimeType)
        self.mimeType = response.mimeType
        self.isFromCache = isFromCache
        self.finalURL = response.url

        // Extract cookies from Set-Cookie headers
        if let url = response.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            self.cookies = cookies.map { HTTPCookieData(from: $0) }
        } else {
            self.cookies = []
        }
    }

    // MARK: - Computed Properties

    /// Статус сообщение
    public var statusMessage: String {
        HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }

    /// Полный статус (код + сообщение)
    public var fullStatus: String {
        "\(statusCode) \(statusMessage)"
    }

    /// Тело как строка (UTF-8)
    public var bodyString: String? {
        guard let body = body else { return nil }
        return String(data: body, encoding: .utf8)
    }

    /// Является ли ответ успешным
    public var isSuccess: Bool {
        statusCategory.isSuccess
    }

    /// Является ли ответ ошибкой
    public var isError: Bool {
        statusCategory.isError
    }

    /// Является ли ответ редиректом
    public var isRedirect: Bool {
        statusCategory == .redirect
    }

    /// Content-Length из заголовков
    public var contentLength: Int64? {
        if let lengthStr = headers["Content-Length"] ?? headers["content-length"],
           let length = Int64(lengthStr) {
            return length
        }
        return nil
    }

    /// Server заголовок
    public var serverInfo: String? {
        headers["Server"] ?? headers["server"]
    }

    /// Date заголовок
    public var dateHeader: String? {
        headers["Date"] ?? headers["date"]
    }

    /// Cache-Control заголовок
    public var cacheControl: String? {
        headers["Cache-Control"] ?? headers["cache-control"]
    }

    /// ETag заголовок
    public var etag: String? {
        headers["ETag"] ?? headers["etag"]
    }

    /// Last-Modified заголовок
    public var lastModified: String? {
        headers["Last-Modified"] ?? headers["last-modified"]
    }

    /// Форматированный размер
    public var formattedBodySize: String {
        ByteCountFormatter.string(fromByteCount: bodySize, countStyle: .file)
    }
}

// MARK: - Redirect Hop

public struct RedirectHop: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(fromURL.absoluteString)-\(toURL.absoluteString)" }

    /// Исходный URL
    public var fromURL: URL

    /// Целевой URL
    public var toURL: URL

    /// Статус-код редиректа
    public var statusCode: Int

    /// Заголовки ответа редиректа
    public var headers: [String: String]

    /// Временная метка
    public var timestamp: Date

    public init(
        fromURL: URL,
        toURL: URL,
        statusCode: Int,
        headers: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.fromURL = fromURL
        self.toURL = toURL
        self.statusCode = statusCode
        self.headers = headers
        self.timestamp = timestamp
    }

    /// Тип редиректа
    public var redirectType: RedirectType {
        RedirectType(statusCode: statusCode)
    }
}

// MARK: - Redirect Type

public enum RedirectType: String, Codable, Sendable {
    case movedPermanently // 301
    case found // 302
    case seeOther // 303
    case temporaryRedirect // 307
    case permanentRedirect // 308
    case other

    public init(statusCode: Int) {
        switch statusCode {
        case 301: self = .movedPermanently
        case 302: self = .found
        case 303: self = .seeOther
        case 307: self = .temporaryRedirect
        case 308: self = .permanentRedirect
        default: self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .movedPermanently: return "Moved Permanently (301)"
        case .found: return "Found (302)"
        case .seeOther: return "See Other (303)"
        case .temporaryRedirect: return "Temporary Redirect (307)"
        case .permanentRedirect: return "Permanent Redirect (308)"
        case .other: return "Other Redirect"
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .movedPermanently, .permanentRedirect:
            return true
        default:
            return false
        }
    }
}
