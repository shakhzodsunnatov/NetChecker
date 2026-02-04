import Foundation

/// Форматирование JSON
public struct JSONFormatter {
    /// Pretty-print JSON с отступами
    public static func format(_ data: Data, indent: Int = 2) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return nil
        }

        guard let prettyData = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return nil
        }

        return String(data: prettyData, encoding: .utf8)
    }

    /// Pretty-print JSON из строки
    public static func format(_ string: String, indent: Int = 2) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        return format(data, indent: indent)
    }

    /// Минифицировать JSON
    public static func minify(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
            return nil
        }

        guard let minifiedData = try? JSONSerialization.data(withJSONObject: json, options: []) else {
            return nil
        }

        return String(data: minifiedData, encoding: .utf8)
    }

    /// Проверить, является ли строка валидным JSON
    public static func isValid(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return isValid(data)
    }

    /// Проверить, является ли Data валидным JSON
    public static func isValid(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }

    /// Редактировать sensitive поля в JSON
    public static func redact(_ data: Data, fields: Set<String>) -> Data? {
        guard var json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) else {
            return nil
        }

        json = redactObject(json, fields: fields)

        return try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    private static func redactObject(_ object: Any, fields: Set<String>) -> Any {
        if var dict = object as? [String: Any] {
            for key in dict.keys {
                if fields.contains(key.lowercased()) {
                    dict[key] = "***REDACTED***"
                } else if let value = dict[key] {
                    dict[key] = redactObject(value, fields: fields)
                }
            }
            return dict
        } else if let array = object as? [Any] {
            return array.map { redactObject($0, fields: fields) }
        }
        return object
    }

    /// Стандартные поля для редактирования
    public static let sensitiveFields: Set<String> = [
        "password",
        "passwd",
        "pass",
        "token",
        "access_token",
        "refresh_token",
        "secret",
        "client_secret",
        "api_key",
        "apikey",
        "ssn",
        "social_security",
        "credit_card",
        "card_number",
        "cvv",
        "pin",
        "pin_code"
    ]

    /// Извлечь значение по JSON path
    public static func value(at path: String, in data: Data) -> Any? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        let components = path.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            if let dict = current as? [String: Any] {
                guard let next = dict[component] else { return nil }
                current = next
            } else if let array = current as? [Any], let index = Int(component), index < array.count {
                current = array[index]
            } else {
                return nil
            }
        }

        return current
    }
}
