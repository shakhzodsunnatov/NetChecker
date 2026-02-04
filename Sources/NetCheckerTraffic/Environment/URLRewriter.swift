import Foundation

/// Переписывание URL для переключения окружений
public struct URLRewriter {
    /// Переписать URL согласно правилу
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

    /// Переписать только хост
    public static func rewriteHost(url: URL, to newHost: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = newHost
        return components?.url
    }

    /// Переписать хост и порт
    public static func rewriteHostAndPort(url: URL, to newHost: String, port: Int?) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = newHost
        components?.port = port
        return components?.url
    }

    /// Переписать схему
    public static func rewriteScheme(url: URL, to newScheme: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = newScheme
        return components?.url
    }

    /// Переписать путь
    public static func rewritePath(url: URL, from oldPath: String, to newPath: String) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        guard let path = components?.path else { return nil }

        if path.hasPrefix(oldPath) {
            components?.path = newPath + path.dropFirst(oldPath.count)
        }

        return components?.url
    }

    /// Проверить соответствие URL паттерну
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

        // Regex pattern
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

    /// Построить URL из компонентов
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
}
