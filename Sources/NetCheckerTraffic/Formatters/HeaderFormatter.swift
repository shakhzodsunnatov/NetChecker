import Foundation

/// Форматирование HTTP заголовков
public struct HeaderFormatter {
    /// Форматировать заголовки в строку
    public static func format(headers: [String: String], redact: Set<String> = []) -> String {
        headers.map { key, value in
            let displayValue = redact.contains(key.lowercased()) ? "***REDACTED***" : value
            return "\(key): \(displayValue)"
        }.sorted().joined(separator: "\n")
    }

    /// Форматировать заголовки для отображения в таблице
    public static func formatTable(headers: [String: String], redact: Set<String> = []) -> [(key: String, value: String)] {
        headers.map { key, value in
            let displayValue = redact.contains(key.lowercased()) ? "***REDACTED***" : value
            return (key: key, value: displayValue)
        }.sorted { $0.key < $1.key }
    }

    /// Стандартные заголовки для редактирования
    public static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "proxy-authorization",
        "www-authenticate",
        "x-csrf-token",
        "x-xsrf-token"
    ]

    /// Редактировать sensitive заголовки
    public static func redact(headers: [String: String], fields: Set<String>? = nil) -> [String: String] {
        let fieldsToRedact = fields ?? sensitiveHeaders
        var result = headers

        for key in headers.keys {
            if fieldsToRedact.contains(key.lowercased()) {
                result[key] = "***REDACTED***"
            }
        }

        return result
    }

    /// Частичное редактирование (показать первые N символов)
    public static func partialRedact(value: String, showFirst: Int = 5) -> String {
        if value.count <= showFirst {
            return "***"
        }
        return String(value.prefix(showFirst)) + "***"
    }
}
