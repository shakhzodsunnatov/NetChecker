import SwiftUI
import NetCheckerTrafficCore

/// Waterfall chart showing request timeline
public struct NetCheckerTrafficUI_WaterfallChartView: View {
    let records: [TrafficRecord]
    let timeWindow: TimeInterval

    @State private var selectedRecord: TrafficRecord?

    public init(records: [TrafficRecord], timeWindow: TimeInterval = 10) {
        self.records = records
        self.timeWindow = timeWindow
    }

    private var startTime: Date {
        records.first?.timestamp ?? Date()
    }

    private var endTime: Date {
        startTime.addingTimeInterval(timeWindow)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Time axis header
            timeAxisHeader

            // Waterfall rows
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(records) { record in
                        WaterfallRow(
                            record: record,
                            startTime: startTime,
                            timeWindow: timeWindow,
                            isSelected: selectedRecord?.id == record.id
                        )
                        .onTapGesture {
                            selectedRecord = record
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                NetCheckerTrafficUI_TrafficDetailView(record: record)
            }
        }
    }

    private var timeAxisHeader: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 150 // Account for label column
            let intervals = 5
            let intervalWidth = width / CGFloat(intervals)

            HStack(spacing: 0) {
                Text("Request")
                    .font(.caption2)
                    .frame(width: 150, alignment: .leading)
                    .padding(.leading, 8)

                ForEach(0...intervals, id: \.self) { i in
                    Text(formatTime(Double(i) * timeWindow / Double(intervals)))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: intervalWidth, alignment: .leading)
                }
            }
        }
        .frame(height: 20)
        .background(Color.gray.opacity(0.15))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        }
        return String(format: "%.1fs", seconds)
    }
}

// MARK: - Waterfall Row

struct WaterfallRow: View {
    let record: TrafficRecord
    let startTime: Date
    let timeWindow: TimeInterval
    let isSelected: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 150
            let barWidth = calculateBarWidth(totalWidth: width)
            let barOffset = calculateBarOffset(totalWidth: width)

            HStack(spacing: 0) {
                // Label
                HStack(spacing: 4) {
                    MethodBadgeCompact(method: record.method)

                    Text(record.path)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 146, alignment: .leading)
                .padding(.leading, 4)

                // Bar
                ZStack(alignment: .leading) {
                    // Background grid
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 1)
                            Spacer()
                        }
                    }

                    // Timing bar
                    if let timings = record.timings {
                        timingBar(timings: timings, totalWidth: width)
                            .offset(x: barOffset)
                    } else {
                        // Simple bar for records without timing details
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor)
                            .frame(width: max(barWidth, 4), height: 12)
                            .offset(x: barOffset)
                    }
                }
            }
        }
        .frame(height: 24)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private func timingBar(timings: RequestTimings, totalWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // DNS
            if timings.dnsLookup > 0 {
                Rectangle()
                    .fill(TrafficTheme.dnsColor)
                    .frame(width: segmentWidth(timings.dnsLookup, totalWidth: totalWidth))
            }

            // TCP
            if timings.tcpConnect > 0 {
                Rectangle()
                    .fill(TrafficTheme.tcpColor)
                    .frame(width: segmentWidth(timings.tcpConnect, totalWidth: totalWidth))
            }

            // TLS
            if let tlsHandshake = timings.tlsHandshake, tlsHandshake > 0 {
                Rectangle()
                    .fill(TrafficTheme.tlsColor)
                    .frame(width: segmentWidth(tlsHandshake, totalWidth: totalWidth))
            }

            // Request
            if timings.requestSend > 0 {
                Rectangle()
                    .fill(TrafficTheme.requestColor)
                    .frame(width: segmentWidth(timings.requestSend, totalWidth: totalWidth))
            }

            // Waiting
            let waiting = timings.timeToFirstByte - timings.requestSend
            if waiting > 0 {
                Rectangle()
                    .fill(TrafficTheme.responseColor)
                    .frame(width: segmentWidth(waiting, totalWidth: totalWidth))
            }

            // Download
            if timings.responseReceive > 0 {
                Rectangle()
                    .fill(TrafficTheme.downloadColor)
                    .frame(width: segmentWidth(timings.responseReceive, totalWidth: totalWidth))
            }
        }
        .frame(height: 12)
        .cornerRadius(2)
    }

    private func segmentWidth(_ duration: TimeInterval, totalWidth: CGFloat) -> CGFloat {
        let width = (duration / timeWindow) * totalWidth
        return max(width, 1)
    }

    private func calculateBarWidth(totalWidth: CGFloat) -> CGFloat {
        let duration = record.duration
        let width = (duration / timeWindow) * totalWidth
        return max(width, 4)
    }

    private func calculateBarOffset(totalWidth: CGFloat) -> CGFloat {
        let offset = record.timestamp.timeIntervalSince(startTime)
        return (offset / timeWindow) * totalWidth
    }

    private var barColor: Color {
        if record.isError {
            return .red
        } else if case .pending = record.state {
            return .orange
        } else if let status = record.statusCode {
            return TrafficTheme.statusColor(for: status)
        }
        return .gray
    }
}

// MARK: - Compact Waterfall

public struct CompactWaterfallView: View {
    let records: [TrafficRecord]

    public init(records: [TrafficRecord]) {
        self.records = records
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Request Timeline")
                .font(.caption)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let maxTime = records.map { $0.duration }.max() ?? 1

                VStack(spacing: 2) {
                    ForEach(records.prefix(10)) { record in
                        HStack(spacing: 4) {
                            Text(record.path)
                                .font(.system(size: 8))
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(TrafficTheme.statusColor(for: record.statusCode ?? 0))
                                .frame(
                                    width: max((record.duration / maxTime) * (width - 70), 4),
                                    height: 8
                                )

                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NetCheckerTrafficUI_WaterfallChartView(
        records: [
            TrafficRecord(
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
        ]
    )
}
