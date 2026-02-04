import Foundation

/// Форматирование запроса в cURL команду
public struct CURLFormatter {
    /// Конвертировать TrafficRecord в cURL команду
    public static func format(record: TrafficRecord, redactSensitive: Bool = true) -> String {
        format(request: record.request, redactSensitive: redactSensitive)
    }

    /// Конвертировать RequestData в cURL команду
    public static func format(request: RequestData, redactSensitive: Bool = true) -> String {
        format(
            url: request.url,
            method: request.method,
            headers: request.headers,
            body: request.body,
            redactSensitive: redactSensitive
        )
    }

    /// Конвертировать URLRequest в cURL команду
    public static func format(urlRequest: URLRequest, redactSensitive: Bool = true) -> String {
        format(
            url: urlRequest.url ?? URL(string: "about:blank")!,
            method: HTTPMethod(from: urlRequest),
            headers: urlRequest.allHTTPHeaderFields ?? [:],
            body: urlRequest.httpBody,
            redactSensitive: redactSensitive
        )
    }

    /// Основной метод форматирования
    public static func format(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        body: Data?,
        redactSensitive: Bool = true
    ) -> String {
        var parts: [String] = ["curl"]

        // Method
        if method != .get {
            parts.append("-X \(method.rawValue)")
        }

        // URL
        parts.append("'\(url.absoluteString)'")

        // Headers
        let headersToUse = redactSensitive ? redactHeaders(headers) : headers
        for (key, value) in headersToUse.sorted(by: { $0.key < $1.key }) {
            let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-H '\(key): \(escapedValue)'")
        }

        // Body
        if let body = body, !body.isEmpty {
            if let bodyString = String(data: body, encoding: .utf8) {
                let processedBody = redactSensitive ? redactBody(bodyString) : bodyString
                let escapedBody = processedBody.replacingOccurrences(of: "'", with: "'\\''")
                parts.append("-d '\(escapedBody)'")
            } else {
                parts.append("--data-binary @<file>")
            }
        }

        return parts.joined(separator: " \\\n  ")
    }

    /// Форматировать в одну строку
    public static func formatOneLine(
        url: URL,
        method: HTTPMethod,
        headers: [String: String],
        body: Data?,
        redactSensitive: Bool = true
    ) -> String {
        format(url: url, method: method, headers: headers, body: body, redactSensitive: redactSensitive)
            .replacingOccurrences(of: " \\\n  ", with: " ")
    }

    // MARK: - Private

    private static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "x-api-key",
        "x-auth-token"
    ]

    private static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var result = headers
        for key in headers.keys {
            if sensitiveHeaders.contains(key.lowercased()) {
                if let value = result[key] {
                    // Show type of auth but redact value
                    if value.lowercased().hasPrefix("bearer ") {
                        result[key] = "Bearer ***"
                    } else if value.lowercased().hasPrefix("basic ") {
                        result[key] = "Basic ***"
                    } else {
                        result[key] = "***"
                    }
                }
            }
        }
        return result
    }

    private static let sensitiveBodyFields: Set<String> = [
        "password",
        "passwd",
        "token",
        "secret",
        "api_key",
        "credit_card"
    ]

    private static func redactBody(_ body: String) -> String {
        // Try to parse as JSON and redact
        if let data = body.data(using: .utf8),
           let redacted = JSONFormatter.redact(data, fields: sensitiveBodyFields),
           let result = String(data: redacted, encoding: .utf8) {
            return result
        }

        // For form-urlencoded, redact sensitive fields
        if body.contains("=") && body.contains("&") {
            var components = URLComponents()
            components.query = body

            if var items = components.queryItems {
                items = items.map { item in
                    if sensitiveBodyFields.contains(item.name.lowercased()) {
                        return URLQueryItem(name: item.name, value: "***REDACTED***")
                    }
                    return item
                }
                components.queryItems = items
                return components.query ?? body
            }
        }

        return body
    }
}
