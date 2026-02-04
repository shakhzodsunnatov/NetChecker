import SwiftUI
import NetCheckerTrafficCore

/// Statistics dashboard view
public struct NetCheckerTrafficUI_TrafficStatisticsView: View {
    let records: [TrafficRecord]

    @State private var selectedTimeRange: TimeRange = .all

    public init(records: [TrafficRecord]) {
        self.records = records
    }

    enum TimeRange: String, CaseIterable {
        case lastMinute = "1m"
        case last5Minutes = "5m"
        case last15Minutes = "15m"
        case lastHour = "1h"
        case all = "All"

        var interval: TimeInterval? {
            switch self {
            case .lastMinute: return 60
            case .last5Minutes: return 300
            case .last15Minutes: return 900
            case .lastHour: return 3600
            case .all: return nil
            }
        }
    }

    private var filteredRecords: [TrafficRecord] {
        guard let interval = selectedTimeRange.interval else {
            return records
        }

        let cutoff = Date().addingTimeInterval(-interval)
        return records.filter { $0.timestamp > cutoff }
    }

    private var statistics: TrafficStatistics {
        TrafficStatistics(from: filteredRecords)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Time range picker
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Overview cards
                overviewCards

                // Response time chart
                responseTimeSection

                // Status codes distribution
                statusCodesSection

                // Top hosts
                topHostsSection

                // Methods distribution
                methodsSection

                // Errors section
                if statistics.failedRequests > 0 {
                    errorsSection
                }
            }
            .padding()
        }
        .navigationTitle("Statistics")
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "Total Requests",
                value: "\(statistics.totalRequests)",
                icon: "arrow.up.arrow.down",
                color: .blue
            )

            StatCard(
                title: "Success Rate",
                value: String(format: "%.1f%%", statistics.successRate),
                icon: "checkmark.circle",
                color: statistics.successRate > 90 ? .green : .orange
            )

            StatCard(
                title: "Avg Response",
                value: formatDuration(statistics.avgResponseTime),
                icon: "clock",
                color: statistics.avgResponseTime < 1 ? .green : .orange
            )

            StatCard(
                title: "Total Data",
                value: formatBytes(statistics.totalBytesReceived),
                icon: "arrow.down.circle",
                color: .purple
            )
        }
    }

    // MARK: - Response Time Section

    private var responseTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Response Times")
                .font(.headline)

            VStack(spacing: 8) {
                ResponseTimeRow(
                    label: "Minimum",
                    value: statistics.fastestRequest?.duration ?? 0,
                    color: .green
                )
                ResponseTimeRow(
                    label: "Average",
                    value: statistics.avgResponseTime,
                    color: .blue
                )
                ResponseTimeRow(
                    label: "P50 (Median)",
                    value: statistics.medianResponseTime,
                    color: .blue
                )
                ResponseTimeRow(
                    label: "P95",
                    value: statistics.p95ResponseTime,
                    color: .orange
                )
                ResponseTimeRow(
                    label: "P99",
                    value: statistics.p99ResponseTime,
                    color: .red
                )
                ResponseTimeRow(
                    label: "Maximum",
                    value: statistics.slowestRequest?.duration ?? 0,
                    color: .red
                )
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    // MARK: - Status Codes Section

    private var statusCodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status Codes")
                .font(.headline)

            VStack(spacing: 0) {
                let sortedCategories = statistics.requestsByCategory.sorted(by: { $0.value > $1.value })
                ForEach(Array(sortedCategories.enumerated()), id: \.element.key) { index, item in
                    let category = item.key
                    let count = item.value
                    HStack {
                        Circle()
                            .fill(statusCategoryColor(category))
                            .frame(width: 12, height: 12)

                        Text(category.displayName)
                            .font(.subheadline)

                        Spacer()

                        Text("\(count)")
                            .font(.system(.subheadline, design: .monospaced))

                        Text(String(format: "%.1f%%", Double(count) / Double(max(statistics.totalRequests, 1)) * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding()

                    if index < sortedCategories.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    private func statusCategoryColor(_ category: StatusCategory) -> Color {
        switch category {
        case .informational: return .gray
        case .success: return .green
        case .redirect: return .blue
        case .clientError: return .orange
        case .serverError: return .red
        case .unknown: return .gray
        }
    }

    // MARK: - Top Hosts Section

    private var topHostsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Hosts")
                .font(.headline)

            VStack(spacing: 0) {
                let topHosts = Array(statistics.requestsByHost
                    .sorted(by: { $0.value > $1.value })
                    .prefix(5))

                ForEach(Array(topHosts.enumerated()), id: \.element.key) { index, item in
                    let host = item.key
                    let count = item.value
                    HStack {
                        Text(host)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)

                        Spacer()

                        Text("\(count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    if index < topHosts.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    // MARK: - Methods Section

    private var methodsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HTTP Methods")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(HTTPMethod.allCases, id: \.rawValue) { method in
                    let count = statistics.requestsByMethod[method] ?? 0
                    if count > 0 {
                        VStack(spacing: 4) {
                            Text("\(count)")
                                .font(.headline)
                            Text(method.rawValue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(TrafficTheme.methodBackgroundColor(for: method))
                        .foregroundColor(TrafficTheme.methodColor(for: method))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Errors Section

    private var errorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Errors")
                    .font(.headline)
            }

            let errorRecords = filteredRecords.filter { record in
                record.isError || (record.statusCode ?? 0) >= 400
            }

            VStack(spacing: 0) {
                let displayRecords = Array(errorRecords.prefix(5))
                ForEach(Array(displayRecords.enumerated()), id: \.element.id) { index, record in
                    HStack {
                        if let statusCode = record.statusCode {
                            NetCheckerTrafficUI_StatusCodeBadge(statusCode: statusCode)
                        } else {
                            Text("Error")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Text(record.path)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text(record.host)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    if index < displayRecords.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            HStack {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }

            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

struct ResponseTimeRow: View {
    let label: String
    let value: TimeInterval
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(formatDuration(value))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_TrafficStatisticsView(records: [])
    }
}
