import SwiftUI
import NetCheckerTrafficCore

/// SSL health dashboard view
public struct NetCheckerTrafficUI_SSLDashboardView: View {
    @ObservedObject private var store = TrafficStore.shared

    public init() {}

    private var sslRecords: [TrafficRecord] {
        store.records.filter { $0.url.scheme == "https" }
    }

    private var recordsWithSecurity: [TrafficRecord] {
        sslRecords.filter { $0.security != nil }
    }

    private var secureRecords: [TrafficRecord] {
        recordsWithSecurity.filter { $0.security?.isSecure == true }
    }

    private var insecureRecords: [TrafficRecord] {
        recordsWithSecurity.filter { $0.security?.isSecure == false }
    }

    private var uniqueHosts: Set<String> {
        Set(sslRecords.map { $0.host })
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overview cards
                overviewSection

                // TLS versions
                tlsVersionsSection

                // Hosts security status
                hostsSecuritySection

                // Recent certificates
                recentCertificatesSection
            }
            .padding()
        }
        .navigationTitle("SSL Dashboard")
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SSLStatCard(
                    title: "HTTPS Requests",
                    value: "\(sslRecords.count)",
                    icon: "lock.fill",
                    color: .blue
                )

                SSLStatCard(
                    title: "Secure",
                    value: "\(secureRecords.count)",
                    icon: "checkmark.shield.fill",
                    color: .green
                )
            }

            HStack(spacing: 12) {
                SSLStatCard(
                    title: "Hosts",
                    value: "\(uniqueHosts.count)",
                    icon: "server.rack",
                    color: .purple
                )

                SSLStatCard(
                    title: "Issues",
                    value: "\(insecureRecords.count)",
                    icon: "exclamationmark.triangle.fill",
                    color: insecureRecords.isEmpty ? .green : .orange
                )
            }
        }
    }

    // MARK: - TLS Versions Section

    private var tlsVersionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TLS Versions")
                .font(.headline)

            let tlsVersions = Dictionary(grouping: recordsWithSecurity) {
                $0.security?.tlsVersion ?? "Unknown"
            }

            if tlsVersions.isEmpty {
                Text("No TLS data available")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    let sortedVersions = tlsVersions.keys.sorted().reversed()
                    ForEach(Array(sortedVersions.enumerated()), id: \.element) { index, version in
                        let count = tlsVersions[version]?.count ?? 0
                        let total = max(recordsWithSecurity.count, 1)

                        HStack {
                            Circle()
                                .fill(tlsVersionColor(version))
                                .frame(width: 12, height: 12)

                            Text(version)
                                .font(.subheadline)

                            Spacer()

                            Text("\(count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(String(format: "%.0f%%", Double(count) / Double(total) * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding()

                        if index < sortedVersions.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            }
        }
    }

    private func tlsVersionColor(_ version: String) -> Color {
        if version.contains("1.3") {
            return .green
        } else if version.contains("1.2") {
            return .blue
        } else if version.contains("1.1") || version.contains("1.0") {
            return .orange
        }
        return .gray
    }

    // MARK: - Hosts Security Section

    private var hostsSecuritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hosts")
                .font(.headline)

            if uniqueHosts.isEmpty {
                Text("No HTTPS hosts yet")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    let sortedHosts = Array(uniqueHosts).sorted()
                    ForEach(Array(sortedHosts.enumerated()), id: \.element) { index, host in
                        let hostRecords = sslRecords.filter { $0.host == host }
                        let isSecure = hostRecords.allSatisfy { $0.security?.isSecure ?? true }
                        let latestTLS = hostRecords.compactMap { $0.security?.tlsVersion }.first

                        HStack {
                            Image(systemName: isSecure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .foregroundColor(isSecure ? .green : .orange)

                            Text(host)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            if let tls = latestTLS {
                                Text(tls)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(tlsVersionColor(tls).opacity(0.15))
                                    .foregroundColor(tlsVersionColor(tls))
                                    .cornerRadius(4)
                            }
                        }
                        .padding()

                        if index < sortedHosts.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Recent Certificates Section

    private var recentCertificatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Certificates")
                .font(.headline)

            let recentWithCerts = Array(recordsWithSecurity
                .filter { !($0.security?.certificateChain.isEmpty ?? true) }
                .prefix(5))

            if recentWithCerts.isEmpty {
                Text("No certificate information available")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentWithCerts.enumerated()), id: \.element.id) { index, record in
                        if let cert = record.security?.certificateChain.first {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cert.subject)
                                        .font(.subheadline)
                                        .lineLimit(1)

                                    Text(record.host)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if let validUntil = cert.validUntil {
                                    ValidityBadge(validTo: validUntil)
                                }
                            }
                            .padding()

                            if index < recentWithCerts.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            }
        }
    }
}

// MARK: - SSL Stat Card

struct SSLStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
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

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_SSLDashboardView()
    }
}
