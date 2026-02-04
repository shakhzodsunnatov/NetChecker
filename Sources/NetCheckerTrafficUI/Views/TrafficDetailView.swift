import SwiftUI
import NetCheckerTrafficCore

/// Detailed view for a traffic record with tabs
public struct NetCheckerTrafficUI_TrafficDetailView: View {
    let record: TrafficRecord

    @State private var selectedTab = 0
    @State private var showingEditor = false
    @SwiftUI.Environment(\.dismiss) private var dismiss

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            recordHeader

            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Request").tag(0)
                Text("Response").tag(1)
                Text("Timing").tag(2)
                if record.security != nil {
                    Text("Security").tag(3)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Tab content - use switch instead of TabView for macOS compatibility
            Group {
                switch selectedTab {
                case 0:
                    NetCheckerTrafficUI_RequestDetailView(record: record)
                case 1:
                    NetCheckerTrafficUI_ResponseDetailView(record: record)
                case 2:
                    NetCheckerTrafficUI_TimingDetailView(record: record)
                case 3:
                    if record.security != nil {
                        NetCheckerTrafficUI_SecurityDetailView(record: record)
                    }
                default:
                    NetCheckerTrafficUI_RequestDetailView(record: record)
                }
            }
        }
        .navigationTitle("Request Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ExportMenuButton(record: record)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Edit & Retry", systemImage: "pencil")
                    }

                    Button {
                        retryRequest()
                    } label: {
                        Label("Retry Original", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button {
                        copyAsCURL()
                    } label: {
                        Label("Copy as cURL", systemImage: "terminal")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NetCheckerTrafficUI_RequestEditorView(record: record)
        }
    }

    private var recordHeader: some View {
        VStack(spacing: 8) {
            HStack {
                NetCheckerTrafficUI_MethodBadge(method: record.method)

                if let statusCode = record.statusCode {
                    NetCheckerTrafficUI_StatusCodeBadge(statusCode: statusCode)
                } else {
                    StateBadge(state: record.state)
                }

                Spacer()

                Text(record.formattedDuration)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if record.responseSize > 0 {
                    NetCheckerTrafficUI_SizeIndicator(bytes: record.responseSize)
                }
            }

            Text(record.url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if record.security != nil {
                    NetCheckerTrafficUI_SSLStatusBadge(securityInfo: record.security)
                }

                if case .mocked = record.state {
                    Text("MOCKED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }

                Spacer()

                Text(formatTimestamp(record.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func retryRequest() {
        Task {
            _ = await RequestRetrier.retry(record: record)
        }
    }

    private func copyAsCURL() {
        let curl = CURLFormatter.format(record: record)
        #if canImport(UIKit)
        UIPasteboard.general.string = curl
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curl, forType: .string)
        #endif
    }
}

#Preview {
    NavigationStack {
        NetCheckerTrafficUI_TrafficDetailView(
            record: TrafficRecord(
                duration: 0.5,
                request: RequestData(
                    url: URL(string: "https://api.example.com/users?page=1")!,
                    method: .get
                ),
                response: ResponseData(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: """
                    {"users": [{"id": 1, "name": "John"}]}
                    """.data(using: .utf8)
                )
            )
        )
    }
}
