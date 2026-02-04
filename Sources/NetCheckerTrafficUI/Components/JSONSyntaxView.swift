import SwiftUI
import NetCheckerTrafficCore

/// View displaying JSON with syntax highlighting
public struct NetCheckerTrafficUI_JSONSyntaxView: View {
    let json: String
    let maxLines: Int?

    @State private var isExpanded = false

    public init(json: String, maxLines: Int? = nil) {
        self.json = json
        self.maxLines = maxLines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(attributedJSON)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(isExpanded ? nil : maxLines)
                    .textSelection(.enabled)
            }

            if let maxLines = maxLines, lineCount > maxLines && !isExpanded {
                Button {
                    withAnimation {
                        isExpanded = true
                    }
                } label: {
                    HStack {
                        Text("Show more (\(lineCount - maxLines) more lines)")
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 8)
            }
        }
    }

    private var lineCount: Int {
        json.components(separatedBy: "\n").count
    }

    private var attributedJSON: AttributedString {
        var attributed = AttributedString(json)

        // Colorize strings (quoted values)
        let stringPattern = #""[^"\\]*(?:\\.[^"\\]*)*""#
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            let nsRange = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: nsRange) {
                if let range = Range(match.range, in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .orange
                }
            }
        }

        // Colorize numbers
        let numberPattern = #"(?<=[\s,:\[])(-?\d+\.?\d*(?:[eE][+-]?\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            let nsRange = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: nsRange) {
                if let range = Range(match.range, in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .cyan
                }
            }
        }

        // Colorize keywords
        let keywordPattern = #"\b(true|false|null)\b"#
        if let regex = try? NSRegularExpression(pattern: keywordPattern) {
            let nsRange = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: nsRange) {
                if let range = Range(match.range, in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .purple
                }
            }
        }

        // Colorize keys
        let keyPattern = #""([^"]+)"\s*:"#
        if let regex = try? NSRegularExpression(pattern: keyPattern) {
            let nsRange = NSRange(json.startIndex..., in: json)
            for match in regex.matches(in: json, range: nsRange) {
                if let range = Range(match.range(at: 1), in: json),
                   let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .blue
                }
            }
        }

        return attributed
    }
}

/// Collapsible JSON view with copy button
public struct CollapsibleJSONView: View {
    let title: String
    let json: String

    @State private var isExpanded = true

    public init(title: String, json: String) {
        self.title = title
        self.json = json
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text(title)
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                NetCheckerTrafficUI_CopyButton(text: json)
            }

            if isExpanded {
                NetCheckerTrafficUI_JSONSyntaxView(json: json)
                    .padding(8)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(8)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            NetCheckerTrafficUI_JSONSyntaxView(json: """
            {
                "name": "John Doe",
                "age": 30,
                "isActive": true,
                "balance": 1234.56,
                "email": null,
                "tags": ["swift", "ios"]
            }
            """)
            .padding()
        }
    }
}
