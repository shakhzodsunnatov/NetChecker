import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Share sheet wrapper for UIActivityViewController
public struct NetCheckerTrafficUI_ShareSheet: View {
    let items: [Any]
    let excludedTypes: [Any]?

    @State private var isPresented = false

    public init(items: [Any], excludedTypes: [Any]? = nil) {
        self.items = items
        self.excludedTypes = excludedTypes
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        #if os(iOS)
        .sheet(isPresented: $isPresented) {
            ActivityViewControllerRepresentable(
                items: items,
                excludedTypes: excludedTypes as? [UIActivity.ActivityType]
            )
        }
        #endif
    }
}

#if os(iOS)
struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let items: [Any]
    let excludedTypes: [UIActivity.ActivityType]?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Share Button

public struct ShareButton: View {
    let title: String
    let items: [Any]

    public init(title: String = "Share", items: [Any]) {
        self.title = title
        self.items = items
    }

    public var body: some View {
        Button {
            share()
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
        }
    }

    private func share() {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
        }

        rootVC.present(activityVC, animated: true)
        #endif
    }
}

// MARK: - Export Menu

public struct ExportMenuButton: View {
    let record: TrafficRecord

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        Menu {
            Button {
                copyFullAPI()
            } label: {
                Label("Copy Full API", systemImage: "doc.on.doc")
            }

            Divider()

            Button {
                shareText(CURLFormatter.format(record: record))
            } label: {
                Label("Copy as cURL", systemImage: "terminal")
            }

            Button {
                if let harData = HARFormatter.format(records: [record]),
                   let har = String(data: harData, encoding: .utf8) {
                    shareText(har)
                }
            } label: {
                Label("Export as HAR", systemImage: "doc.text")
            }

            Divider()

            Button {
                shareURL()
            } label: {
                Label("Copy URL", systemImage: "link")
            }

            if let body = record.request.bodyString {
                Button {
                    shareText(body)
                } label: {
                    Label("Copy Request Body", systemImage: "doc")
                }
            }

            if let body = record.response?.bodyString {
                Button {
                    shareText(body)
                } label: {
                    Label("Copy Response Body", systemImage: "doc.fill")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }

    private func shareText(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func shareURL() {
        #if canImport(UIKit)
        UIPasteboard.general.url = record.url
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.url.absoluteString, forType: .string)
        #endif
    }

    private func copyFullAPI() {
        var output = ""

        // Request Section
        output += "══════ REQUEST ══════\n\n"

        // Method & URL
        output += "[\(record.method.rawValue)] \(record.url.absoluteString)\n\n"

        // Timestamp & Duration
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        output += "Time: \(dateFormatter.string(from: record.timestamp)) | \(record.formattedDuration)\n\n"

        // Request Headers
        if !record.request.headers.isEmpty {
            output += "── Headers ──\n"
            for (key, value) in record.request.headers.sorted(by: { $0.key < $1.key }) {
                output += "\(key): \(value)\n"
            }
            output += "\n"
        }

        // Request Body
        if let requestBody = record.request.bodyString, !requestBody.isEmpty {
            output += "── Body ──\n"
            output += formatJSONIfPossible(requestBody)
            output += "\n\n"
        }

        // Response Section
        output += "══════ RESPONSE ══════\n\n"

        if let response = record.response {
            // Status & Size
            output += "Status: \(response.statusCode)"
            if let bodySize = response.body?.count, bodySize > 0 {
                output += " | \(formatBytes(bodySize))"
            }
            output += "\n\n"

            // Response Headers
            if !response.headers.isEmpty {
                output += "── Headers ──\n"
                for (key, value) in response.headers.sorted(by: { $0.key < $1.key }) {
                    output += "\(key): \(value)\n"
                }
                output += "\n"
            }

            // Response Body
            if let responseBody = response.bodyString, !responseBody.isEmpty {
                output += "── Body ──\n"
                output += formatJSONIfPossible(responseBody)
                output += "\n"
            }
        } else {
            switch record.state {
            case .pending:
                output += "Status: Pending...\n"
            case .failed(let error):
                output += "Status: Failed\nError: \(error)\n"
            case .mocked:
                output += "Status: Mocked\n"
            default:
                output += "Status: No response\n"
            }
        }

        shareText(output)
    }

    private func formatJSONIfPossible(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return text
        }
        return prettyString
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.2f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

import NetCheckerTrafficCore

#Preview {
    VStack(spacing: 20) {
        NetCheckerTrafficUI_ShareSheet(items: ["Hello World"])
        ShareButton(items: ["Share this text"])
    }
    .padding()
}
