import Foundation

/// URL rewriting utilities for environment switching
public struct URLRewriter {
    /// Rewrite URL according to rule
    public static func rewrite(
        url: URL,
        from sourcePattern: String,
        to targetURL: URL
    ) -> URL? {
        guard matches(url: url, pattern: sourcePattern) else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // Apply target URL components
        components?.scheme = targetURL.scheme
        components?.host = targetURL.host
        components?.port = targetURL.port

        // If target has a path prefix, prepend it
        if !targetURL.path.isEmpty && targetURL.path != "/" {
            let originalPath = components?.path ?? ""
            components?.path = targetURL.path + originalPath
        }

        return components?.url
    }

    /// Rewrite only the host
    public static func rewriteHost(url: URL, to newHost: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = newHost
        return components?.url
    }

    /// Rewrite host and port
    public static func rewriteHostAndPort(url: URL, to newHost: String, port: Int?) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = newHost
        components?.port = port
        return components?.url
    }

    /// Rewrite scheme
    public static func rewriteScheme(url: URL, to newScheme: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = newScheme
        return components?.url
    }

    /// Rewrite path prefix
    public static func rewritePath(url: URL, from oldPath: String, to newPath: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        guard let path = components?.path else { return nil }

        if path.hasPrefix(oldPath) {
            components?.path = newPath + path.dropFirst(oldPath.count)
        }

        return components?.url
    }

    /// Check if URL matches pattern
    public static func matches(url: URL, pattern: String) -> Bool {
        guard let host = url.host else { return false }

        let patternLower = pattern.lowercased()
        let hostLower = host.lowercased()

        // Exact match
        if patternLower == hostLower {
            return true
        }

        // Wildcard at start (*.example.com)
        if patternLower.hasPrefix("*") {
            let suffix = patternLower.dropFirst()
            return hostLower.hasSuffix(suffix)
        }

        // Wildcard at end (example.*)
        if patternLower.hasSuffix("*") {
            let prefix = patternLower.dropLast()
            return hostLower.hasPrefix(prefix)
        }

        // Regex pattern with wildcards
        if patternLower.contains("*") {
            let regexPattern = patternLower
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "*", with: ".*")

            if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: .caseInsensitive) {
                let range = NSRange(hostLower.startIndex..., in: hostLower)
                return regex.firstMatch(in: hostLower, options: [], range: range) != nil
            }
        }

        return false
    }

    /// Build URL from components
    public static func buildURL(
        scheme: String = "https",
        host: String,
        port: Int? = nil,
        path: String = "/",
        queryItems: [URLQueryItem]? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    /// Apply environment headers to request
    public static func applyHeaders(
        _ environmentHeaders: [String: String],
        to request: inout URLRequest,
        overwrite: Bool = true
    ) {
        for (key, value) in environmentHeaders {
            if overwrite {
                request.setValue(value, forHTTPHeaderField: key)
            } else {
                // Only set if not already present
                if request.value(forHTTPHeaderField: key) == nil {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
    }

    /// Apply environment headers to mutable request
    public static func applyHeaders(
        _ environmentHeaders: [String: String],
        to request: NSMutableURLRequest,
        overwrite: Bool = true
    ) {
        for (key, value) in environmentHeaders {
            if overwrite {
                request.setValue(value, forHTTPHeaderField: key)
            } else {
                // Only set if not already present
                if request.value(forHTTPHeaderField: key) == nil {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
    }
}
