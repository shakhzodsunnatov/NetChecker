import SwiftUI
import NetCheckerTrafficCore

/// Detail view for response information
public struct NetCheckerTrafficUI_ResponseDetailView: View {
    let record: TrafficRecord

    @State private var showRawHeaders = false
    @State private var showFormattedBody = true

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let response = record.response {
                    // Status Section
                    statusSection(response)

                    // Headers Section
                    headersSection(response)

                    // Body Section
                    if let body = response.body, !body.isEmpty {
                        bodySection(response)
                    }

                    // Redirects Section
                    if !record.redirects.isEmpty {
                        redirectsSection
                    }
                } else if case .pending = record.state {
                    pendingView
                } else if record.isError {
                    errorView
                } else {
                    noResponseView
                }
            }
            .padding()
        }
    }

    // MARK: - Status Section

    private func statusSection(_ response: ResponseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            HStack(spacing: 12) {
                StatusCodeBadgeExtended(statusCode: response.statusCode)

                Spacer()

                if let mime = response.mimeType {
                    Text(mime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - Headers Section

    private func headersSection(_ response: ResponseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Headers")
                    .font(.headline)

                Spacer()

                Toggle("Raw", isOn: $showRawHeaders)
                    .toggleStyle(.button)
                    .font(.caption)
            }

            if showRawHeaders {
                rawHeadersView(response)
            } else {
                NetCheckerTrafficUI_HeadersTableView(
                    headers: response.headers,
                    showSearch: response.headers.count > 5
                )
            }
        }
    }

    private func rawHeadersView(_ response: ResponseData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(response.headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                Text("\(key): \(value)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Body Section

    private func bodySection(_ response: ResponseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Body")
                    .font(.headline)

                Spacer()

                NetCheckerTrafficUI_SizeIndicator(bytes: response.bodySize)

                if response.contentType == .json || response.contentType == .xml {
                    Toggle("Format", isOn: $showFormattedBody)
                        .toggleStyle(.button)
                        .font(.caption)
                }

                if let bodyString = response.bodyString {
                    NetCheckerTrafficUI_CopyButton(text: bodyString, label: "Copy")
                }
            }

            responseBodyView(response)
        }
    }

    @ViewBuilder
    private func responseBodyView(_ response: ResponseData) -> some View {
        switch response.contentType {
        case .json:
            jsonBodyView(response)
        case .image:
            imageBodyView(response)
        case .html, .xml:
            textBodyView(response)
        default:
            if response.bodyString != nil {
                textBodyView(response)
            } else if let body = response.body {
                BinaryBodyView(data: body)
            }
        }
    }

    private func jsonBodyView(_ response: ResponseData) -> some View {
        Group {
            if let bodyString = response.bodyString {
                let displayString = showFormattedBody
                    ? (JSONFormatter.format(bodyString) ?? bodyString)
                    : bodyString

                NetCheckerTrafficUI_JSONSyntaxView(json: displayString, maxLines: 50)
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
            }
        }
    }

    private func imageBodyView(_ response: ResponseData) -> some View {
        Group {
            if let body = response.body {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: body) {
                    VStack(spacing: 8) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(8)

                        HStack {
                            Text("\(Int(uiImage.size.width))×\(Int(uiImage.size.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            NetCheckerTrafficUI_SizeIndicator(bytes: Int64(body.count))
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
                }
                #endif
            }
        }
    }

    private func textBodyView(_ response: ResponseData) -> some View {
        Group {
            if let bodyString = response.bodyString {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(bodyString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Redirects Section

    private var redirectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Redirects (\(record.redirects.count))")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(record.redirects) { hop in
                    HStack {
                        Text("\(hop.statusCode)")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Text(hop.toURL.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        NetCheckerTrafficUI_CopyButton(text: hop.toURL.absoluteString)
                    }

                    if hop.id != record.redirects.last?.id {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 20)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - State Views

    private var pendingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Waiting for response...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Request Failed")
                .font(.headline)

            if let error = record.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Error Code: \(error.code)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var noResponseView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Response")
                .font(.headline)

            Text("The request was cancelled or no response was received")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    NetCheckerTrafficUI_ResponseDetailView(
        record: TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com/users")!,
                method: .get
            ),
            response: ResponseData(
                statusCode: 200,
                headers: [
                    "Content-Type": "application/json",
                    "Content-Length": "1234",
                    "Cache-Control": "max-age=3600"
                ],
                body: """
                {
                    "users": [
                        {"id": 1, "name": "John"},
                        {"id": 2, "name": "Jane"}
                    ],
                    "total": 2
                }
                """.data(using: .utf8)
            )
        )
    )
}
