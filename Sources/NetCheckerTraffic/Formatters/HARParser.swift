import Foundation

/// Ошибка разбора HAR-файла
public enum HARParseError: LocalizedError, Equatable {
    case notJSON
    case missingLog
    case unsupportedVersion(String)
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .notJSON:
            return "Файл не является корректным JSON"
        case .missingLog:
            return "В файле отсутствует секция log"
        case .unsupportedVersion(let version):
            return "Неподдерживаемая версия HAR: \(version)"
        case .noEntries:
            return "В файле нет ни одной записи"
        }
    }
}

// MARK: - Модель разбора

/// Модели ниже намеренно отделены от моделей `HARFormatter`.
///
/// Экспорт формирует строго определённую структуру, где все поля обязательны.
/// Импорт же принимает файлы Chrome DevTools, Safari Web Inspector, Charles и
/// Proxyman, каждый из которых опускает свой набор необязательных полей.
/// Ослабление экспортных моделей ради импорта лишило бы экспорт типовой строгости,
/// поэтому здесь отдельная, максимально снисходительная модель.

struct ParsedHAR: Decodable {
    let log: ParsedHARLog
}

struct ParsedHARLog: Decodable {
    let version: String?
    let entries: [ParsedHAREntry]?
}

struct ParsedHAREntry: Decodable {
    let startedDateTime: String?
    let time: Double?
    let request: ParsedHARRequest
    let response: ParsedHARResponse?
}

struct ParsedHARRequest: Decodable {
    let method: String?
    let url: String
    let headers: [ParsedHARNameValue]?
    let postData: ParsedHARPostData?
}

struct ParsedHARResponse: Decodable {
    let status: Int?
    let headers: [ParsedHARNameValue]?
    let content: ParsedHARContent?
}

struct ParsedHARNameValue: Decodable {
    let name: String
    let value: String?
}

struct ParsedHARPostData: Decodable {
    let mimeType: String?
    let text: String?
}

struct ParsedHARContent: Decodable {
    let size: Int?
    let mimeType: String?
    let text: String?
    let encoding: String?

    /// Тело ответа с учётом base64-кодирования
    var decodedBody: Data? {
        guard let text = text, !text.isEmpty else { return nil }

        if encoding?.lowercased() == "base64" {
            return Data(base64Encoded: text) ?? Data(text.utf8)
        }
        return Data(text.utf8)
    }
}

// MARK: - Парсер

/// Разбор файлов в формате HAR 1.2
public enum HARParser {

    /// Разобрать HAR и получить записи трафика
    public static func parse(_ data: Data) throws -> [TrafficRecord] {
        let har: ParsedHAR
        do {
            har = try JSONDecoder().decode(ParsedHAR.self, from: data)
        } catch let error as DecodingError {
            // Отличаем «не тот JSON» от «вообще не JSON»
            if case .keyNotFound = error { throw HARParseError.missingLog }
            if (try? JSONSerialization.jsonObject(with: data)) != nil {
                throw HARParseError.missingLog
            }
            throw HARParseError.notJSON
        } catch {
            throw HARParseError.notJSON
        }

        if let version = har.log.version, !version.hasPrefix("1.") {
            throw HARParseError.unsupportedVersion(version)
        }

        guard let entries = har.log.entries, !entries.isEmpty else {
            throw HARParseError.noEntries
        }

        let records = entries.compactMap(record(from:))
        guard !records.isEmpty else { throw HARParseError.noEntries }

        return records
    }

    // MARK: - Private

    private static func record(from entry: ParsedHAREntry) -> TrafficRecord? {
        guard let url = URL(string: entry.request.url), url.host != nil else { return nil }

        let request = RequestData(
            url: url,
            method: HTTPMethod(rawValue: (entry.request.method ?? "GET").uppercased()) ?? .get,
            headers: headers(from: entry.request.headers),
            body: entry.request.postData?.text.map { Data($0.utf8) }
        )

        var response: ResponseData?
        if let harResponse = entry.response, let status = harResponse.status, status > 0 {
            response = ResponseData(
                statusCode: status,
                headers: headers(from: harResponse.headers),
                body: harResponse.content?.decodedBody,
                mimeType: harResponse.content?.mimeType
            )
        }

        var metadata = TrafficMetadata(from: url)
        metadata.tags = ["imported", "har"]
        metadata.sdkSource = "HAR import"

        return TrafficRecord(
            timestamp: date(from: entry.startedDateTime),
            duration: (entry.time ?? 0) / 1000, // HAR хранит миллисекунды
            state: response == nil ? .pending : .completed,
            request: request,
            response: response,
            metadata: metadata
        )
    }

    private static func headers(from list: [ParsedHARNameValue]?) -> [String: String] {
        guard let list = list else { return [:] }

        var result: [String: String] = [:]
        for item in list {
            // Заголовки HTTP/2 начинаются с двоеточия и не являются настоящими заголовками
            guard !item.name.hasPrefix(":") else { continue }
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private static func date(from string: String?) -> Date {
        guard let string = string else { return Date() }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string) ?? Date()
    }
}
