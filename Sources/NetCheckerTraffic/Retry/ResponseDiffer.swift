import Foundation

/// Сравнение двух ответов
public struct ResponseDiffer {
    /// Сравнить два ответа
    public static func diff(original: ResponseData?, retry: ResponseData?) -> ResponseDiff {
        var diff = ResponseDiff()

        // Status diff
        if let origStatus = original?.statusCode, let retryStatus = retry?.statusCode {
            if origStatus != retryStatus {
                diff.statusDiff = StatusDiff(
                    original: origStatus,
                    retry: retryStatus
                )
            }
        }

        // Headers diff
        let origHeaders = original?.headers ?? [:]
        let retryHeaders = retry?.headers ?? [:]
        diff.headersDiff = diffHeaders(original: origHeaders, retry: retryHeaders)

        // Body diff (for text content)
        if let origBody = original?.bodyString, let retryBody = retry?.bodyString {
            diff.bodyDiff = diffBodies(original: origBody, retry: retryBody)
        }

        // Size diff
        let origSize = original?.bodySize ?? 0
        let retrySize = retry?.bodySize ?? 0
        if origSize != retrySize {
            diff.sizeDiff = SizeDiff(original: origSize, retry: retrySize)
        }

        return diff
    }

    /// Сравнить два TrafficRecord
    public static func diff(original: TrafficRecord, retry: RetryResult) -> ResponseDiff {
        var diff = diff(original: original.response, retry: retry.response)

        // Duration diff
        diff.durationDiff = DurationDiff(
            original: original.duration,
            retry: retry.duration
        )

        return diff
    }

    // MARK: - Private Methods

    private static func diffHeaders(
        original: [String: String],
        retry: [String: String]
    ) -> [HeaderDiff] {
        var diffs: [HeaderDiff] = []

        // Check for modified and removed
        for (key, origValue) in original {
            if let retryValue = retry[key] {
                if origValue != retryValue {
                    diffs.append(HeaderDiff(
                        key: key,
                        type: .modified,
                        originalValue: origValue,
                        retryValue: retryValue
                    ))
                }
            } else {
                diffs.append(HeaderDiff(
                    key: key,
                    type: .removed,
                    originalValue: origValue,
                    retryValue: nil
                ))
            }
        }

        // Check for added
        for (key, retryValue) in retry {
            if original[key] == nil {
                diffs.append(HeaderDiff(
                    key: key,
                    type: .added,
                    originalValue: nil,
                    retryValue: retryValue
                ))
            }
        }

        return diffs.sorted { $0.key < $1.key }
    }

    private static func diffBodies(original: String, retry: String) -> BodyDiff {
        if original == retry {
            return BodyDiff(type: .identical)
        }

        // Try JSON diff
        if let origData = original.data(using: .utf8),
           let retryData = retry.data(using: .utf8),
           let origJSON = try? JSONSerialization.jsonObject(with: origData) as? [String: Any],
           let retryJSON = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any] {
            let jsonDiffs = diffJSON(original: origJSON, retry: retryJSON, path: "")
            return BodyDiff(type: .json, jsonDiffs: jsonDiffs)
        }

        // Line-by-line diff
        let origLines = original.components(separatedBy: "\n")
        let retryLines = retry.components(separatedBy: "\n")
        let lineDiffs = diffLines(original: origLines, retry: retryLines)

