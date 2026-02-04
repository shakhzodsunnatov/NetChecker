import Foundation
import Security

/// Валидатор SSL Pinning
public final class SSLPinningValidator {
    // MARK: - Singleton

    public static let shared = SSLPinningValidator()

    // MARK: - Properties

    /// Настроенные пины по хостам
    private var pins: [String: Set<String>] = [:]
    private let lock = NSLock()

    // MARK: - Public Methods

    /// Добавить pin для хоста
    public func addPin(host: String, spkiHash: String) {
        lock.lock()
        defer { lock.unlock() }

        var hostPins = pins[host.lowercased()] ?? []
        hostPins.insert(spkiHash)
        pins[host.lowercased()] = hostPins
    }

    /// Удалить пины для хоста
    public func removePins(for host: String) {
        lock.lock()
        defer { lock.unlock() }
        pins.removeValue(forKey: host.lowercased())
    }

    /// Проверить pin сертификата
    public func validate(trust: SecTrust, host: String) -> PinValidationResult {
        lock.lock()
        let hostPins = pins[host.lowercased()]
        lock.unlock()

        guard let expectedPins = hostPins, !expectedPins.isEmpty else {
            return PinValidationResult(
                host: host,
                isValid: true,
                isPinned: false,
                reason: "No pins configured for this host"
            )
        }

        // Extract SPKI hashes from certificate chain
        let certChain = extractCertificateChain(from: trust)
        let certHashes = certChain.map { calculateSPKIHash($0) }

        // Check if any certificate matches any pin
        for hash in certHashes {
            if expectedPins.contains(hash) {
                return PinValidationResult(
                    host: host,
                    isValid: true,
                    isPinned: true,
                    matchedPin: hash
                )
            }
        }

        return PinValidationResult(
            host: host,
            isValid: false,
            isPinned: true,
            reason: "Certificate does not match any pinned key",
            serverHashes: certHashes,
            expectedHashes: Array(expectedPins)
        )
    }

    /// Вычислить SPKI hash для сертификата
    public func calculateSPKIHash(_ certificate: SecCertificate) -> String {
        // Get certificate data
        let certData = SecCertificateCopyData(certificate) as Data

        // Extract public key
        var publicKey: SecKey?

        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            publicKey = SecCertificateCopyKey(certificate)
        } else {
            // Fallback for older versions
            let policy = SecPolicyCreateBasicX509()
            var trust: SecTrust?
            SecTrustCreateWithCertificates(certificate, policy, &trust)
            if let trust = trust {
                publicKey = SecTrustCopyPublicKey(trust)
            }
        }

        guard let key = publicKey,
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return ""
        }

        // Calculate SHA-256 hash of SPKI
        return CertificateParser.sha256Fingerprint(of: keyData)
    }

    // MARK: - Private Methods

    private func extractCertificateChain(from trust: SecTrust) -> [SecCertificate] {
        var certificates: [SecCertificate] = []

        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            if let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                certificates = chain
            }
        } else {
            let count = SecTrustGetCertificateCount(trust)
            for index in 0..<count {
                if let cert = SecTrustGetCertificateAtIndex(trust, index) {
                    certificates.append(cert)
                }
            }
        }

        return certificates
    }
}

// MARK: - Pin Validation Result

public struct PinValidationResult: Sendable {
    public let host: String
    public let isValid: Bool
    public let isPinned: Bool
    public var matchedPin: String?
    public var reason: String?
    public var serverHashes: [String]?
    public var expectedHashes: [String]?

    public init(
        host: String,
        isValid: Bool,
        isPinned: Bool,
        matchedPin: String? = nil,
        reason: String? = nil,
        serverHashes: [String]? = nil,
        expectedHashes: [String]? = nil
    ) {
        self.host = host
        self.isValid = isValid
        self.isPinned = isPinned
        self.matchedPin = matchedPin
        self.reason = reason
        self.serverHashes = serverHashes
        self.expectedHashes = expectedHashes
    }
}
