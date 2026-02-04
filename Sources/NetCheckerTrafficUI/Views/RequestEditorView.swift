import SwiftUI
import NetCheckerTrafficCore

/// View for editing and retrying a request with modified parameters
public struct NetCheckerTrafficUI_RequestEditorView: View {
    let originalRecord: TrafficRecord

    @SwiftUI.Environment(\.dismiss) private var dismiss

    // Editable fields
    @State private var url: String
    @State private var method: HTTPMethod
    @State private var headers: [EditableHeader]
    @State private var bodyText: String

    // State
    @State private var isLoading = false
    @State private var response: ResponseData?
    @State private var responseError: String?
    @State private var showingAddHeader = false
    @State private var newHeaderKey = ""
    @State private var newHeaderValue = ""

    public init(record: TrafficRecord) {
        self.originalRecord = record
        _url = State(initialValue: record.url.absoluteString)
        _method = State(initialValue: record.method)
        _headers = State(initialValue: record.request.headers.map { EditableHeader(key: $0.key, value: $0.value) })
        _bodyText = State(initialValue: record.request.bodyString ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                // URL Section
                Section {
                    #if os(iOS)
                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    #else
                    TextField("URL", text: $url)
                        .autocorrectionDisabled()
                    #endif
                } header: {
                    Text("URL")
                } footer: {
                    Text("Full URL including scheme and path")
                }

                // Method Section
                Section("Method") {
                    // Common methods as buttons
                    HStack(spacing: 8) {
                        ForEach([HTTPMethod.get, .post, .put, .patch, .delete], id: \.rawValue) { m in
                            MethodSelectButton(
                                method: m,
                                isSelected: method == m,
                                action: { method = m }
                            )
                        }

                        // More methods in menu
                        Menu {
                            ForEach([HTTPMethod.head, .options, .trace, .connect], id: \.rawValue) { m in
                                Button {
                                    method = m
                                } label: {
                                    HStack {
                                        Text(m.rawValue)
                                        if method == m {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text("•••")
                                .font(.caption)
                                .fontWeight(.bold)
                                .frame(minWidth: 40)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                }

                // Headers Section
                Section {
                    ForEach($headers) { $header in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                #if os(iOS)
                                TextField("Key", text: $header.key)
                                    .font(.system(.body, design: .monospaced))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                #else
                                TextField("Key", text: $header.key)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                #endif
                            }

                            #if os(iOS)
                            TextField("Value", text: $header.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            #else
                            TextField("Value", text: $header.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .autocorrectionDisabled()
                            #endif
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: deleteHeaders)

                    Button {
                        showingAddHeader = true
                    } label: {
                        Label("Add Header", systemImage: "plus.circle")
                    }
                } header: {
                    HStack {
                        Text("Headers")
                        Spacer()
                        Text("\(headers.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Common Headers Quick Add
                Section("Quick Add") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            QuickHeaderButton(title: "Bearer Token") {
                                addHeader("Authorization", "Bearer YOUR_TOKEN")
                            }

                            QuickHeaderButton(title: "JSON Content") {
                                addHeader("Content-Type", "application/json")
                            }

                            QuickHeaderButton(title: "Accept JSON") {
                                addHeader("Accept", "application/json")
                            }

                            QuickHeaderButton(title: "API Key") {
                                addHeader("X-API-Key", "YOUR_API_KEY")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Body Section
                if method != .get && method != .head {
                    Section {
                        TextEditor(text: $bodyText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 150)

                        HStack {
                            Button("Format JSON") {
                                formatBody()
                            }
                            .disabled(bodyText.isEmpty)

                            Spacer()

                            Button("Clear") {
                                bodyText = ""
                            }
                            .foregroundColor(.red)
                        }
                    } header: {
                        Text("Request Body")
                    }
                }

                // Response Section (after sending)
                if let response = response {
                    Section("Response") {
                        HStack {
                            Text("Status")
                            Spacer()
                            NetCheckerTrafficUI_StatusCodeBadge(statusCode: response.statusCode)
                        }

                        if let bodyString = response.bodyString {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Body")
                                    Spacer()
                                    NetCheckerTrafficUI_CopyButton(text: bodyString, label: "Copy")
                                }

                                ScrollView {
                                    Text(formatResponseBody(bodyString, contentType: response.contentType ?? .plainText))
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 200)
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                if let error = responseError {
                    Section("Error") {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit & Retry")
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
                    Button {
                        sendRequest()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Send")
                        }
                    }
                    .disabled(isLoading || url.isEmpty)
                }
            }
            .alert("Add Header", isPresented: $showingAddHeader) {
                TextField("Header Name", text: $newHeaderKey)
                TextField("Header Value", text: $newHeaderValue)
                Button("Cancel", role: .cancel) {
                    newHeaderKey = ""
                    newHeaderValue = ""
                }
                Button("Add") {
                    if !newHeaderKey.isEmpty {
                        addHeader(newHeaderKey, newHeaderValue)
                        newHeaderKey = ""
                        newHeaderValue = ""
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteHeaders(at offsets: IndexSet) {
        headers.remove(atOffsets: offsets)
    }

    private func addHeader(_ key: String, _ value: String) {
        // Check if header already exists
        if let index = headers.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) {
            headers[index].value = value
        } else {
            headers.append(EditableHeader(key: key, value: value))
        }
    }

    private func formatBody() {
        if let data = bodyText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            bodyText = prettyString
        }
    }

    private func formatResponseBody(_ body: String, contentType: ContentType) -> String {
        if contentType == .json, let formatted = JSONFormatter.format(body) {
            return formatted
        }
        return body
    }

    private func sendRequest() {
        guard let requestURL = URL(string: url) else {
            responseError = "Invalid URL"
            return
        }

        isLoading = true
        response = nil
        responseError = nil

        Task {
            do {
                var request = URLRequest(url: requestURL)
                request.httpMethod = method.rawValue

                // Add headers
                for header in headers where !header.key.isEmpty {
                    request.setValue(header.value, forHTTPHeaderField: header.key)
                }

                // Add body
                if !bodyText.isEmpty && method != .get && method != .head {
                    request.httpBody = bodyText.data(using: .utf8)
                }

                let (data, urlResponse) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    if let httpResponse = urlResponse as? HTTPURLResponse {
                        var responseHeaders: [String: String] = [:]
                        for (key, value) in httpResponse.allHeaderFields {
                            if let keyString = key as? String, let valueString = value as? String {
                                responseHeaders[keyString] = valueString
                            }
                        }

                        response = ResponseData(
                            statusCode: httpResponse.statusCode,
                            headers: responseHeaders,
                            body: data
                        )
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    responseError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct EditableHeader: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

struct QuickHeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct MethodSelectButton: View {
    let method: HTTPMethod
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(method.rawValue)
                .font(.system(.caption, weight: isSelected ? .bold : .medium))
                .frame(minWidth: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(isSelected ? methodColor.opacity(0.2) : Color.gray.opacity(0.15))
                .foregroundColor(isSelected ? methodColor : .secondary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var methodColor: Color {
        switch method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .purple
        case .delete: return .red
        default: return .gray
        }
    }
}

#Preview {
    NetCheckerTrafficUI_RequestEditorView(
        record: TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .post,
                headers: [
                    "Content-Type": "application/json",
                    "Authorization": "Bearer token123"
                ],
                body: "{\"name\": \"John\"}".data(using: .utf8)
            )
        )
    )
}
