import Foundation
import Security

/// Информация о безопасности соединения
public struct SecurityInfo: Codable, Sendable, Hashable {
    /// Версия TLS
    public var tlsVersion: String?

    /// Набор шифров
    public var cipherSuite: String?

    /// ALPN протокол (h2, http/1.1)
    public var alpnProtocol: String?

    /// Цепочка сертификатов
    public var certificateChain: [CertificateInfo]

    /// Проверка пиннинга прошла
    public var isPinned: Bool

    /// Сессия была переиспользована
    public var sessionReused: Bool

    /// OCSP stapling включен
    public var ocspStapling: Bool?

    /// Certificate Transparency включен
    public var certificateTransparency: Bool?

    // MARK: - Initialization

    public init(
        tlsVersion: String? = nil,
        cipherSuite: String? = nil,
        alpnProtocol: String? = nil,
        certificateChain: [CertificateInfo] = [],
        isPinned: Bool = false,
        sessionReused: Bool = false,
        ocspStapling: Bool? = nil,
        certificateTransparency: Bool? = nil
    ) {
        self.tlsVersion = tlsVersion
        self.cipherSuite = cipherSuite
        self.alpnProtocol = alpnProtocol
        self.certificateChain = certificateChain
        self.isPinned = isPinned
        self.sessionReused = sessionReused
        self.ocspStapling = ocspStapling
        self.certificateTransparency = certificateTransparency
    }

    // MARK: - Computed Properties

    /// Leaf (server) certificate
    public var serverCertificate: CertificateInfo? {
        certificateChain.first
    }

    /// Root certificate
    public var rootCertificate: CertificateInfo? {
        certificateChain.last
    }

    /// Является ли соединение безопасным
    public var isSecure: Bool {
        guard let tls = tlsVersion else { return false }
        // TLS 1.2+ considered secure
        return tls.contains("1.2") || tls.contains("1.3")
    }

    /// Уровень безопасности
    public var securityLevel: SecurityLevel {
        if tlsVersion?.contains("1.3") == true {
            return .excellent
        } else if tlsVersion?.contains("1.2") == true {
            return .good
        } else if tlsVersion?.contains("1.1") == true || tlsVersion?.contains("1.0") == true {
            return .weak
        } else if tlsVersion != nil {
            return .fair
        }
        return .none
    }

    /// Дней до истечения сертификата
    public var daysUntilExpiry: Int? {
        guard let cert = serverCertificate, let validUntil = cert.validUntil else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: validUntil).day
        return days
    }

    /// Сертификат скоро истечет (< 30 дней)
    public var isExpiringSoon: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days < 30 && days >= 0
    }

    /// Сертификат истек
    public var isExpired: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days < 0
    }
}

// MARK: - Certificate Info

public struct CertificateInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String { serialNumber }

    /// Common Name (CN)
    public var subject: String

    /// Issuer
    public var issuer: String

    /// Serial number
    public var serialNumber: String

    /// Valid from date
    public var validFrom: Date?

    /// Valid until date
    public var validUntil: Date?

    /// Public key bits
    public var publicKeyBits: Int?

    /// Public key algorithm
    public var publicKeyAlgorithm: String?

    /// Signature algorithm
    public var signatureAlgorithm: String?

    /// Subject Alternative Names
    public var subjectAlternativeNames: [String]

    /// SHA-256 fingerprint
    public var sha256Fingerprint: String?

    /// Is self-signed
    public var isSelfSigned: Bool

    /// Is CA certificate
    public var isCA: Bool

    // MARK: - Initialization

    public init(
        subject: String,
        issuer: String,
        serialNumber: String = UUID().uuidString,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        publicKeyBits: Int? = nil,
        publicKeyAlgorithm: String? = nil,
        signatureAlgorithm: String? = nil,
        subjectAlternativeNames: [String] = [],
        sha256Fingerprint: String? = nil,
        isSelfSigned: Bool = false,
        isCA: Bool = false
    ) {
        self.subject = subject
        self.issuer = issuer
        self.serialNumber = serialNumber
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.publicKeyBits = publicKeyBits
        self.publicKeyAlgorithm = publicKeyAlgorithm
        self.signatureAlgorithm = signatureAlgorithm
        self.subjectAlternativeNames = subjectAlternativeNames
        self.sha256Fingerprint = sha256Fingerprint
        self.isSelfSigned = isSelfSigned
        self.isCA = isCA
    }

    // MARK: - Computed Properties

    /// Дней до истечения
    public var daysUntilExpiry: Int? {
        guard let validUntil = validUntil else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: validUntil).day
    }

    /// Истек ли сертификат
    public var isExpired: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days < 0
    }

    /// Скоро истекает (< 30 дней)
    public var isExpiringSoon: Bool {
        guard let days = daysUntilExpiry else { return false }
        return days < 30 && days >= 0
    }

    /// Отформатированный срок действия
    public var validityPeriod: String? {
        guard let from = validFrom, let until = validUntil else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: from)) → \(formatter.string(from: until))"
    }
}

// MARK: - Security Level

public enum SecurityLevel: String, Codable, Sendable, Comparable {
    case none
    case weak
    case fair
    case good
    case excellent

    public static func < (lhs: SecurityLevel, rhs: SecurityLevel) -> Bool {
        let order: [SecurityLevel] = [.none, .weak, .fair, .good, .excellent]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else { return false }
        return lhsIndex < rhsIndex
    }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }

    public var colorName: String {
        switch self {
        case .none: return "gray"
        case .weak: return "red"
        case .fair: return "orange"
        case .good: return "green"
        case .excellent: return "blue"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "lock.open"
        case .weak: return "lock.trianglebadge.exclamationmark"
        case .fair: return "lock"
        case .good: return "lock.fill"
        case .excellent: return "lock.shield.fill"
        }
    }
}
