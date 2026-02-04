import SwiftUI
import NetCheckerTrafficCore

/// Detail view for request timing information
public struct NetCheckerTrafficUI_TimingDetailView: View {
    let record: TrafficRecord

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Overview
                timingOverview

                // Visual timeline
                if let timings = record.timings {
                    timelineSection(timings)
                }

                // Detailed breakdown
                if let timings = record.timings {
                    detailedBreakdown(timings)
                }

                // Comparison section
                comparisonSection
            }
            .padding()
        }
    }

    // MARK: - Timing Overview

    private var timingOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            HStack(spacing: 20) {
                TimingOverviewItem(
                    title: "Total Time",
                    value: record.formattedDuration,
                    icon: "clock",
                    color: .blue
                )

                if record.state == .completed || record.state == .mocked {
                    TimingOverviewItem(
                        title: "Speed",
                        value: speedIndicator,
                        icon: speedIcon,
                        color: speedColor
                    )
                }

                if record.responseSize > 0 {
                    TimingOverviewItem(
                        title: "Throughput",
                        value: throughput,
                        icon: "arrow.down.circle",
                        color: .green
                    )
                }
            }
        }
    }

    private var speedIndicator: String {
        if record.duration < 0.1 {
            return "Very Fast"
        } else if record.duration < 0.5 {
            return "Fast"
        } else if record.duration < 1.0 {
            return "Normal"
        } else if record.duration < 3.0 {
            return "Slow"
        } else {
            return "Very Slow"
        }
    }

    private var speedIcon: String {
        if record.duration < 0.5 {
            return "hare"
        } else if record.duration < 2.0 {
            return "gauge.medium"
        } else {
            return "tortoise"
        }
    }

    private var speedColor: Color {
        if record.duration < 0.3 {
            return .green
        } else if record.duration < 1.0 {
            return .blue
        } else if record.duration < 2.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var throughput: String {
        guard record.duration > 0 else { return "N/A" }
        let bytesPerSecond = Double(record.responseSize) / record.duration
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    // MARK: - Timeline Section

    private func timelineSection(_ timings: RequestTimings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline")
                .font(.headline)

            NetCheckerTrafficUI_TimingBarView(timings: timings)
                .frame(height: 50)
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)

            // Legend
            HStack(spacing: 16) {
                TimingLegendItem(color: TrafficTheme.dnsColor, label: "DNS")
                TimingLegendItem(color: TrafficTheme.tcpColor, label: "TCP")
                TimingLegendItem(color: TrafficTheme.tlsColor, label: "TLS")
                TimingLegendItem(color: TrafficTheme.requestColor, label: "Request")
                TimingLegendItem(color: TrafficTheme.responseColor, label: "Waiting")
                TimingLegendItem(color: TrafficTheme.downloadColor, label: "Download")
            }
            .font(.caption2)
        }
    }

    // MARK: - Detailed Breakdown

    private func detailedBreakdown(_ timings: RequestTimings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Breakdown")
                .font(.headline)

            VStack(spacing: 0) {
                if timings.dnsLookup > 0 {
                    TimingDetailRow(
                        phase: "DNS Lookup",
                        description: "Domain name resolution",
                        duration: timings.dnsLookup,
                        percentage: timings.dnsLookup / timings.total * 100,
                        color: TrafficTheme.dnsColor
                    )
                    Divider()
                }

                if timings.tcpConnect > 0 {
                    TimingDetailRow(
                        phase: "TCP Connection",
                        description: "Establishing connection",
                        duration: timings.tcpConnect,
                        percentage: timings.tcpConnect / timings.total * 100,
                        color: TrafficTheme.tcpColor
                    )
                    Divider()
                }

                if let tlsHandshake = timings.tlsHandshake, tlsHandshake > 0 {
                    TimingDetailRow(
                        phase: "TLS Handshake",
                        description: "SSL/TLS negotiation",
                        duration: tlsHandshake,
                        percentage: tlsHandshake / timings.total * 100,
                        color: TrafficTheme.tlsColor
                    )
                    Divider()
                }

                if timings.requestSend > 0 {
                    TimingDetailRow(
                        phase: "Request Sent",
                        description: "Sending request data",
                        duration: timings.requestSend,
                        percentage: timings.requestSend / timings.total * 100,
                        color: TrafficTheme.requestColor
                    )
                    Divider()
                }

                let waiting = timings.timeToFirstByte - timings.requestSend
                if waiting > 0 {
                    TimingDetailRow(
                        phase: "Waiting (TTFB)",
                        description: "Time to first byte",
                        duration: waiting,
                        percentage: waiting / timings.total * 100,
                        color: TrafficTheme.responseColor
                    )
                    Divider()
                }

                if timings.responseReceive > 0 {
                    TimingDetailRow(
                        phase: "Content Download",
                        description: "Downloading response",
                        duration: timings.responseReceive,
                        percentage: timings.responseReceive / timings.total * 100,
                        color: TrafficTheme.downloadColor
                    )
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    // MARK: - Comparison Section

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)

            VStack(spacing: 12) {
                PerformanceIndicator(
                    label: "Response Time",
                    value: record.duration,
                    thresholds: (good: 0.3, warning: 1.0, bad: 3.0),
                    format: { formatDuration($0) }
                )

                if let timings = record.timings {
                    PerformanceIndicator(
                        label: "Time to First Byte",
                        value: timings.timeToFirstByte,
                        thresholds: (good: 0.2, warning: 0.6, bad: 1.5),
                        format: { formatDuration($0) }
                    )

                    if let tlsHandshake = timings.tlsHandshake, tlsHandshake > 0 {
                        PerformanceIndicator(
                            label: "TLS Handshake",
                            value: tlsHandshake,
                            thresholds: (good: 0.1, warning: 0.3, bad: 0.5),
                            format: { formatDuration($0) }
                        )
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

// MARK: - Supporting Views

struct TimingOverviewItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

struct TimingLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
}

struct TimingDetailRow: View {
    let phase: String
    let description: String
    let duration: TimeInterval
    let percentage: Double
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(duration))
                    .font(.system(.subheadline, design: .monospaced))
                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

struct PerformanceIndicator: View {
    let label: String
    let value: Double
    let thresholds: (good: Double, warning: Double, bad: Double)
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)

            Spacer()

            Text(format(value))
                .font(.system(.subheadline, design: .monospaced))

            Circle()
                .fill(indicatorColor)
                .frame(width: 12, height: 12)
        }
    }

    private var indicatorColor: Color {
        if value <= thresholds.good {
            return .green
        } else if value <= thresholds.warning {
            return .orange
        } else {
            return .red
        }
    }
}

#Preview {
    NetCheckerTrafficUI_TimingDetailView(
        record: TrafficRecord(
            duration: 0.515,
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .get
            ),
            response: ResponseData(statusCode: 200),
            timings: RequestTimings(
                dnsLookup: 0.015,
                tcpConnect: 0.045,
                tlsHandshake: 0.120,
                requestSend: 0.005,
                serverWait: 0.250,
                responseReceive: 0.080,
                total: 0.515
            )
        )
    )
}
