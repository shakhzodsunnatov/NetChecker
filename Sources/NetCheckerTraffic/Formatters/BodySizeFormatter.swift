import Foundation

/// Форматирование размера данных
public struct BodySizeFormatter {
    /// Форматировать размер в человекочитаемый вид
    public static func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Форматировать размер с точностью
    public static func format(bytes: Int64, precision: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    /// Форматировать размер компактно
    public static func formatCompact(bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else {
            return String(format: "%.1f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
    }

    /// Форматировать upload/download
    public static func formatTransfer(sent: Int64, received: Int64) -> String {
        "↑ \(format(bytes: sent)) ↓ \(format(bytes: received))"
    }
}
