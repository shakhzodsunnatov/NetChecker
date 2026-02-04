import SwiftUI
import NetCheckerTrafficCore

/// View for comparing two responses
public struct NetCheckerTrafficUI_ResponseDiffView: View {
    let original: TrafficRecord
    let retry: RetryResult

    @State private var selectedTab = 0

    public init(original: TrafficRecord, retry: RetryResult) {
        self.original = original
        self.retry = retry
    }

    private var diff: ResponseDiff {
        ResponseDiffer.diff(original: original, retry: retry)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Summary header
            diffSummaryHeader

            // Tab selection
            Picker("View", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Status").tag(1)
                Text("Headers").tag(2)
                Text("Body").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    overviewTab
                case 1:
                    statusTab
                case 2:
                    headersTab
                case 3:
                    bodyTab
                default:
                    overviewTab
                }
            }
        }
        .navigationTitle("Response Comparison")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Summary Header

    private var diffSummaryHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Original")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let status = original.statusCode {
                        NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Retry")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let status = retry.statusCode {
                        NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
                    }
                }
            }

            // Change indicator
            if diff.hasChanges {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(diff.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Responses are identical")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status comparison
                if let statusDiff = diff.statusDiff {
                    DiffCard(title: "Status Code") {
                        HStack {
                            Text("\(statusDiff.original)")
                                .font(.system(.title, design: .monospaced))
                                .foregroundColor(TrafficTheme.statusColor(for: statusDiff.original))

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)

                            Text("\(statusDiff.retry)")
                                .font(.system(.title, design: .monospaced))
                                .foregroundColor(TrafficTheme.statusColor(for: statusDiff.retry))

                            Spacer()

                            if statusDiff.improved {
                                Text("Improved")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if statusDiff.worsened {
                                Text("Worsened")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // Duration comparison
                if let durationDiff = diff.durationDiff {
                    DiffCard(title: "Duration") {
                        HStack {
                            Text(formatDuration(durationDiff.original))
                                .font(.system(.headline, design: .monospaced))

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)

                            Text(formatDuration(durationDiff.retry))
                                .font(.system(.headline, design: .monospaced))

                            Spacer()

                            let changePercent = durationDiff.percentChange
                            Text(String(format: "%+.0f%%", changePercent))
                                .font(.caption)
                                .foregroundColor(durationDiff.improved ? .green : .red)
                        }
                    }
                }

                // Size comparison
                if let sizeDiff = diff.sizeDiff {
                    DiffCard(title: "Response Size") {
                        HStack {
                            Text(formatBytes(sizeDiff.original))
                                .font(.system(.headline, design: .monospaced))

                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)

                            Text(formatBytes(sizeDiff.retry))
                                .font(.system(.headline, design: .monospaced))

                            Spacer()

                            Text(String(format: "%+.0f%%", sizeDiff.percentChange))
                                .font(.caption)
                                .foregroundColor(sizeDiff.change > 0 ? .orange : .green)
                        }
                    }
                }

                // Headers summary
                if !diff.headersDiff.isEmpty {
                    DiffCard(title: "Headers") {
                        VStack(alignment: .leading, spacing: 4) {
                            let added = diff.headersDiff.filter { $0.type == .added }.count
                            let removed = diff.headersDiff.filter { $0.type == .removed }.count
                            let modified = diff.headersDiff.filter { $0.type == .modified }.count

                            if added > 0 {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                    Text("\(added) added")
                                        .font(.caption)
                                }
                            }

                            if removed > 0 {
                                HStack {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                    Text("\(removed) removed")
                                        .font(.caption)
                                }
                            }

                            if modified > 0 {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("\(modified) modified")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                // Body summary
                if let bodyDiff = diff.bodyDiff, bodyDiff.type != .identical {
                    DiffCard(title: "Body") {
                        HStack {
                            Text(bodyDiffDescription(bodyDiff))
                                .font(.caption)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Status Tab

    private var statusTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let statusDiff = diff.statusDiff {
                    VStack(spacing: 20) {
                        // Original
                        VStack(spacing: 8) {
                            Text("Original")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            StatusCodeBadgeExtended(statusCode: statusDiff.original)
                        }

                        Image(systemName: "arrow.down")
                            .foregroundColor(.secondary)

                        // Retry
                        VStack(spacing: 8) {
                            Text("Retry")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            StatusCodeBadgeExtended(statusCode: statusDiff.retry)
                        }
                    }
                    .padding()
                } else {
                    Text("Status codes are identical")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
    }

    // MARK: - Headers Tab

    private var headersTab: some View {
        ScrollView {
            VStack(spacing: 8) {
                if diff.headersDiff.isEmpty {
                    Text("Headers are identical")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(diff.headersDiff) { headerDiff in
                        HeaderDiffRow(diff: headerDiff)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Body Tab

    private var bodyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let bodyDiff = diff.bodyDiff {
                    switch bodyDiff.type {
                    case .identical:
                        Text("Bodies are identical")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()

                    case .json:
                        ForEach(bodyDiff.jsonDiffs) { jsonDiff in
                            JSONDiffRow(diff: jsonDiff)
                        }

                    case .text:
                        ForEach(bodyDiff.lineDiffs) { lineDiff in
                            LineDiffRow(diff: lineDiff)
                        }

                    case .binary:
                        Text("Binary content differs")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                } else {
                    Text("No body to compare")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding()
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

    private func bodyDiffDescription(_ diff: BodyDiff) -> String {
        switch diff.type {
        case .identical: return "Identical"
        case .json: return "\(diff.jsonDiffs.count) JSON differences"
        case .text: return "\(diff.lineDiffs.count) line differences"
        case .binary: return "Binary content differs"
        }
    }
}

// MARK: - Supporting Views

struct DiffCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

struct HeaderDiffRow: View {
    let diff: HeaderDiff

    var body: some View {
        HStack(alignment: .top) {
            Text(diff.type.symbol)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(diffColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(diff.key)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)

                if let original = diff.originalValue {
                    HStack {
                        Text("-")
                            .foregroundColor(.red)
                        Text(original)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }

                if let retry = diff.retryValue {
                    HStack {
                        Text("+")
                            .foregroundColor(.green)
                        Text(retry)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(diffColor.opacity(0.1))
        .cornerRadius(4)
    }

    private var diffColor: Color {
        switch diff.type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }
}

struct JSONDiffRow: View {
    let diff: JSONDiff

    var body: some View {
        HStack(alignment: .top) {
            Text(diff.type.symbol)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(diffColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(diff.path)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.blue)

                if let original = diff.originalValue {
                    Text("- \(original)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.red)
                }

                if let retry = diff.retryValue {
                    Text("+ \(retry)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.green)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(diffColor.opacity(0.1))
        .cornerRadius(4)
    }

    private var diffColor: Color {
        switch diff.type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }
}

struct LineDiffRow: View {
    let diff: LineDiff

    var body: some View {
        HStack(alignment: .top) {
            Text("\(diff.lineNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(diff.type.symbol)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(diffColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                if let original = diff.originalLine {
                    Text(original)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.red)
                }

                if let retry = diff.retryLine {
                    Text(retry)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.green)
                }

                if let line = diff.line {
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(diffColor)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var diffColor: Color {
        switch diff.type {
        case .added: return .green
        case .removed: return .red
        case .modified: return .orange
        }
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_ResponseDiffView(
            original: TrafficRecord(
                duration: 0.5,
                request: RequestData(
                    url: URL(string: "https://api.example.com/users")!,
                    method: .get
                ),
                response: ResponseData(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: """
                    {"name": "John", "age": 30}
                    """.data(using: .utf8)
                )
            ),
            retry: RetryResult(
                response: ResponseData(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: """
                    {"name": "John", "age": 31}
                    """.data(using: .utf8)
                ),
                duration: 0.3
            )
        )
    }
}
