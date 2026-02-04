import SwiftUI
import NetCheckerTrafficCore

/// Visual timing bar for request phases
public struct NetCheckerTrafficUI_TimingBarView: View {
    let timings: RequestTimings
    let showLabels: Bool

    public init(timings: RequestTimings, showLabels: Bool = true) {
        self.timings = timings
        self.showLabels = showLabels
    }

    public var body: some View {
        GeometryReader { geometry in
            let total = timings.total
            let width = geometry.size.width

            HStack(spacing: 0) {
                // DNS
                if timings.dnsLookup > 0 {
                    TimingSegment(
                        label: "DNS",
                        duration: timings.dnsLookup,
                        total: total,
                        color: TrafficTheme.dnsColor,
                        showLabel: showLabels,
                        width: width
                    )
                }

                // TCP
                if timings.tcpConnect > 0 {
                    TimingSegment(
                        label: "TCP",
                        duration: timings.tcpConnect,
                        total: total,
                        color: TrafficTheme.tcpColor,
                        showLabel: showLabels,
                        width: width
                    )
                }

                // TLS
                if let tlsHandshake = timings.tlsHandshake, tlsHandshake > 0 {
                    TimingSegment(
                        label: "TLS",
                        duration: tlsHandshake,
                        total: total,
                        color: TrafficTheme.tlsColor,
                        showLabel: showLabels,
                        width: width
                    )
                }

                // Request
                if timings.requestSend > 0 {
                    TimingSegment(
                        label: "Request",
                        duration: timings.requestSend,
                        total: total,
                        color: TrafficTheme.requestColor,
                        showLabel: showLabels,
                        width: width
                    )
                }

                // TTFB (Waiting)
                let waiting = timings.timeToFirstByte - timings.requestSend
                if waiting > 0 {
                    TimingSegment(
                        label: "Waiting",
                        duration: waiting,
                        total: total,
                        color: TrafficTheme.responseColor,
                        showLabel: showLabels,
                        width: width
                    )
                }

                // Download
                if timings.responseReceive > 0 {
                    TimingSegment(
                        label: "Download",
                        duration: timings.responseReceive,
                        total: total,
                        color: TrafficTheme.downloadColor,
                        showLabel: showLabels,
                        width: width
                    )
                }
            }
        }
        .frame(height: showLabels ? 40 : 16)
    }
}

// MARK: - Timing Segment

struct TimingSegment: View {
    let label: String
    let duration: TimeInterval
    let total: TimeInterval
    let color: Color
    let showLabel: Bool
    let width: CGFloat

    var body: some View {
        let segmentWidth = (duration / total) * width

        VStack(spacing: 2) {
            Rectangle()
                .fill(color)
                .frame(width: max(segmentWidth, 2))

            if showLabel && segmentWidth > 30 {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Timing Details List

public struct TimingDetailsList: View {
    let timings: RequestTimings

    public init(timings: RequestTimings) {
        self.timings = timings
    }

    public var body: some View {
        VStack(spacing: 0) {
            if timings.dnsLookup > 0 {
                TimingRow(
                    label: "DNS Lookup",
                    duration: timings.dnsLookup,
                    color: TrafficTheme.dnsColor
                )
            }

            if timings.tcpConnect > 0 {
                TimingRow(
                    label: "TCP Connection",
                    duration: timings.tcpConnect,
                    color: TrafficTheme.tcpColor
                )
            }

            if let tlsHandshake = timings.tlsHandshake, tlsHandshake > 0 {
                TimingRow(
                    label: "TLS Handshake",
                    duration: tlsHandshake,
                    color: TrafficTheme.tlsColor
                )
            }

            if timings.requestSend > 0 {
                TimingRow(
                    label: "Request Sent",
                    duration: timings.requestSend,
                    color: TrafficTheme.requestColor
                )
            }

            if timings.timeToFirstByte > 0 {
                TimingRow(
                    label: "Time to First Byte",
                    duration: timings.timeToFirstByte,
                    color: TrafficTheme.responseColor
                )
            }

            if timings.responseReceive > 0 {
                TimingRow(
                    label: "Content Download",
                    duration: timings.responseReceive,
                    color: TrafficTheme.downloadColor
                )
            }

            Divider()
                .padding(.vertical, 8)

            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                Text(formatDuration(timings.total))
                    .font(.system(.headline, design: .monospaced))
            }
            .padding(.horizontal)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

struct TimingRow: View {
    let label: String
    let duration: TimeInterval
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(formatDuration(duration))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

#Preview {
    VStack(spacing: 20) {
        NetCheckerTrafficUI_TimingBarView(
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
        .padding()

        TimingDetailsList(
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
    }
}
