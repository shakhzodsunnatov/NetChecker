import Foundation
import Security

/// Парсер X.509 сертификатов
public struct CertificateParser {
    /// Парсить SecCertificate в CertificateInfo
    public static func parse(_ certificate: SecCertificate) -> CertificateInfo {
        let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown"
        let certData = SecCertificateCopyData(certificate) as Data

        var info = CertificateInfo(
            subject: subject,
            issuer: "Unknown",
            serialNumber: generateSerialNumber(from: certData)
        )

        // Try to extract more details (macOS only - SecCertificateCopyValues not available on iOS)
        #if os(macOS)
        if let values = SecCertificateCopyValues(certificate, nil, nil) as? [String: Any] {
            // Parse validity dates
            if let notBefore = values["2.5.29.24"] as? [String: Any],
               let date = notBefore["value"] as? Date {
                info.validFrom = date
            }

            if let notAfter = values["2.5.29.25"] as? [String: Any],
               let date = notAfter["value"] as? Date {
                info.validUntil = date
            }
        }
        #endif

        // Calculate SHA-256 fingerprint
        info.sha256Fingerprint = sha256Fingerprint(of: certData)

        // Check if self-signed
        info.isSelfSigned = subject == info.issuer

        return info
    }

    /// Парсить Data (DER encoded) в CertificateInfo
    public static func parse(derData: Data) -> CertificateInfo? {
        guard let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            return nil
        }
        return parse(certificate)
    }

    /// Парсить PEM строку в CertificateInfo
    public static func parse(pemString: String) -> CertificateInfo? {
        guard let derData = pemToDer(pemString) else {
            return nil
        }
        return parse(derData: derData)
    }

    /// Конвертировать PEM в DER
    public static func pemToDer(_ pem: String) -> Data? {
        let lines = pem.components(separatedBy: "\n")
        let base64Lines = lines.filter { line in
            !line.hasPrefix("-----") && !line.isEmpty
        }
        let base64String = base64Lines.joined()
        return Data(base64Encoded: base64String)
    }

    /// Вычислить SHA-256 fingerprint
    public static func sha256Fingerprint(of data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }

        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Генерировать serial number из данных
    private static func generateSerialNumber(from data: Data) -> String {
        let hash = sha256Fingerprint(of: data)
        return String(hash.prefix(20))
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
