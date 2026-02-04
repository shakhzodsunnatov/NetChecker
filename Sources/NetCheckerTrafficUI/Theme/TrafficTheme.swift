import SwiftUI
import NetCheckerTrafficCore

/// Theme for traffic UI components
public struct TrafficTheme {
    // MARK: - Status Code Colors

    /// Color for HTTP status code
    public static func statusColor(for code: Int) -> Color {
        switch code {
        case 100..<200: return .gray
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }

    /// Background color for HTTP status code badge
    public static func statusBackgroundColor(for code: Int) -> Color {
        statusColor(for: code).opacity(0.15)
    }

    // MARK: - Method Colors

    /// Color for HTTP method
    public static func methodColor(for method: HTTPMethod) -> Color {
        switch method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .purple
        case .delete: return .red
        case .head: return .gray
        case .options: return .teal
        case .trace: return .indigo
        case .connect: return .mint
        }
    }

    /// Background color for HTTP method badge
    public static func methodBackgroundColor(for method: HTTPMethod) -> Color {
        methodColor(for: method).opacity(0.15)
    }

    // MARK: - Content Type Colors

    /// Color for content type
    public static func contentTypeColor(for contentType: ContentType) -> Color {
        switch contentType {
        case .json: return .orange
        case .xml: return .purple
        case .html: return .blue
        case .formUrlEncoded: return .green
        case .multipartFormData: return .teal
        case .plainText: return .gray
        case .image: return .pink
        case .pdf: return .red
        case .protobuf: return .mint
        case .msgpack: return .cyan
        case .graphql: return .purple
        case .binary: return .gray
        case .unknown: return .gray
        }
    }

    // MARK: - State Colors

    /// Color for traffic record state
    public static func stateColor(for state: TrafficRecordState) -> Color {
        switch state {
        case .pending: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .mocked: return .purple
        }
    }

    // MARK: - Timing Colors

    public static let dnsColor = Color.blue
    public static let tcpColor = Color.orange
    public static let tlsColor = Color.purple
    public static let requestColor = Color.green
    public static let responseColor = Color.cyan
    public static let downloadColor = Color.indigo

    // MARK: - SSL Colors

    public static let sslSecureColor = Color.green
    public static let sslWarningColor = Color.orange
    public static let sslErrorColor = Color.red

    // MARK: - Environment Colors

    public static let productionColor = Color.red
    public static let stagingColor = Color.orange
    public static let developmentColor = Color.blue
    public static let localColor = Color.green

    // MARK: - Diff Colors

    public static let addedColor = Color.green
    public static let removedColor = Color.red
    public static let modifiedColor = Color.yellow

    // MARK: - Typography

    public static let monospacedFont = Font.system(.body, design: .monospaced)
    public static let monospacedSmallFont = Font.system(.caption, design: .monospaced)

    // MARK: - Spacing

    public static let itemSpacing: CGFloat = 8
    public static let sectionSpacing: CGFloat = 16
    public static let cornerRadius: CGFloat = 8
    public static let badgeCornerRadius: CGFloat = 4
}

// MARK: - Color Extensions

extension Color {
    /// Create color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct BadgeModifier: ViewModifier {
    let backgroundColor: Color
    let foregroundColor: Color

    func body(content: Content) -> some View {
        content
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(TrafficTheme.badgeCornerRadius)
    }
}

extension View {
    func badgeStyle(backgroundColor: Color, foregroundColor: Color) -> some View {
        modifier(BadgeModifier(backgroundColor: backgroundColor, foregroundColor: foregroundColor))
    }
}
