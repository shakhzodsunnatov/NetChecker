import Foundation

/// Данные HTTP-запроса
public struct RequestData: Codable, Sendable, Hashable {
    /// URL запроса
    public var url: URL

    /// HTTP-метод
    public var method: HTTPMethod

    /// Заголовки запроса
    public var headers: [String: String]

    /// Тело запроса
    public var body: Data?

    /// Размер тела в байтах
    public var bodySize: Int64

    /// Тип контента
    public var contentType: ContentType?

    /// Политика кэширования
    public var cachePolicy: String

    /// Таймаут запроса
    public var timeoutInterval: TimeInterval

    /// Cookies запроса
    public var cookies: [HTTPCookieData]

    // MARK: - Initialization

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        cachePolicy: String = "default",
        timeoutInterval: TimeInterval = 60,
        cookies: [HTTPCookieData] = []
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.bodySize = Int64(body?.count ?? 0)
        self.contentType = ContentType(headers: headers)
        self.cachePolicy = cachePolicy
        self.timeoutInterval = timeoutInterval
        self.cookies = cookies
    }

    /// Создать из URLRequest
    public init(from request: URLRequest) {
        self.url = request.url ?? URL(string: "about:blank")!
        self.method = HTTPMethod(from: request)
        self.headers = request.allHTTPHeaderFields ?? [:]

        // Try to get body from httpBody first, then from httpBodyStream
        if let httpBody = request.httpBody {
            self.body = httpBody
            self.bodySize = Int64(httpBody.count)
        } else if let bodyStream = request.httpBodyStream {
            // Read from httpBodyStream (used by Alamofire and others)
            let bodyData = Self.readBodyStream(bodyStream)
            self.body = bodyData
            self.bodySize = Int64(bodyData?.count ?? 0)
        } else {
            self.body = nil
            self.bodySize = 0
        }

        self.contentType = ContentType(headers: request.allHTTPHeaderFields)
        self.cachePolicy = Self.cachePolicyString(request.cachePolicy)
        self.timeoutInterval = request.timeoutInterval
        self.cookies = Self.extractCookies(from: request)
    }

    /// Read data from an InputStream
    private static func readBodyStream(_ stream: InputStream) -> Data? {
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else if bytesRead < 0 {
                // Error reading stream
                return nil
            } else {
                // No more data
                break
            }
        }

        return data.isEmpty ? nil : data
    }

    // MARK: - Computed Properties

    /// Хост из URL
    public var host: String {
        url.host ?? ""
    }

    /// Путь из URL
    public var path: String {
        url.path.isEmpty ? "/" : url.path
    }

    /// Схема (http/https)
    public var scheme: String {
        url.scheme ?? "https"
    }

    /// Порт
    public var port: Int? {
        url.port
    }

    /// Query параметры
    public var queryItems: [URLQueryItem] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    /// Тело как строка (UTF-8)
    public var bodyString: String? {
        guard let body = body else { return nil }
        return String(data: body, encoding: .utf8)
    }

    /// Полный URL как строка
    public var urlString: String {
        url.absoluteString
    }

    /// Краткий путь для отображения
    public var displayPath: String {
        var result = path
        if let query = url.query, !query.isEmpty {
            result += "?\(query.prefix(50))"
            if query.count > 50 {
                result += "..."
            }
        }
        return result
    }

    // MARK: - Helper Methods

    private static func cachePolicyString(_ policy: URLRequest.CachePolicy) -> String {
        switch policy {
        case .useProtocolCachePolicy: return "default"
        case .reloadIgnoringLocalCacheData: return "reload"
        case .reloadIgnoringLocalAndRemoteCacheData: return "no-cache"
        case .returnCacheDataElseLoad: return "cache-first"
        case .returnCacheDataDontLoad: return "cache-only"
        case .reloadRevalidatingCacheData: return "revalidate"
        @unknown default: return "unknown"
        }
    }

    private static func extractCookies(from request: URLRequest) -> [HTTPCookieData] {
        guard let url = request.url,
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return []
        }
        return cookies.map { HTTPCookieData(from: $0) }
    }
}

// MARK: - HTTP Cookie Data

public struct HTTPCookieData: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name + (domain ?? "") }

    public var name: String
    public var value: String
    public var domain: String?
    public var path: String?
    public var expiresDate: Date?
    public var isSecure: Bool
    public var isHTTPOnly: Bool

    public init(
        name: String,
        value: String,
        domain: String? = nil,
        path: String? = nil,
        expiresDate: Date? = nil,
        isSecure: Bool = false,
        isHTTPOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    public init(from cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
    }
}

// MARK: - Metadata

public struct TrafficMetadata: Codable, Sendable, Hashable {
    /// Хост
    public var host: String

    /// Путь
    public var path: String

    /// Схема
    public var scheme: String

    /// Порт
    public var port: Int?

    /// Query параметры
    public var queryItems: [QueryItem]

    /// Сторонний ли запрос (не наш бэкенд)
    public var isThirdParty: Bool

    /// Источник SDK (эвристика)
    public var sdkSource: String?

    /// Пользовательские теги
    public var tags: [String]

    public init(
        host: String,
        path: String,
        scheme: String = "https",
        port: Int? = nil,
        queryItems: [QueryItem] = [],
        isThirdParty: Bool = false,
        sdkSource: String? = nil,
        tags: [String] = []
    ) {
        self.host = host
        self.path = path
        self.scheme = scheme
        self.port = port
        self.queryItems = queryItems
        self.isThirdParty = isThirdParty
        self.sdkSource = sdkSource
        self.tags = tags
    }

    public init(from url: URL) {
        self.host = url.host ?? ""
        self.path = url.path.isEmpty ? "/" : url.path
        self.scheme = url.scheme ?? "https"
        self.port = url.port
        self.queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.map { QueryItem(name: $0.name, value: $0.value) } ?? []
        self.isThirdParty = false
        self.sdkSource = nil
        self.tags = []
    }
}

public struct QueryItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}
