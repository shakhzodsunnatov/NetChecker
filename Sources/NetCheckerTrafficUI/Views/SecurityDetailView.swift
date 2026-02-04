import SwiftUI
import NetCheckerTrafficCore

/// Detail view for security/SSL information
public struct NetCheckerTrafficUI_SecurityDetailView: View {
    let record: TrafficRecord

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let securityInfo = record.security {
                    // Security Overview
                    securityOverview(securityInfo)

                    // TLS Details
                    tlsDetailsSection(securityInfo)

                    // Certificate Chain
                    if !securityInfo.certificateChain.isEmpty {
                        certificateChainSection(securityInfo)
                    }

                    // Pinning Status
                    pinningSection(securityInfo)
                } else {
                    noSecurityInfo
                }
            }
            .padding()
        }
    }

    // MARK: - Security Overview

    private func securityOverview(_ info: SecurityInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: info.isSecure ? "lock.shield.fill" : "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 40))
                    .foregroundColor(info.isSecure ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.isSecure ? "Secure Connection" : "Connection Warning")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(securitySummary(info))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(info.isSecure ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            )
        }
    }

    private func securitySummary(_ info: SecurityInfo) -> String {
        var parts: [String] = []

        if let tls = info.tlsVersion {
            parts.append(tls)
        }

        if info.isPinned {
            parts.append("Pinned")
        }

        if info.isSecure {
            parts.append("Valid Certificate")
        } else {
            parts.append("Certificate Issue")
        }

        return parts.joined(separator: " • ")
    }

    // MARK: - TLS Details

    private func tlsDetailsSection(_ info: SecurityInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TLS Details")
                .font(.headline)

            VStack(spacing: 0) {
                if let tlsVersion = info.tlsVersion {
                    SecurityDetailRow(
                        icon: "lock.fill",
                        label: "TLS Version",
                        value: tlsVersion,
                        color: tlsVersionColor(tlsVersion)
                    )
                    Divider()
                }

                if let cipher = info.cipherSuite {
                    SecurityDetailRow(
                        icon: "key.fill",
                        label: "Cipher Suite",
                        value: formatCipher(cipher),
                        color: .blue
                    )
                    Divider()
                }

                if let alpn = info.alpnProtocol {
                    SecurityDetailRow(
                        icon: "arrow.left.arrow.right",
                        label: "Protocol",
                        value: alpn,
                        color: .purple
                    )
                    Divider()
                }

                SecurityDetailRow(
                    icon: "shield.fill",
                    label: "Connection",
                    value: info.isSecure ? "Encrypted" : "Not Secure",
                    color: info.isSecure ? .green : .red
                )

                if info.sessionReused {
                    Divider()
                    SecurityDetailRow(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Session",
                        value: "Reused",
                        color: .green
                    )
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    private func tlsVersionColor(_ version: String) -> Color {
        if version.contains("1.3") {
            return .green
        } else if version.contains("1.2") {
            return .blue
        } else {
            return .orange
        }
    }

    private func formatCipher(_ cipher: String) -> String {
        // Simplify long cipher names
        if cipher.count > 30 {
            return String(cipher.prefix(27)) + "..."
        }
        return cipher
    }

    // MARK: - Certificate Chain

    private func certificateChainSection(_ info: SecurityInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Certificate Chain")
                    .font(.headline)

                Spacer()

                Text("\(info.certificateChain.count) certificate(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(info.certificateChain.indices, id: \.self) { index in
                    NetCheckerTrafficUI_CertificateRow(
                        certificate: info.certificateChain[index],
                        index: index
                    )
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    // MARK: - Pinning Status

    private func pinningSection(_ info: SecurityInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Certificate Pinning")
                .font(.headline)

            HStack {
                Image(systemName: info.isPinned ? "pin.fill" : "pin.slash")
                    .font(.title2)
                    .foregroundColor(info.isPinned ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.isPinned ? "Pinning Active" : "No Pinning")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(info.isPinned
                         ? "Certificate is pinned and validated"
                         : "Standard certificate validation only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    // MARK: - No Security Info

    private var noSecurityInfo: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Security Information")
                .font(.headline)

            Text("This connection does not use HTTPS or security information is not available")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Security Detail Row

struct SecurityDetailRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
        }
        .padding()
    }
}

#Preview {
    NetCheckerTrafficUI_SecurityDetailView(
        record: TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com/secure")!,
                method: .get
            ),
            security: SecurityInfo(
                tlsVersion: "TLS 1.3",
                cipherSuite: "TLS_AES_256_GCM_SHA384",
                certificateChain: [
                    CertificateInfo(
                        subject: "*.example.com",
                        issuer: "DigiCert SHA2 Extended Validation Server CA",
                        validFrom: Date().addingTimeInterval(-365 * 24 * 3600),
                        validUntil: Date().addingTimeInterval(365 * 24 * 3600)
                    ),
                    CertificateInfo(
                        subject: "DigiCert SHA2 Extended Validation Server CA",
                        issuer: "DigiCert Inc",
                        isCA: true
                    )
                ],
                isPinned: true
            )
        )
    )
}