        return BodyDiff(type: .text, lineDiffs: lineDiffs)
    }

    private static func diffJSON(
        original: [String: Any],
        retry: [String: Any],
        path: String
    ) -> [JSONDiff] {
        var diffs: [JSONDiff] = []

        // Check modified and removed
        for (key, origValue) in original {
            let currentPath = path.isEmpty ? key : "\(path).\(key)"

            if let retryValue = retry[key] {
                if !valuesEqual(origValue, retryValue) {
                    // Check nested objects
                    if let origDict = origValue as? [String: Any],
                       let retryDict = retryValue as? [String: Any] {
                        diffs.append(contentsOf: diffJSON(original: origDict, retry: retryDict, path: currentPath))
                    } else {
                        diffs.append(JSONDiff(
                            path: currentPath,
                            type: .modified,
                            originalValue: String(describing: origValue),
                            retryValue: String(describing: retryValue)
                        ))
                    }
                }
            } else {
                diffs.append(JSONDiff(
                    path: currentPath,
                    type: .removed,
                    originalValue: String(describing: origValue),
                    retryValue: nil
                ))
            }
        }

        // Check added
        for (key, retryValue) in retry {
            let currentPath = path.isEmpty ? key : "\(path).\(key)"

            if original[key] == nil {
                diffs.append(JSONDiff(
                    path: currentPath,
                    type: .added,
                    originalValue: nil,
                    retryValue: String(describing: retryValue)
                ))
            }
        }

        return diffs
    }

    private static func valuesEqual(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (a as String, b as String): return a == b
        case let (a as Int, b as Int): return a == b
        case let (a as Double, b as Double): return a == b
        case let (a as Bool, b as Bool): return a == b
        case let (a as [Any], b as [Any]): return a.count == b.count
        case (is NSNull, is NSNull): return true
        default: return false
        }
    }

    private static func diffLines(original: [String], retry: [String]) -> [LineDiff] {
        var diffs: [LineDiff] = []

        let maxLines = max(original.count, retry.count)

        for i in 0..<maxLines {
            let origLine = i < original.count ? original[i] : nil
            let retryLine = i < retry.count ? retry[i] : nil

            if origLine != retryLine {
                if origLine == nil {
                    diffs.append(LineDiff(lineNumber: i + 1, type: .added, line: retryLine!))
                } else if retryLine == nil {
                    diffs.append(LineDiff(lineNumber: i + 1, type: .removed, line: origLine!))
                } else {
                    diffs.append(LineDiff(lineNumber: i + 1, type: .modified, originalLine: origLine, retryLine: retryLine))
                }
            }
        }

        return diffs
    }
}

// MARK: - Diff Models

public struct ResponseDiff: Sendable {
    public var statusDiff: StatusDiff?
    public var headersDiff: [HeaderDiff] = []
    public var bodyDiff: BodyDiff?
    public var sizeDiff: SizeDiff?
    public var durationDiff: DurationDiff?

    public var hasChanges: Bool {
        statusDiff != nil || !headersDiff.isEmpty || bodyDiff?.type != .identical || sizeDiff != nil
    }

    public var summary: String {
        var parts: [String] = []

        if let status = statusDiff {
            parts.append("Status: \(status.original) → \(status.retry)")
        }

        if !headersDiff.isEmpty {
            parts.append("Headers: \(headersDiff.count) changes")
        }

        if let body = bodyDiff, body.type != .identical {
            parts.append("Body changed")
        }

        if let size = sizeDiff {
            let change = size.retry - size.original
            let sign = change >= 0 ? "+" : ""
            parts.append("Size: \(sign)\(ByteCountFormatter.string(fromByteCount: change, countStyle: .file))")
        }

        if let duration = durationDiff {
            let change = duration.retry - duration.original
            let percent = duration.original > 0 ? (change / duration.original) * 100 : 0
            let sign = percent >= 0 ? "+" : ""
            parts.append("Time: \(sign)\(String(format: "%.0f", percent))%")
        }

        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

public struct StatusDiff: Sendable {
    public let original: Int
    public let retry: Int

    public var improved: Bool {
        retry.isSuccessStatusCode && !original.isSuccessStatusCode
    }

    public var worsened: Bool {
        !retry.isSuccessStatusCode && original.isSuccessStatusCode
    }
}

public struct HeaderDiff: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let type: DiffType
    public let originalValue: String?
    public let retryValue: String?
}

public struct BodyDiff: Sendable {
    public let type: BodyDiffType
    public var jsonDiffs: [JSONDiff] = []
    public var lineDiffs: [LineDiff] = []
}

public enum BodyDiffType: Sendable {
    case identical
    case json
    case text
    case binary
}

public struct JSONDiff: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let type: DiffType
    public let originalValue: String?
    public let retryValue: String?
}

public struct LineDiff: Sendable, Identifiable {
    public var id: Int { lineNumber }
    public let lineNumber: Int
    public let type: DiffType
    public var line: String?
    public var originalLine: String?
    public var retryLine: String?
}

public struct SizeDiff: Sendable {
    public let original: Int64
    public let retry: Int64

    public var change: Int64 { retry - original }
    public var percentChange: Double {
        original > 0 ? Double(change) / Double(original) * 100 : 0
    }
}

public struct DurationDiff: Sendable {
    public let original: TimeInterval
    public let retry: TimeInterval

    public var change: TimeInterval { retry - original }
    public var percentChange: Double {
        original > 0 ? change / original * 100 : 0
    }
    public var improved: Bool { retry < original }
}

public enum DiffType: String, Sendable {
    case added
    case removed
    case modified

    public var symbol: String {
        switch self {
        case .added: return "+"
        case .removed: return "-"
        case .modified: return "~"
        }
    }

    public var colorName: String {
        switch self {
        case .added: return "green"
        case .removed: return "red"
        case .modified: return "yellow"
        }
    }
}
