import SwiftUI
#if canImport(UIKit)
import UIKit
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
        #endif
    }

    private func shareURL() {
        #if canImport(UIKit)
        UIPasteboard.general.url = record.url
        #endif
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
