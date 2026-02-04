import Foundation

/// Ошибки сетевого трафика
public struct TrafficError: Codable, Sendable, Hashable {
    /// Код ошибки (NSURLErrorDomain code)
    public let code: Int

    /// Домен ошибки
    public let domain: String

    /// Локализованное описание
    public let localizedDescription: String

    /// Категория ошибки
    public let category: ErrorCategory

    /// Временная метка
    public let timestamp: Date

    // MARK: - Initialization

    public init(
        code: Int,
        domain: String,
        localizedDescription: String,
        category: ErrorCategory? = nil,
        timestamp: Date = Date()
    ) {
        self.code = code
        self.domain = domain
        self.localizedDescription = localizedDescription
        self.category = category ?? ErrorCategory(code: code, domain: domain)
        self.timestamp = timestamp
    }

    /// Создать из Error
    public init(from error: Error) {
        let nsError = error as NSError
        self.code = nsError.code
        self.domain = nsError.domain
        self.localizedDescription = error.localizedDescription
        self.category = ErrorCategory(code: nsError.code, domain: nsError.domain)
        self.timestamp = Date()
    }
}

// MARK: - Error Category

public enum ErrorCategory: String, Codable, Sendable, CaseIterable {
    case timeout
    case noConnection
    case dnsFailure
    case sslError
    case cancelled
    case serverUnreachable
    case badRequest
    case authenticationRequired
    case forbidden
    case notFound
    case serverError
    case other

    // MARK: - Initialization

    public init(code: Int, domain: String) {
        guard domain == NSURLErrorDomain else {
            self = .other
            return
        }

        switch code {
        case NSURLErrorTimedOut:
            self = .timeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            self = .noConnection
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            self = .dnsFailure
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            self = .sslError
        case NSURLErrorCancelled:
            self = .cancelled
        case NSURLErrorCannotConnectToHost:
            self = .serverUnreachable
        default:
            self = .other
        }
    }

    /// Создать из HTTP статус-кода
    public init(statusCode: Int) {
        switch statusCode {
        case 400: self = .badRequest
        case 401, 407: self = .authenticationRequired
        case 403: self = .forbidden
        case 404: self = .notFound
        case 500..<600: self = .serverError
        default: self = .other
        }
    }

    // MARK: - Properties

    /// Название категории
    public var displayName: String {
        switch self {
        case .timeout: return "Timeout"
        case .noConnection: return "No Connection"
        case .dnsFailure: return "DNS Failure"
        case .sslError: return "SSL/TLS Error"
        case .cancelled: return "Cancelled"
        case .serverUnreachable: return "Server Unreachable"
        case .badRequest: return "Bad Request"
        case .authenticationRequired: return "Authentication Required"
        case .forbidden: return "Forbidden"
        case .notFound: return "Not Found"
        case .serverError: return "Server Error"
        case .other: return "Unknown Error"
        }
    }

    /// Описание категории
    public var description: String {
        switch self {
        case .timeout: return "The request timed out"
        case .noConnection: return "No internet connection"
        case .dnsFailure: return "Could not resolve hostname"
        case .sslError: return "SSL/TLS certificate error"
        case .cancelled: return "Request was cancelled"
        case .serverUnreachable: return "Could not connect to server"
        case .badRequest: return "Invalid request"
        case .authenticationRequired: return "Authentication required"
        case .forbidden: return "Access denied"
        case .notFound: return "Resource not found"
        case .serverError: return "Server error"
        case .other: return "An unknown error occurred"
        }
    }

    /// SF Symbol для категории
    public var systemImage: String {
        switch self {
        case .timeout: return "clock.badge.exclamationmark"
        case .noConnection: return "wifi.slash"
        case .dnsFailure: return "network.slash"
        case .sslError: return "lock.slash"
        case .cancelled: return "xmark.circle"
        case .serverUnreachable: return "server.rack"
        case .badRequest: return "exclamationmark.triangle"
        case .authenticationRequired: return "person.badge.key"
        case .forbidden: return "hand.raised"
        case .notFound: return "magnifyingglass"
        case .serverError: return "exclamationmark.octagon"
        case .other: return "questionmark.circle"
        }
    }

    /// Можно ли повторить запрос
    public var isRetryable: Bool {
        switch self {
        case .timeout, .noConnection, .serverUnreachable, .serverError:
            return true
        case .dnsFailure, .sslError, .cancelled, .badRequest, .authenticationRequired, .forbidden, .notFound, .other:
            return false
        }
    }
}
