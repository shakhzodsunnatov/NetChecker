import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Экспорт записей трафика
public struct TrafficExporter {
    /// Экспортировать записи в выбранном формате
    public static func export(
        records: [TrafficRecord],
        format: ExportFormat,
        redactSensitive: Bool = true
    ) -> ExportResult? {
        let data: Data?
        let filename: String

        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = try? encoder.encode(records)
            filename = "traffic_export_\(timestamp()).json"

        case .har:
            data = HARFormatter.format(records: records)
            filename = "traffic_export_\(timestamp()).har"

        case .curl:
            let curls = records.map { CURLFormatter.format(record: $0, redactSensitive: redactSensitive) }
            data = curls.joined(separator: "\n\n# ---\n\n").data(using: .utf8)
            filename = "traffic_export_\(timestamp()).sh"
        }

        guard let exportData = data else { return nil }

        return ExportResult(
            data: exportData,
            filename: filename,
            mimeType: format.mimeType
        )
    }

    /// Экспортировать одну запись
    public static func export(
        record: TrafficRecord,
        format: ExportFormat,
        redactSensitive: Bool = true
    ) -> ExportResult? {
        export(records: [record], format: format, redactSensitive: redactSensitive)
    }

    /// Создать текст для Share
    public static func shareText(for record: TrafficRecord) -> String {
        var text = """
        \(record.method.rawValue) \(record.url.absoluteString)

        """

        if let status = record.statusCode {
            text += "Status: \(status) \(record.response?.statusMessage ?? "")\n"
        }

        text += "Duration: \(record.formattedDuration)\n"
        text += "Size: \(record.formattedResponseSize)\n"

        if record.isError {
            text += "\nError: \(record.error?.localizedDescription ?? "Unknown error")\n"
        }

        return text
    }

    /// Создать отчет о сессии
    public static func sessionReport(records: [TrafficRecord]) -> String {
        let stats = TrafficStatistics(from: records)

        var report = """
        # NetChecker Traffic Report
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        ## Summary
        - Total Requests: \(stats.totalRequests)
        - Successful: \(stats.successfulRequests) (\(String(format: "%.1f", stats.successRate))%)
        - Failed: \(stats.failedRequests)
        - Pending: \(stats.pendingRequests)

        ## Performance
        - Average Response Time: \(stats.formattedAvgTime)
        - Median Response Time: \(stats.formattedMedianTime)
        - Data Received: \(stats.formattedBytesReceived)
        - Data Sent: \(stats.formattedBytesSent)

        ## Requests by Host
        """

        for (host, count) in stats.requestsByHost.sorted(by: { $0.value > $1.value }) {
            report += "\n- \(host): \(count) requests"
        }

        report += "\n\n## Requests by Status"
        for (status, count) in stats.requestsByStatusCode.sorted(by: { $0.key < $1.key }) {
            report += "\n- \(status): \(count)"
        }

        if !stats.recentErrors.isEmpty {
            report += "\n\n## Recent Errors"
            for error in stats.recentErrors.prefix(10) {
                report += "\n- \(error.shortDescription)"
                if let errorInfo = error.error {
                    report += ": \(errorInfo.localizedDescription)"
                }
            }
        }

        return report
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Export Result

public struct ExportResult: Sendable {
    /// Экспортированные данные
    public let data: Data

    /// Имя файла
    public let filename: String

    /// MIME-тип
    public let mimeType: String

    /// Сохранить в файл
    public func save(to url: URL) throws {
        try data.write(to: url)
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Создать URL для временного файла
    @MainActor
    public func temporaryFileURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
    #endif
}
