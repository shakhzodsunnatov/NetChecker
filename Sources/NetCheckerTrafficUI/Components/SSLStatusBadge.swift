import SwiftUI
import NetCheckerTrafficCore

/// Badge showing SSL/TLS status
public struct NetCheckerTrafficUI_SSLStatusBadge: View {
    let securityInfo: SecurityInfo?

    public init(securityInfo: SecurityInfo?) {
        self.securityInfo = securityInfo
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }

    private var iconName: String {
        guard let info = securityInfo else {
            return "lock.slash"
        }

        if info.isSecure {
            return "lock.fill"
        } else {
            return "lock.trianglebadge.exclamationmark"
        }
    }

    private var statusText: String {
        guard let info = securityInfo else {
            return "No TLS"
        }

        if info.isSecure {
            return info.tlsVersion ?? "TLS"
        } else {
            return "Warning"
        }
    }

    private var statusColor: Color {
        guard let info = securityInfo else {
            return TrafficTheme.sslErrorColor
        }

        if info.isSecure {
            return TrafficTheme.sslSecureColor
        } else {
            return TrafficTheme.sslWarningColor
        }
    }
}

/// Detailed SSL status view
public struct SSLStatusDetailView: View {
    let securityInfo: SecurityInfo

    public init(securityInfo: SecurityInfo) {
        self.securityInfo = securityInfo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            HStack {
                Image(systemName: securityInfo.isSecure ? "lock.shield.fill" : "lock.trianglebadge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundColor(securityInfo.isSecure ? .green : .orange)

                VStack(alignment: .leading) {
                    Text(securityInfo.isSecure ? "Secure Connection" : "Connection Warning")
                        .font(.headline)

                    if let tlsVersion = securityInfo.tlsVersion {
                        Text(tlsVersion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)

            // TLS Details
            if securityInfo.tlsVersion != nil || securityInfo.cipherSuite != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Details")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let tlsVersion = securityInfo.tlsVersion {
                        DetailRow(label: "TLS Version", value: tlsVersion)
                    }

                    if let cipher = securityInfo.cipherSuite {
                        DetailRow(label: "Cipher Suite", value: cipher)
                    }

                    if let alpn = securityInfo.alpnProtocol {
                        DetailRow(label: "Protocol", value: alpn)
                    }

                    if securityInfo.sessionReused {
                        DetailRow(label: "Session", value: "Reused")
                    }
                }
            }

            // Certificate chain
            if !securityInfo.certificateChain.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Certificate Chain")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(securityInfo.certificateChain.indices, id: \.self) { index in
                        NetCheckerTrafficUI_CertificateRow(
                            certificate: securityInfo.certificateChain[index],
                            index: index
                        )
                    }
                }
            }

            // Pinning status
            if securityInfo.isPinned {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundColor(.green)
                    Text("Certificate Pinning Active")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NetCheckerTrafficUI_SSLStatusBadge(securityInfo: nil)

        NetCheckerTrafficUI_SSLStatusBadge(
            securityInfo: SecurityInfo(
                tlsVersion: "TLS 1.3",
                cipherSuite: "TLS_AES_256_GCM_SHA384"
            )
        )

        NetCheckerTrafficUI_SSLStatusBadge(
            securityInfo: SecurityInfo(
                tlsVersion: "TLS 1.0"
            )
        )
    }
    .padding()
}
