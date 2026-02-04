import SwiftUI
import NetCheckerTrafficCore

/// View for retrying requests with different configurations
public struct NetCheckerTrafficUI_RetryView: View {
    let record: TrafficRecord

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EnvironmentStore.shared

    @State private var urlString: String
    @State private var isRetrying = false
    @State private var retryResult: RetryResult?
    @State private var showingDiff = false

    public init(record: TrafficRecord) {
        self.record = record
        self._urlString = State(initialValue: record.url.absoluteString)
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Original request info
                Section("Original Request") {
                    LabeledContent("Method", value: record.method.rawValue)
                    LabeledContent("URL", value: record.url.absoluteString)

                    if let status = record.statusCode {
                        LabeledContent("Status") {
                            NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
                        }
                    }

                    LabeledContent("Duration", value: record.formattedDuration)
                }

                // Modified URL
                Section("Retry Configuration") {
                    TextField("URL", text: $urlString)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .autocorrectionDisabled()
                }

                // Environment quick switch
                if !store.groups.isEmpty {
                    Section("Switch Environment") {
                        ForEach(store.groups) { group in
                            ForEach(group.environments) { env in
                                Button {
                                    switchToEnvironment(env)
                                } label: {
                                    HStack {
                                        Text(env.emoji)
                                        Text(env.name)
                                        Spacer()
                                        Text(env.baseURL.host ?? "")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Retry button
                Section {
                    Button {
                        performRetry()
                    } label: {
                        HStack {
                            Spacer()
                            if isRetrying {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isRetrying ? "Retrying..." : "Retry Request")
                            Spacer()
                        }
                    }
                    .disabled(isRetrying || !isValidURL)
                }

                // Result
                if let result = retryResult {
                    Section("Retry Result") {
                        retryResultView(result)
                    }
                }
            }
            .navigationTitle("Retry Request")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if retryResult != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Compare") {
                            showingDiff = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDiff) {
                if let result = retryResult {
                    NavigationStack {
                        NetCheckerTrafficUI_ResponseDiffView(
                            original: record,
                            retry: result
                        )
                    }
                }
            }
        }
    }

    private var isValidURL: Bool {
        URL(string: urlString) != nil
    }

    private func switchToEnvironment(_ env: NetCheckerTrafficCore.Environment) {
        if var components = URLComponents(url: record.url, resolvingAgainstBaseURL: false) {
            components.scheme = env.baseURL.scheme
            components.host = env.baseURL.host
            components.port = env.baseURL.port

            if let newURL = components.url {
                urlString = newURL.absoluteString
            }
        }
    }

    private func performRetry() {
        guard let url = URL(string: urlString) else { return }

        isRetrying = true
        retryResult = nil

        Task {
            let result = await RequestRetrier.retry(record: record, withURL: url)

            await MainActor.run {
                retryResult = result
                isRetrying = false
            }
        }
    }

    private func retryResultView(_ result: RetryResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                if result.isSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Success")
                        .fontWeight(.medium)
                } else if result.error != nil {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Failed")
                        .fontWeight(.medium)
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.orange)
                    Text("Unknown")
                }

                Spacer()

                if let status = result.statusCode {
                    NetCheckerTrafficUI_StatusCodeBadge(statusCode: status)
                }
            }

            // Duration
            HStack {
                Text("Duration")
                    .foregroundColor(.secondary)
                Spacer()
                Text(result.formattedDuration)
                    .font(.system(.body, design: .monospaced))

                // Compare with original
                let change = result.duration - record.duration
                let changePercent = record.duration > 0 ? (change / record.duration) * 100 : 0
                Text(String(format: "%+.0f%%", changePercent))
                    .font(.caption)
                    .foregroundColor(change > 0 ? .red : .green)
            }

            // Error if any
            if let error = result.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Response preview
            if let response = result.response,
               let bodyString = response.bodyString {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Response Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(bodyString.prefix(200)))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(5)
                }
            }
        }
    }
}

#Preview {
    NetCheckerTrafficUI_RetryView(
        record: TrafficRecord(
            duration: 0.5,
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .get
            ),
            response: ResponseData(statusCode: 200)
        )
    )
}
