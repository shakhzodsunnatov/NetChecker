import SwiftUI
import NetCheckerTrafficCore

/// Indicator for response/request body size
public struct NetCheckerTrafficUI_SizeIndicator: View {
    let bytes: Int64
    let showIcon: Bool
    let style: SizeIndicatorStyle

    public enum SizeIndicatorStyle {
        case compact
        case full
        case badge
    }

    public init(bytes: Int64, showIcon: Bool = true, style: SizeIndicatorStyle = .compact) {
        self.bytes = bytes
        self.showIcon = showIcon
        self.style = style
    }

    public var body: some View {
        switch style {
        case .compact:
            compactView
        case .full:
            fullView
        case .badge:
            badgeView
        }
    }

    private var compactView: some View {
        HStack(spacing: 4) {
            if showIcon {
                Image(systemName: "doc")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var fullView: some View {
        HStack(spacing: 8) {
            Image(systemName: sizeIcon)
                .font(.title3)
                .foregroundColor(sizeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedSize)
                    .font(.headline)
                Text(exactSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var badgeView: some View {
        Text(formattedSize)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(sizeColor.opacity(0.15))
            .foregroundColor(sizeColor)
            .cornerRadius(TrafficTheme.badgeCornerRadius)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var exactSize: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)") bytes"
    }

    private var sizeIcon: String {
        switch bytes {
        case 0: return "doc"
        case 1..<1024: return "doc.text"
        case 1024..<1024 * 100: return "doc.text.fill"
        case 1024 * 100..<1024 * 1024: return "doc.richtext"
        default: return "doc.richtext.fill"
        }
    }

    private var sizeColor: Color {
        switch bytes {
        case 0: return .gray
        case 1..<1024: return .green
        case 1024..<1024 * 100: return .blue
        case 1024 * 100..<1024 * 1024: return .orange
        default: return .red
        }
    }
}

// MARK: - Size Comparison

public struct SizeComparisonView: View {
    let originalSize: Int64
    let newSize: Int64

    public init(originalSize: Int64, newSize: Int64) {
        self.originalSize = originalSize
        self.newSize = newSize
    }

    public var body: some View {
        HStack(spacing: 4) {
            NetCheckerTrafficUI_SizeIndicator(bytes: originalSize, showIcon: false)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)

            NetCheckerTrafficUI_SizeIndicator(bytes: newSize, showIcon: false)

            if originalSize != newSize {
                Text(changeText)
                    .font(.caption)
                    .foregroundColor(changeColor)
            }
        }
    }

    private var change: Int64 {
        newSize - originalSize
    }

    private var changePercent: Double {
        guard originalSize > 0 else { return 0 }
        return Double(change) / Double(originalSize) * 100
    }

    private var changeText: String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f", changePercent))%"
    }

    private var changeColor: Color {
        if change > 0 {
            return .red
        } else if change < 0 {
            return .green
        }
        return .secondary
    }
}

#Preview {
    VStack(spacing: 20) {
        Group {
            NetCheckerTrafficUI_SizeIndicator(bytes: 0)
            NetCheckerTrafficUI_SizeIndicator(bytes: 512)
            NetCheckerTrafficUI_SizeIndicator(bytes: 1024 * 50)
            NetCheckerTrafficUI_SizeIndicator(bytes: 1024 * 500)
            NetCheckerTrafficUI_SizeIndicator(bytes: 1024 * 1024 * 5)
        }

        Divider()

        Group {
            NetCheckerTrafficUI_SizeIndicator(bytes: 1024 * 50, style: .full)
            NetCheckerTrafficUI_SizeIndicator(bytes: 1024 * 50, style: .badge)
        }

        Divider()

        SizeComparisonView(originalSize: 1024 * 100, newSize: 1024 * 80)
        SizeComparisonView(originalSize: 1024 * 100, newSize: 1024 * 150)
    }
    .padding()
}
