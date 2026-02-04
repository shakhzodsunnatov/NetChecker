import SwiftUI
import NetCheckerTrafficCore

/// Row displaying certificate information
public struct NetCheckerTrafficUI_CertificateRow: View {
    let certificate: CertificateInfo
    let index: Int

    @State private var isExpanded = false

    public init(certificate: CertificateInfo, index: Int = 0) {
        self.certificate = certificate
        self.index = index
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    // Level indicator
                    ForEach(0..<index, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2)
                            .padding(.leading, 8)
                    }

                    Image(systemName: certificateIcon)
                        .foregroundColor(certificateColor)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(certificate.subject)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(certificate.issuer)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let validUntil = certificate.validUntil {
                        ValidityBadge(validTo: validUntil)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                CertificateDetailView(certificate: certificate)
                    .padding(.leading, CGFloat(index) * 16 + 40)
                    .padding(.bottom, 8)
            }

            Divider()
        }
    }

    private var certificateIcon: String {
        if index == 0 {
            return "lock.shield.fill"
        } else if certificate.isCA {
            return "building.columns.fill"
        } else {
            return "doc.text.fill"
        }
    }

    private var certificateColor: Color {
        if certificate.isExpired {
            return .red
        } else if certificate.isExpiringSoon {
            return .orange
        }
        return .green
    }
}

// MARK: - Validity Badge

struct ValidityBadge: View {
    let validTo: Date

    var body: some View {
        let isExpired = validTo < Date()
        let isExpiringSoon = validTo < Date().addingTimeInterval(30 * 24 * 3600)

        HStack(spacing: 4) {
            if isExpired {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("Expired")
            } else if isExpiringSoon {
                Image(systemName: "clock.fill")
                    .font(.caption2)
                Text("Expires Soon")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                Text("Valid")
            }
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15))
        .foregroundColor(badgeColor)
        .cornerRadius(4)
    }

    private var badgeColor: Color {
        let isExpired = validTo < Date()
        let isExpiringSoon = validTo < Date().addingTimeInterval(30 * 24 * 3600)

        if isExpired {
            return .red
        } else if isExpiringSoon {
            return .orange
        }
        return .green
    }
}

// MARK: - Certificate Detail View

struct CertificateDetailView: View {
    let certificate: CertificateInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CertDetailRow(label: "Subject", value: certificate.subject)
            CertDetailRow(label: "Issuer", value: certificate.issuer)
            CertDetailRow(label: "Serial Number", value: certificate.serialNumber)

            if let validFrom = certificate.validFrom {
                CertDetailRow(label: "Valid From", value: formatDate(validFrom))
            }

            if let validUntil = certificate.validUntil {
                CertDetailRow(label: "Valid To", value: formatDate(validUntil))
            }

            if let algorithm = certificate.signatureAlgorithm {
                CertDetailRow(label: "Signature Algorithm", value: algorithm)
            }

            if let keyAlgorithm = certificate.publicKeyAlgorithm {
                CertDetailRow(label: "Public Key Algorithm", value: keyAlgorithm)
            }

            if let keyBits = certificate.publicKeyBits {
                CertDetailRow(label: "Key Size", value: "\(keyBits) bits")
            }

            if !certificate.subjectAlternativeNames.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subject Alternative Names")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(certificate.subjectAlternativeNames, id: \.self) { san in
                        Text(san)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
            }

            if let fingerprint = certificate.sha256Fingerprint {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHA-256 Fingerprint")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(fingerprint)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(2)
                }

                NetCheckerTrafficUI_CopyButton(text: fingerprint, label: "Copy Fingerprint")
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct CertDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            NetCheckerTrafficUI_CertificateRow(
                certificate: CertificateInfo(
                    subject: "*.example.com",
                    issuer: "DigiCert SHA2 Extended Validation Server CA",
                    validFrom: Date().addingTimeInterval(-365 * 24 * 3600),
                    validUntil: Date().addingTimeInterval(365 * 24 * 3600)
                ),
                index: 0
            )

            NetCheckerTrafficUI_CertificateRow(
                certificate: CertificateInfo(
                    subject: "DigiCert SHA2 Extended Validation Server CA",
                    issuer: "DigiCert Inc",
                    validFrom: Date().addingTimeInterval(-5 * 365 * 24 * 3600),
                    validUntil: Date().addingTimeInterval(5 * 365 * 24 * 3600),
                    isCA: true
                ),
                index: 1
            )
        }
        .padding()
    }
}
