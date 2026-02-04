import SwiftUI
import NetCheckerTrafficCore

/// Detail view for request information
public struct NetCheckerTrafficUI_RequestDetailView: View {
    let record: TrafficRecord

    @State private var showRawHeaders = false

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // URL Section
                urlSection

                // Headers Section
                headersSection

                // Query Parameters
                if !queryParameters.isEmpty {
                    querySection
                }

                // Body Section
                if let body = record.request.body, !body.isEmpty {
                    bodySection
                }

                // Cookies Section
                if !record.request.cookies.isEmpty {
                    cookiesSection
                }
            }
            .padding()
        }
    }

    // MARK: - URL Section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("URL")
                    .font(.headline)

                Spacer()

                NetCheckerTrafficUI_CopyButton(text: record.url.absoluteString, label: "Copy")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scheme")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(record.url.scheme ?? "")
                        .font(.system(.caption, design: .monospaced))
                }

                HStack {
                    Text("Host")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(record.host)
                        .font(.system(.caption, design: .monospaced))
                }

                HStack {
                    Text("Path")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)
                    Text(record.path)
                        .font(.system(.caption, design: .monospaced))
                }

                if let port = record.url.port {
                    HStack {
                        Text("Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .leading)
                        Text("\(port)")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - Headers Section

    private var headersSection: some View {
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
                rawHeadersView
            } else {
                NetCheckerTrafficUI_HeadersTableView(
                    headers: record.request.headers,
                    showSearch: record.request.headers.count > 5
                )
            }
        }
    }

    private var rawHeadersView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(record.request.headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
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

    // MARK: - Query Parameters

    private var queryParameters: [URLQueryItem] {
        URLComponents(url: record.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Query Parameters")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(queryParameters, id: \.name) { item in
                    HStack {
                        Text(item.name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)

                        Text("=")
                            .foregroundColor(.secondary)

                        Text(item.value ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)

                        Spacer()

                        NetCheckerTrafficUI_CopyButton(text: item.value ?? "")
                    }
                    .padding(.vertical, 4)

                    if item != queryParameters.last {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    // MARK: - Body Section

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Body")
                    .font(.headline)

                Spacer()

                if let body = record.request.body {
                    NetCheckerTrafficUI_SizeIndicator(bytes: Int64(body.count))
                }

                if let bodyString = record.request.bodyString {
                    NetCheckerTrafficUI_CopyButton(text: bodyString, label: "Copy")
                }
            }

            if let bodyString = record.request.bodyString {
                if record.request.contentType == .json {
                    let formatted = JSONFormatter.format(bodyString) ?? bodyString
                    NetCheckerTrafficUI_JSONSyntaxView(json: formatted, maxLines: 20)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)
                } else {
                    Text(bodyString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)
                }
            } else if let body = record.request.body {
                BinaryBodyView(data: body)
            }
        }
    }

    // MARK: - Cookies Section

    private var cookiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cookies")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(record.request.cookies) { cookie in
                    HStack {
                        Text(cookie.name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)

                        Text("=")
                            .foregroundColor(.secondary)

                        Text(cookie.value)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)

                        Spacer()

                        if cookie.isSecure {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)

                    if cookie.id != record.request.cookies.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }
}

// MARK: - Binary Body View

struct BinaryBodyView: View {
    let data: Data

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.secondary)

                Text("Binary Data")
                    .font(.subheadline)

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Hex preview (first 256 bytes)
            let previewData = data.prefix(256)
            Text(hexDump(previewData))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(8)

            if data.count > 256 {
                Text("... and \(data.count - 256) more bytes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(8)
    }

    private func hexDump(_ data: Data) -> String {
        var result = ""
        let bytesPerLine = 16

        for (index, byte) in data.enumerated() {
            if index % bytesPerLine == 0 {
                if index > 0 {
                    result += "\n"
                }
                result += String(format: "%04X: ", index)
            }
            result += String(format: "%02X ", byte)
        }

        return result
    }
}

#Preview {
    NetCheckerTrafficUI_RequestDetailView(
        record: TrafficRecord(
            request: RequestData(
                url: URL(string: "https://api.example.com/v1/users?page=1&limit=10")!,
                method: .post,
                headers: [
                    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                    "User-Agent": "NetChecker/1.0"
                ],
                body: """
                {
                    "name": "John Doe",
                    "email": "john@example.com"
                }
                """.data(using: .utf8)
            )
        )
    )
}
