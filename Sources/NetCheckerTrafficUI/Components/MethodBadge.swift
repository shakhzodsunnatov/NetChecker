import SwiftUI
import NetCheckerTrafficCore

/// Badge displaying HTTP method with color
public struct NetCheckerTrafficUI_MethodBadge: View {
    let method: HTTPMethod

    public init(method: HTTPMethod) {
        self.method = method
    }

    public init(methodString: String) {
        self.method = HTTPMethod(rawValue: methodString.uppercased()) ?? .get
    }

    public var body: some View {
        Text(method.rawValue)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TrafficTheme.methodBackgroundColor(for: method))
            .foregroundColor(TrafficTheme.methodColor(for: method))
            .cornerRadius(TrafficTheme.badgeCornerRadius)
    }
}

/// Compact method badge (just initials)
public struct MethodBadgeCompact: View {
    let method: HTTPMethod

    public init(method: HTTPMethod) {
        self.method = method
    }

    public var body: some View {
        Text(shortName)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .frame(width: 24)
            .padding(.vertical, 2)
            .background(TrafficTheme.methodBackgroundColor(for: method))
            .foregroundColor(TrafficTheme.methodColor(for: method))
            .cornerRadius(TrafficTheme.badgeCornerRadius)
    }

    private var shortName: String {
        switch method {
        case .get: return "G"
        case .post: return "P"
        case .put: return "U"
        case .patch: return "A"
        case .delete: return "D"
        case .head: return "H"
        case .options: return "O"
        case .trace: return "T"
        case .connect: return "C"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(HTTPMethod.allCases, id: \.rawValue) { method in
            HStack {
                NetCheckerTrafficUI_MethodBadge(method: method)
                MethodBadgeCompact(method: method)
            }
        }
    }
    .padding()
}
