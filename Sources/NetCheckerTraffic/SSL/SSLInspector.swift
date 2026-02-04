import Foundation
import Security
import Network

/// Инспектор SSL сертификатов
public final class SSLInspector {
    // MARK: - Singleton

    public static let shared = SSLInspector()

    // MARK: - Public Methods

    /// Проверить SSL сертификат хоста
    public func check(host: String, port: UInt16 = 443) async -> SSLCheckResult {
        await withCheckedContinuation { continuation in
            checkHost(host: host, port: port) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Извлечь информацию о сертификате из SecTrust
    public func extractCertificateInfo(from trust: SecTrust) -> [CertificateInfo] {
        var certificates: [CertificateInfo] = []

        let count = SecTrustGetCertificateCount(trust)

        for index in 0..<count {
            if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
                if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                   index < chain.count {
                    let cert = chain[Int(index)]
                    if let info = parseCertificate(cert) {
                        certificates.append(info)
                    }
                }
            } else {
                // Fallback for older versions
                if let cert = SecTrustGetCertificateAtIndex(trust, index) {
                    if let info = parseCertificate(cert) {
                        certificates.append(info)
                    }
                }
            }
        }

        return certificates
    }

    /// Извлечь TLS версию
    public func extractTLSVersion(_ version: tls_protocol_version_t) -> String {
        switch version {
        case .TLSv10: return "TLS 1.0"
        case .TLSv11: return "TLS 1.1"
        case .TLSv12: return "TLS 1.2"
        case .TLSv13: return "TLS 1.3"
        case .DTLSv10: return "DTLS 1.0"
        case .DTLSv12: return "DTLS 1.2"
        default: return "Unknown"
        }
    }

    /// Описание cipher suite
    public func cipherSuiteDescription(_ suite: tls_ciphersuite_t) -> String {
        switch suite {
        case .RSA_WITH_AES_128_GCM_SHA256: return "RSA_WITH_AES_128_GCM_SHA256"
        case .RSA_WITH_AES_256_GCM_SHA384: return "RSA_WITH_AES_256_GCM_SHA384"
        case .ECDHE_RSA_WITH_AES_128_GCM_SHA256: return "ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        case .ECDHE_RSA_WITH_AES_256_GCM_SHA384: return "ECDHE_RSA_WITH_AES_256_GCM_SHA384"
        case .ECDHE_ECDSA_WITH_AES_128_GCM_SHA256: return "ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
        case .ECDHE_ECDSA_WITH_AES_256_GCM_SHA384: return "ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
        case .AES_128_GCM_SHA256: return "TLS_AES_128_GCM_SHA256"
        case .AES_256_GCM_SHA384: return "TLS_AES_256_GCM_SHA384"
        case .CHACHA20_POLY1305_SHA256: return "TLS_CHACHA20_POLY1305_SHA256"
        default: return "Unknown (\(suite.rawValue))"
        }
    }

    // MARK: - Private Methods

    private func checkHost(
        host: String,
        port: UInt16,
        completion: @escaping (SSLCheckResult) -> Void
    ) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )

        let parameters = NWParameters.tls
        let connection = NWConnection(to: endpoint, using: parameters)

        var result = SSLCheckResult(host: host, port: Int(port))

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Extract TLS info
                if let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
                    let secProtocol = metadata.securityProtocolMetadata
                    result.isValid = true

                    // Get TLS version
                    let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(secProtocol)
                    result.tlsVersion = self.extractTLSVersion(version)

                    // Get cipher suite (use singular function)
                    let ciphersuite = sec_protocol_metadata_get_negotiated_tls_ciphersuite(secProtocol)
                    result.cipherSuite = self.cipherSuiteDescription(ciphersuite)
                }

                connection.cancel()
                completion(result)

            case .failed(let error):
                result.isValid = false
                result.error = error.localizedDescription
                connection.cancel()
                completion(result)

            case .cancelled:
                break

            default:
                break
            }
        }

        connection.start(queue: .global())

        // Timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if connection.state != .ready && connection.state != .failed(.posix(.ECANCELED)) {
                result.isValid = false
                result.error = "Connection timeout"
                connection.cancel()
                completion(result)
            }
        }
    }

    private func parseCertificate(_ certificate: SecCertificate) -> CertificateInfo? {
        // Get subject summary
        let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"

        // Get certificate data for detailed parsing
        let certData = SecCertificateCopyData(certificate) as Data

        // Basic parsing - in production you'd want more detailed X.509 parsing
        var info = CertificateInfo(
            subject: subject,
            issuer: "Unknown", // Would need ASN.1 parsing
            serialNumber: UUID().uuidString
        )

        // Note: Detailed certificate parsing requires platform-specific APIs
        // SecCertificateCopyValues is macOS-only
        // For iOS, would need to parse DER/ASN.1 directly or use OpenSSL

        return info
    }
}

// MARK: - SSL Check Result

public struct SSLCheckResult: Sendable {
    public var host: String
    public var port: Int
    public var isValid: Bool = false
    public var tlsVersion: String?
    public var cipherSuite: String?
    public var certificates: [CertificateInfo] = []
    public var error: String?

    /// Дней до истечения сертификата
    public var expiresIn: Int? {
        certificates.first?.daysUntilExpiry
    }

    /// Является ли соединение безопасным
    public var isSecure: Bool {
        guard isValid else { return false }
        guard let tls = tlsVersion else { return false }
        return tls.contains("1.2") || tls.contains("1.3")
    }
}
