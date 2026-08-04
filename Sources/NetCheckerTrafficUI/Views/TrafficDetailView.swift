import SwiftUI
import NetCheckerTrafficCore

/// Detailed view for a traffic record with tabs
public struct NetCheckerTrafficUI_TrafficDetailView: View {
    let record: TrafficRecord

    @State private var selectedTab = 0
    @State private var showingEditor = false
    @State private var showingMockCreator = false
    @State private var showBreakpointAdded = false
    @State private var showMockAdded = false
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var breakpointEngine = BreakpointEngine.shared
    @ObservedObject private var mockEngine = MockEngine.shared

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
        // Одна группа вместо двух ToolbarItem с одинаковым placement:
        // при совпадающем placement порядок не определён, а на узкой панели
        // часть элементов схлопывается или пропадает совсем.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ExportMenuButton(record: record)

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

                    // Breakpoint options
                    Menu {
                        Button {
                            addBreakpoint(direction: .request)
                        } label: {
                            Label("Pause Request", systemImage: "arrow.up.circle")
                        }

                        Button {
                            addBreakpoint(direction: .response)
                        } label: {
                            Label("Pause Response", systemImage: "arrow.down.circle")
                        }

                        Button {
                            addBreakpoint(direction: .both)
                        } label: {
                            Label("Pause Both", systemImage: "arrow.up.arrow.down.circle")
                        }
                    } label: {
                        Label("Add Breakpoint", systemImage: "hand.raised")
                    }

                    Button {
                        showingMockCreator = true
                    } label: {
                        Label("Create Mock Response", systemImage: "theatermasks")
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
        .sheet(isPresented: $showingMockCreator) {
            NavigationStack {
                MockCreatorFromRecordView(record: record)
            }
        }
        .alert("Breakpoint Added", isPresented: $showBreakpointAdded) {
            Button("OK", role: .cancel) { }
            Button("Enable Breakpoints") {
                breakpointEngine.isEnabled = true
            }
        } message: {
            Text("Breakpoint rule added for this URL. Enable breakpoints to pause matching requests.")
        }
        .alert("Mock Created", isPresented: $showMockAdded) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Mock rule created. Future requests to this URL will return your custom response.")
        }
    }

    private func addBreakpoint(direction: BreakpointDirection) {
        let urlPattern = record.url.absoluteString
        let rule = BreakpointRule(
            name: "Break: \(record.url.path)",
            matching: BreakpointMatching(urlPattern: urlPattern),
            direction: direction
        )
        breakpointEngine.addRule(rule)
        showBreakpointAdded = true
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

// MARK: - Mock Creator From Record

struct MockCreatorFromRecordView: View {
    let record: TrafficRecord

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var mockEngine = MockEngine.shared

    @State private var statusCode: Int
    @State private var responseBody: String
    @State private var requestBody: String
    @State private var useCustomRequestBody = false
    @State private var contentType = "application/json"
    @State private var useExactURL = true

    init(record: TrafficRecord) {
        self.record = record
        // Pre-fill with existing response if available
        _statusCode = State(initialValue: record.response?.statusCode ?? 200)
        _responseBody = State(initialValue: record.response?.bodyString ?? "{\n  \"message\": \"Mocked response\"\n}")
        // Pre-fill request body from original request
        _requestBody = State(initialValue: record.request.bodyString ?? "")
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.method.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text(record.url.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                Toggle("Match exact URL", isOn: $useExactURL)
            } header: {
                Text("URL to Mock")
            } footer: {
                Text(useExactURL ? "Will only match this exact URL" : "Will match URL pattern with wildcards")
            }

            // Custom Request Body Section
            if record.method != .get && record.method != .head {
                Section {
                    Toggle("Override Request Body", isOn: $useCustomRequestBody)

                    if useCustomRequestBody {
                        NetCheckerTrafficUI_BodyEditor(
                            title: "Request Body",
                            text: $requestBody,
                            sourceBody: record.request.body,
                            minHeight: 100
                        )
                    }
                } header: {
                    Text("Request Body")
                } footer: {
                    Text(useCustomRequestBody
                         ? "The captured entry will show this body instead of the original one"
                         : "Original request body will be used")
                }
            }

            Section("Response Status") {
                Picker("Status Code", selection: $statusCode) {
                    Group {
                        Text("200 OK").tag(200)
                        Text("201 Created").tag(201)
                        Text("204 No Content").tag(204)
                    }
                    Divider()
                    Group {
                        Text("400 Bad Request").tag(400)
                        Text("401 Unauthorized").tag(401)
                        Text("403 Forbidden").tag(403)
                        Text("404 Not Found").tag(404)
                        Text("422 Unprocessable").tag(422)
                    }
                    Divider()
                    Group {
                        Text("500 Server Error").tag(500)
                        Text("502 Bad Gateway").tag(502)
                        Text("503 Unavailable").tag(503)
                    }
                }
            }

            Section("Content Type") {
                Picker("Type", selection: $contentType) {
                    Text("JSON").tag("application/json")
                    Text("Text").tag("text/plain")
                    Text("HTML").tag("text/html")
                }
                .pickerStyle(.segmented)
            }

            Section {
                NetCheckerTrafficUI_BodyEditor(
                    title: "Response Body",
                    text: $responseBody,
                    sourceBody: record.response?.body,
                    minHeight: 200
                )
            } header: {
                Text("Response Body")
            } footer: {
                Text("This response will be returned instead of the real server response")
            }
        }
        .navigationTitle("Create Mock")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createMock()
                }
            }
        }
    }



    private func createMock() {
        let urlPattern: String
        if useExactURL {
            urlPattern = record.url.absoluteString
        } else {
            // Create pattern with wildcards for query params
            var components = URLComponents(url: record.url, resolvingAgainstBaseURL: false)
            components?.query = nil
            urlPattern = (components?.string ?? record.url.absoluteString) + "*"
        }

        let response = MockResponse(
            statusCode: statusCode,
            headers: ["Content-Type": contentType],
            body: responseBody.data(using: .utf8),
            requestBodyOverride: useCustomRequestBody ? requestBody.data(using: .utf8) : nil
        )

        let rule = MockRule(
            name: "Mock: \(record.url.path)",
            isEnabled: true,
            matching: MockMatching(urlPattern: urlPattern, method: record.method),
            action: .respond(response)
        )

        mockEngine.addRule(rule)

        // Enable mock engine
        if !mockEngine.isEnabled {
            mockEngine.isEnabled = true
        }

        dismiss()
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
