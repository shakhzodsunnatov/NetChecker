import Foundation

/// Форматирование в HAR (HTTP Archive) формат
public struct HARFormatter {
    /// Конвертировать записи в HAR Data
    public static func format(records: [TrafficRecord]) -> Data? {
        let har = HAR(
            log: HARLog(
                version: "1.2",
                creator: HARCreator(
                    name: "NetChecker",
                    version: "1.0"
                ),
                entries: records.map { HAREntry(from: $0) }
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try? encoder.encode(har)
    }

    /// Конвертировать одну запись в HAR Data
    public static func format(record: TrafficRecord) -> Data? {
        format(records: [record])
    }
}

// MARK: - HAR Models

private struct HAR: Codable {
    let log: HARLog
}

private struct HARLog: Codable {
    let version: String
    let creator: HARCreator
    let entries: [HAREntry]
}

private struct HARCreator: Codable {
    let name: String
    let version: String
}

private struct HAREntry: Codable {
    let startedDateTime: String
    let time: Double
    let request: HARRequest
    let response: HARResponse
    let cache: HARCache
    let timings: HARTimings

    init(from record: TrafficRecord) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.startedDateTime = formatter.string(from: record.timestamp)
        self.time = record.duration * 1000 // Convert to ms

        self.request = HARRequest(from: record.request)
        self.response = HARResponse(from: record.response)
        self.cache = HARCache()
        self.timings = HARTimings(from: record.timings)
    }
}

private struct HARRequest: Codable {
    let method: String
    let url: String
    let httpVersion: String
    let cookies: [HARCookie]
    let headers: [HARHeader]
    let queryString: [HARQueryParam]
    let postData: HARPostData?
    let headersSize: Int
    let bodySize: Int

    init(from request: RequestData) {
        self.method = request.method.rawValue
        self.url = request.url.absoluteString
        self.httpVersion = "HTTP/1.1"
        self.cookies = request.cookies.map { HARCookie(from: $0) }
        self.headers = request.headers.map { HARHeader(name: $0.key, value: $0.value) }
        self.queryString = request.queryItems.map { HARQueryParam(name: $0.name, value: $0.value ?? "") }

        if let body = request.body, !body.isEmpty {
            self.postData = HARPostData(
                mimeType: request.contentType?.mimeType ?? "application/octet-stream",
                text: String(data: body, encoding: .utf8) ?? ""
            )
        } else {
            self.postData = nil
        }

        self.headersSize = -1 // Unknown
        self.bodySize = Int(request.bodySize)
    }
}

private struct HARResponse: Codable {
    let status: Int
    let statusText: String
    let httpVersion: String
    let cookies: [HARCookie]
    let headers: [HARHeader]
    let content: HARContent
    let redirectURL: String
    let headersSize: Int
    let bodySize: Int

    init(from response: ResponseData?) {
        guard let response = response else {
            self.status = 0
            self.statusText = "No Response"
            self.httpVersion = "HTTP/1.1"
            self.cookies = []
            self.headers = []
            self.content = HARContent(size: 0, mimeType: "", text: nil)
            self.redirectURL = ""
            self.headersSize = -1
            self.bodySize = -1
            return
        }

        self.status = response.statusCode
        self.statusText = response.statusMessage
        self.httpVersion = "HTTP/1.1"
        self.cookies = response.cookies.map { HARCookie(from: $0) }
        self.headers = response.headers.map { HARHeader(name: $0.key, value: $0.value) }

        self.content = HARContent(
            size: Int(response.bodySize),
            mimeType: response.mimeType ?? "application/octet-stream",
            text: response.bodyString
        )

        self.redirectURL = response.finalURL?.absoluteString ?? ""
        self.headersSize = -1
        self.bodySize = Int(response.bodySize)
    }
}

private struct HARCookie: Codable {
    let name: String
    let value: String
    let path: String?
    let domain: String?
    let expires: String?
    let httpOnly: Bool
    let secure: Bool

    init(from cookie: HTTPCookieData) {
        self.name = cookie.name
        self.value = cookie.value
        self.path = cookie.path
        self.domain = cookie.domain

        if let expires = cookie.expiresDate {
            let formatter = ISO8601DateFormatter()
            self.expires = formatter.string(from: expires)
        } else {
            self.expires = nil
        }

        self.httpOnly = cookie.isHTTPOnly
        self.secure = cookie.isSecure
    }
}

private struct HARHeader: Codable {
    let name: String
    let value: String
}

private struct HARQueryParam: Codable {
    let name: String
    let value: String
}

private struct HARPostData: Codable {
    let mimeType: String
    let text: String
}

private struct HARContent: Codable {
    let size: Int
    let mimeType: String
    let text: String?
}

private struct HARCache: Codable {
    // Empty for now
}

private struct HARTimings: Codable {
    let blocked: Double
    let dns: Double
    let connect: Double
    let ssl: Double
    let send: Double
    let wait: Double
    let receive: Double

    init(from timings: RequestTimings?) {
        guard let timings = timings else {
            self.blocked = -1
            self.dns = -1
            self.connect = -1
            self.ssl = -1
            self.send = -1
            self.wait = -1
            self.receive = -1
            return
        }

        self.blocked = 0
        self.dns = timings.dnsLookup * 1000
        self.connect = timings.tcpConnect * 1000
        self.ssl = (timings.tlsHandshake ?? 0) * 1000
        self.send = timings.requestSend * 1000
        self.wait = timings.serverWait * 1000
        self.receive = timings.responseReceive * 1000
    }
}
