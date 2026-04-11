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

        // Найти самый верхний VC (чтобы не упасть если уже есть presented)
        var topVC = rootVC
        while let presented = topVC.presentedViewController { topVC = presented }

        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        }

        topVC.present(activityVC, animated: true)
        #endif
    }
}

// MARK: - Export Menu

public struct ExportMenuButton: View {
    let record: TrafficRecord

    @State private var copiedLabel: String?
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    public init(record: TrafficRecord) {
        self.record = record
    }

    public var body: some View {
        Menu {
            // Share (система)
            Button {
                let text = buildFullAPI()
                shareItems = [text]
                showShareSheet = true
            } label: {
                Label("Share Full API", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                copyWithFeedback(CURLFormatter.format(record: record), label: "cURL")
            } label: {
                Label(copiedLabel == "cURL" ? "Copied!" : "Copy as cURL", systemImage: copiedLabel == "cURL" ? "checkmark" : "terminal")
            }

            Button {
                copyWithFeedback(record.url.absoluteString, label: "URL")
            } label: {
                Label(copiedLabel == "URL" ? "Copied!" : "Copy URL", systemImage: copiedLabel == "URL" ? "checkmark" : "link")
            }

            Button {
                copyWithFeedback(buildFullAPI(), label: "Full")
            } label: {
                Label(copiedLabel == "Full" ? "Copied!" : "Copy Full API", systemImage: copiedLabel == "Full" ? "checkmark" : "doc.on.doc")
            }

            if let harData = HARFormatter.format(records: [record]),
               let har = String(data: harData, encoding: .utf8) {
                Button {
                    copyWithFeedback(har, label: "HAR")
                } label: {
                    Label(copiedLabel == "HAR" ? "Copied!" : "Copy as HAR", systemImage: copiedLabel == "HAR" ? "checkmark" : "doc.text")
                }
            }

            if let body = record.request.bodyString {
                Divider()
                Button {
                    copyWithFeedback(body, label: "ReqBody")
                } label: {
                    Label(copiedLabel == "ReqBody" ? "Copied!" : "Copy Request Body", systemImage: copiedLabel == "ReqBody" ? "checkmark" : "doc")
                }
            }

            if let body = record.response?.bodyString {
                Button {
                    copyWithFeedback(body, label: "ResBody")
                } label: {
                    Label(copiedLabel == "ResBody" ? "Copied!" : "Copy Response Body", systemImage: copiedLabel == "ResBody" ? "checkmark" : "doc.fill")
                }
            }
        } label: {
            if let copiedLabel, !copiedLabel.isEmpty {
                Label("Copied!", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerRepresentable(items: shareItems, excludedTypes: nil)
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    private func copyWithFeedback(_ text: String, label: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation { copiedLabel = label }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copiedLabel = nil }
        }
    }

    private func shareURL() {
        #if canImport(UIKit)
        UIPasteboard.general.url = record.url
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.url.absoluteString, forType: .string)
        #endif
    }

    private func buildFullAPI() -> String { copyFullAPI() }


    @discardableResult
    private func copyFullAPI() -> String {
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

        return output
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
