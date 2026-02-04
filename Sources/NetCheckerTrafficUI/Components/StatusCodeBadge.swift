import SwiftUI
import NetCheckerTrafficCore

/// Badge displaying HTTP status code with color
public struct NetCheckerTrafficUI_StatusCodeBadge: View {
    let statusCode: Int

    public init(statusCode: Int) {
        self.statusCode = statusCode
    }

    public var body: some View {
        Text("\(statusCode)")
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TrafficTheme.statusBackgroundColor(for: statusCode))
            .foregroundColor(TrafficTheme.statusColor(for: statusCode))
            .cornerRadius(TrafficTheme.badgeCornerRadius)
    }
}

/// Extended status badge with description
public struct StatusCodeBadgeExtended: View {
    let statusCode: Int
    let showDescription: Bool

    public init(statusCode: Int, showDescription: Bool = true) {
        self.statusCode = statusCode
        self.showDescription = showDescription
    }

    public var body: some View {
        HStack(spacing: 4) {
            NetCheckerTrafficUI_StatusCodeBadge(statusCode: statusCode)

            if showDescription {
                Text(statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusDescription: String {
        switch statusCode {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return ""
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach([200, 201, 301, 400, 401, 404, 500, 503], id: \.self) { code in
            StatusCodeBadgeExtended(statusCode: code)
        }
    }
    .padding()
}
