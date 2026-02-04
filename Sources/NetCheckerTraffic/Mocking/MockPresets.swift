import Foundation

/// Готовые пресеты моков
public struct MockPresets {
    // MARK: - HTTP Errors

    /// 500 Internal Server Error
    public static var serverError: MockResponse {
        MockResponse.json(
            #"{"error": "Internal Server Error", "code": 500}"#,
            statusCode: 500
        )
    }

    /// 404 Not Found
    public static var notFound: MockResponse {
        MockResponse.json(
            #"{"error": "Not Found", "code": 404}"#,
            statusCode: 404
        )
    }

    /// 401 Unauthorized
    public static var unauthorized: MockResponse {
        MockResponse.json(
            #"{"error": "Unauthorized", "code": 401}"#,
            statusCode: 401
        )
    }

    /// 403 Forbidden
    public static var forbidden: MockResponse {
        MockResponse.json(
            #"{"error": "Forbidden", "code": 403}"#,
            statusCode: 403
        )
    }

    /// 429 Too Many Requests
    public static var tooManyRequests: MockResponse {
        MockResponse(
            statusCode: 429,
            headers: [
                "Content-Type": "application/json",
                "Retry-After": "60"
            ],
            body: #"{"error": "Too Many Requests", "code": 429, "retryAfter": 60}"#.data(using: .utf8)
        )
    }

    /// 503 Service Unavailable
    public static var serviceUnavailable: MockResponse {
        MockResponse.json(
            #"{"error": "Service Unavailable", "code": 503}"#,
            statusCode: 503
        )
    }

    /// 502 Bad Gateway
    public static var badGateway: MockResponse {
        MockResponse.json(
            #"{"error": "Bad Gateway", "code": 502}"#,
            statusCode: 502
        )
    }

    /// 504 Gateway Timeout
    public static var gatewayTimeout: MockResponse {
        MockResponse.json(
            #"{"error": "Gateway Timeout", "code": 504}"#,
            statusCode: 504
        )
    }

    // MARK: - Network Errors

    /// No Connection
    public static var noConnection: MockError {
        .noConnection
    }

    /// Timeout
    public static var timeout: MockError {
        .timeout
    }

    /// DNS Failure
    public static var dnsFailure: MockError {
        .dnsFailure
    }

    /// SSL Error
    public static var sslError: MockError {
        .sslError
    }

    // MARK: - Delays

    /// Slow response (5 seconds)
    public static var slowResponse: MockAction {
        .delay(seconds: 5.0)
    }

    /// Very slow response (10 seconds)
    public static var verySlowResponse: MockAction {
        .delay(seconds: 10.0)
    }

    /// Custom delay
    public static func delay(_ seconds: TimeInterval) -> MockAction {
        .delay(seconds: seconds)
    }

    // MARK: - Empty Responses

    /// Empty response (200 OK)
    public static var emptyResponse: MockResponse {
        MockResponse.empty(statusCode: 200)
    }

    /// Empty array []
    public static var emptyArray: MockResponse {
        MockResponse.json("[]")
    }

    /// Empty object {}
    public static var emptyObject: MockResponse {
        MockResponse.json("{}")
    }

    // MARK: - Convenience Methods

    /// Create error response with message
    public static func error(
        statusCode: Int,
        message: String,
        code: String? = nil
    ) -> MockResponse {
        var json: [String: Any] = [
            "error": message,
            "statusCode": statusCode
        ]
        if let code = code {
            json["code"] = code
        }

        if let data = try? JSONSerialization.data(withJSONObject: json) {
            return MockResponse(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: data
            )
        }

        return MockResponse(statusCode: statusCode)
    }

    /// Create success response with JSON
    public static func success(json: String) -> MockResponse {
        MockResponse.json(json, statusCode: 200)
    }

    /// Create success response with encodable object
    public static func success<T: Encodable>(_ object: T) -> MockResponse? {
        MockResponse.json(object, statusCode: 200)
    }

    /// Create paginated response
    public static func paginated(
        items: [Any],
        page: Int = 1,
        totalPages: Int = 1,
        totalItems: Int? = nil
    ) -> MockResponse? {
        let response: [String: Any] = [
            "items": items,
            "page": page,
            "totalPages": totalPages,
            "totalItems": totalItems ?? items.count
        ]

        if let data = try? JSONSerialization.data(withJSONObject: response) {
            return MockResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: data
            )
        }

        return nil
    }
}

// MARK: - Quick Mock Rules

public extension MockRule {
    /// 500 Error для URL
    static func serverError(for urlPattern: String) -> MockRule {
        MockRule(
            name: "Server Error",
            matching: .url(urlPattern),
            action: .respond(MockPresets.serverError)
        )
    }

    /// 404 Not Found для URL
    static func notFound(for urlPattern: String) -> MockRule {
        MockRule(
            name: "Not Found",
            matching: .url(urlPattern),
            action: .respond(MockPresets.notFound)
        )
    }

    /// 401 Unauthorized для URL
    static func unauthorized(for urlPattern: String) -> MockRule {
        MockRule(
            name: "Unauthorized",
            matching: .url(urlPattern),
            action: .respond(MockPresets.unauthorized)
        )
    }

    /// Timeout для URL
    static func timeout(for urlPattern: String) -> MockRule {
        MockRule(
            name: "Timeout",
            matching: .url(urlPattern),
            action: .error(.timeout)
        )
    }

    /// No Connection для URL
    static func noConnection(for urlPattern: String) -> MockRule {
        MockRule(
            name: "No Connection",
            matching: .url(urlPattern),
            action: .error(.noConnection)
        )
    }

    /// Empty array для URL
    static func emptyList(for urlPattern: String) -> MockRule {
        MockRule(
            name: "Empty List",
            matching: .url(urlPattern),
            action: .respond(MockPresets.emptyArray)
        )
    }

    /// Slow response для URL
    static func slow(for urlPattern: String, delay: TimeInterval = 5.0) -> MockRule {
        MockRule(
            name: "Slow Response",
            matching: .url(urlPattern),
            action: .delay(seconds: delay)
        )
    }
}
