import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Button for copying text to clipboard
public struct NetCheckerTrafficUI_CopyButton: View {
    let text: String
    let label: String?
    let showConfirmation: Bool

    @State private var copied = false

    public init(text: String, label: String? = nil, showConfirmation: Bool = true) {
        self.text = text
        self.label = label
        self.showConfirmation = showConfirmation
    }

    public var body: some View {
        Button {
            copyToClipboard(text)
            if showConfirmation {
                withAnimation {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        copied = false
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                if let label = label {
                    Text(copied ? "Copied!" : label)
                        .font(.caption)
                }
            }
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.plain)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Copy button with menu for multiple formats
public struct CopyMenuButton: View {
    let items: [(label: String, value: String)]

    public init(items: [(label: String, value: String)]) {
        self.items = items
    }

    public var body: some View {
        Menu {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    copyToClipboard(items[index].value)
                } label: {
                    Label(items[index].label, systemImage: "doc.on.doc")
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption)
        }
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Quick copy row for key-value pairs
public struct CopyableRow: View {
    let label: String
    let value: String
    let monospaced: Bool

    public init(label: String, value: String, monospaced: Bool = true) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    public var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .lineLimit(1)
                .truncationMode(.middle)

            NetCheckerTrafficUI_CopyButton(text: value)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        NetCheckerTrafficUI_CopyButton(text: "Hello World")
        NetCheckerTrafficUI_CopyButton(text: "Hello World", label: "Copy")
        CopyMenuButton(items: [
            ("Copy URL", "https://example.com"),
            ("Copy cURL", "curl https://example.com"),
            ("Copy JSON", "{}")
        ])
        CopyableRow(label: "URL", value: "https://api.example.com/v1/users")
    }
    .padding()
}
