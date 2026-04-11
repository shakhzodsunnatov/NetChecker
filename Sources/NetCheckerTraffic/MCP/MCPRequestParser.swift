import Foundation

/// Распарсенный HTTP-запрос от MCP-клиента
struct MCPHTTPRequest: Sendable {
    /// HTTP-метод
    let method: String

    /// Путь запроса
    let path: String

    /// Заголовки
    let headers: [String: String]

    /// Тело запроса
    let body: Data?

    /// Content-Type заголовок
    var contentType: String? {
        headers["content-type"] ?? headers["Content-Type"]
    }

    /// Content-Length заголовок
    var contentLength: Int? {
        if let value = headers["content-length"] ?? headers["Content-Length"] {
            return Int(value)
        }
        return nil
    }

    /// Путь без query string
    var cleanPath: String {
        path.components(separatedBy: "?").first ?? path
    }

    /// Query-параметры
    private var queryParams: [String: String] {
        guard let query = path.components(separatedBy: "?").dropFirst().first else { return [:] }
        var params: [String: String] = [:]
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                params[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return params
    }

    func queryString(_ key: String) -> String? { queryParams[key] }
    func queryInt(_ key: String) -> Int? { queryParams[key].flatMap { Int($0) } }
}

/// HTTP-ответ для MCP-клиента
struct MCPHTTPResponse: Sendable {
    let statusCode: Int
    let statusText: String
    let headers: [String: String]
    let body: Data?

    /// Сериализовать в HTTP/1.1 формат
    func serialize() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"

        var allHeaders = headers
        if let body = body {
            allHeaders["Content-Length"] = "\(body.count)"
        } else {
            allHeaders["Content-Length"] = "0"
        }
        allHeaders["Connection"] = "close"

        for (key, value) in allHeaders {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var data = Data(response.utf8)
        if let body = body {
            data.append(body)
        }
        return data
    }

    // MARK: - Фабрики

    /// JSON-ответ
    static func json(_ object: Any, statusCode: Int = 200) -> MCPHTTPResponse {
        let body = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return MCPHTTPResponse(
            statusCode: statusCode,
            statusText: statusText(for: statusCode),
            headers: [
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            ],
            body: body
        )
    }

    /// JSON-ответ из Encodable
    static func jsonEncodable<T: Encodable>(_ value: T, statusCode: Int = 200) -> MCPHTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try? encoder.encode(value)
        return MCPHTTPResponse(
            statusCode: statusCode,
            statusText: statusText(for: statusCode),
            headers: [
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            ],
            body: body
        )
    }

    /// Ошибка
    static func error(_ message: String, statusCode: Int = 400) -> MCPHTTPResponse {
        json(["error": message], statusCode: statusCode)
    }

    /// CORS preflight
    static func corsOK() -> MCPHTTPResponse {
        MCPHTTPResponse(
            statusCode: 204,
            statusText: "No Content",
            headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Max-Age": "86400"
            ],
            body: nil
        )
    }

    private static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }
}

/// Парсер HTTP-запросов из сырых байтов TCP
enum MCPRequestParser {

    /// Максимальный размер заголовков (64 KB)
    static let maxHeaderSize = 64 * 1024

    /// Разделитель заголовков и тела
    private static let headerBodySeparator = Data("\r\n\r\n".utf8)

    /// Распарсить данные в HTTP-запрос
    /// - Returns: (запрос, оставшиеся байты) или nil при неполных данных
    static func parse(_ data: Data) -> MCPHTTPRequest? {
        // Ищем разделитель заголовков и тела
        guard let separatorRange = data.range(of: headerBodySeparator) else {
            return nil // Заголовки ещё не полностью получены
        }

        let headerData = data[data.startIndex..<separatorRange.lowerBound]

        guard headerData.count <= maxHeaderSize else {
            return nil // Заголовки слишком большие
        }

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        // Парсим request line: "POST /log HTTP/1.1"
        let requestLineParts = lines[0].components(separatedBy: " ")
        guard requestLineParts.count >= 2 else { return nil }

        let method = requestLineParts[0].uppercased()
        let path = requestLineParts[1]

        // Парсим заголовки
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        // Читаем body
        let bodyStart = separatorRange.upperBound
        let body: Data?
        if let contentLength = Int(headers["Content-Length"] ?? headers["content-length"] ?? "0"),
           contentLength > 0 {
            let availableBytes = data.count - (bodyStart - data.startIndex)
            if availableBytes >= contentLength {
                body = data[bodyStart..<(bodyStart + contentLength)]
            } else {
                return nil // Тело ещё не полностью получено
            }
        } else {
            let remaining = data[bodyStart...]
            body = remaining.isEmpty ? nil : Data(remaining)
        }

        return MCPHTTPRequest(
            method: method,
            path: path,
            headers: headers,
            body: body
        )
    }
}
