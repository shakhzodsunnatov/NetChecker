import Foundation

/// Агрегированная статистика трафика
public struct TrafficStatistics: Sendable {
    // MARK: - General Stats

    /// Общее количество запросов
    public let totalRequests: Int

    /// Успешные запросы
    public let successfulRequests: Int

    /// Неудачные запросы
    public let failedRequests: Int

    /// Pending запросы
    public let pendingRequests: Int

    /// Процент успешных
    public var successRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successfulRequests) / Double(totalRequests) * 100
    }

    /// Общее количество полученных байт
    public let totalBytesReceived: Int64

    /// Общее количество отправленных байт
    public let totalBytesSent: Int64

    /// Длительность сессии
    public let sessionDuration: TimeInterval

    // MARK: - Timing Stats

    /// Среднее время ответа
    public let avgResponseTime: TimeInterval

    /// Медианное время ответа
    public let medianResponseTime: TimeInterval

    /// 95-й перцентиль времени ответа
    public let p95ResponseTime: TimeInterval

    /// 99-й перцентиль времени ответа
    public let p99ResponseTime: TimeInterval

    /// Самый быстрый запрос
    public let fastestRequest: TrafficRecord?

    /// Самый медленный запрос
    public let slowestRequest: TrafficRecord?

    /// Среднее время DNS
    public let avgDNSTime: TimeInterval

    // MARK: - Host Stats

    /// Запросы по хостам
    public let requestsByHost: [String: Int]

    /// Ошибки по хостам
    public let errorsByHost: [String: Int]

    /// Среднее время по хостам
    public let avgTimeByHost: [String: TimeInterval]

    /// Трафик по хостам
    public let dataByHost: [String: Int64]

    // MARK: - Method Stats

    /// Запросы по методам
    public let requestsByMethod: [HTTPMethod: Int]

    // MARK: - Status Stats

    /// Запросы по статус-кодам
    public let requestsByStatusCode: [Int: Int]

    /// Запросы по категориям
    public let requestsByCategory: [StatusCategory: Int]

    // MARK: - Time Series (для графиков)

    /// Запросы в минуту
    public let requestsPerMinute: [(Date, Int)]

    /// Ошибки в минуту
    public let errorsPerMinute: [(Date, Int)]

    /// Среднее время ответа в минуту
    public let avgResponseTimePerMinute: [(Date, TimeInterval)]

    // MARK: - Top Lists

    /// Топ 10 самых медленных
    public let top10Slowest: [TrafficRecord]

    /// Топ 10 самых больших
    public let top10Largest: [TrafficRecord]

    /// Топ 10 самых частых URL patterns
    public let top10MostFrequent: [(String, Int)]

    /// Последние ошибки
    public let recentErrors: [TrafficRecord]

    // MARK: - Computed Properties

    /// Форматированный размер полученных данных
    public var formattedBytesReceived: String {
        ByteCountFormatter.string(fromByteCount: totalBytesReceived, countStyle: .file)
    }

    /// Форматированный размер отправленных данных
    public var formattedBytesSent: String {
        ByteCountFormatter.string(fromByteCount: totalBytesSent, countStyle: .file)
    }

    /// Форматированное среднее время
    public var formattedAvgTime: String {
        formatDuration(avgResponseTime)
    }

    /// Форматированное медианное время
    public var formattedMedianTime: String {
        formatDuration(medianResponseTime)
    }

    /// Общее количество данных
    public var totalBytes: Int64 {
        totalBytesReceived + totalBytesSent
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 0.001 {
            return "<1 ms"
        } else if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else {
            return String(format: "%.2f s", duration)
        }
    }

    // MARK: - Initialization

    public init(from records: [TrafficRecord], sessionStart: Date = Date()) {
        self.totalRequests = records.count
        self.successfulRequests = records.filter { $0.isSuccess }.count
        self.failedRequests = records.filter { $0.isError }.count
        self.pendingRequests = records.filter {
            if case .pending = $0.state { return true }
            return false
        }.count

        self.totalBytesReceived = records.reduce(0) { $0 + $1.responseSize }
        self.totalBytesSent = records.reduce(0) { $0 + $1.requestSize }

        if let first = records.first {
            self.sessionDuration = Date().timeIntervalSince(first.timestamp)
        } else {
            self.sessionDuration = Date().timeIntervalSince(sessionStart)
        }

        // Timing stats
        let completedRecords = records.filter {
            if case .completed = $0.state { return true }
            return false
        }
        let durations = completedRecords.map { $0.duration }.sorted()

        if durations.isEmpty {
            self.avgResponseTime = 0
            self.medianResponseTime = 0
            self.p95ResponseTime = 0
            self.p99ResponseTime = 0
        } else {
            self.avgResponseTime = durations.reduce(0, +) / Double(durations.count)
            self.medianResponseTime = durations[durations.count / 2]
            self.p95ResponseTime = durations[min(Int(Double(durations.count) * 0.95), durations.count - 1)]
            self.p99ResponseTime = durations[min(Int(Double(durations.count) * 0.99), durations.count - 1)]
        }

        self.fastestRequest = completedRecords.min { $0.duration < $1.duration }
        self.slowestRequest = completedRecords.max { $0.duration < $1.duration }

        let dnsTimings = completedRecords.compactMap { $0.timings?.dnsLookup }
        self.avgDNSTime = dnsTimings.isEmpty ? 0 : dnsTimings.reduce(0, +) / Double(dnsTimings.count)

        // Host stats
        var requestsByHost: [String: Int] = [:]
        var errorsByHost: [String: Int] = [:]
        var timeByHost: [String: [TimeInterval]] = [:]
        var dataByHost: [String: Int64] = [:]

        for record in records {
            let host = record.host
            requestsByHost[host, default: 0] += 1

            if record.isError {
                errorsByHost[host, default: 0] += 1
            }

            if case .completed = record.state {
                timeByHost[host, default: []].append(record.duration)
            }

            dataByHost[host, default: 0] += record.responseSize
        }

        self.requestsByHost = requestsByHost
        self.errorsByHost = errorsByHost
        self.avgTimeByHost = timeByHost.mapValues { times in
            times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
        }
        self.dataByHost = dataByHost

        // Method stats
        var requestsByMethod: [HTTPMethod: Int] = [:]
        for record in records {
            requestsByMethod[record.method, default: 0] += 1
        }
        self.requestsByMethod = requestsByMethod

        // Status stats
        var requestsByStatusCode: [Int: Int] = [:]
        var requestsByCategory: [StatusCategory: Int] = [:]
        for record in records {
            if let status = record.statusCode {
                requestsByStatusCode[status, default: 0] += 1
            }
            if let category = record.statusCategory {
                requestsByCategory[category, default: 0] += 1
            }
        }
        self.requestsByStatusCode = requestsByStatusCode
        self.requestsByCategory = requestsByCategory

        // Time series (group by minute)
        var minuteGroups: [Date: [TrafficRecord]] = [:]
        let calendar = Calendar.current
        for record in records {
            let minute = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.timestamp)) ?? record.timestamp
            minuteGroups[minute, default: []].append(record)
        }

        let sortedMinutes = minuteGroups.keys.sorted()
        self.requestsPerMinute = sortedMinutes.map { ($0, minuteGroups[$0]!.count) }
        self.errorsPerMinute = sortedMinutes.map { ($0, minuteGroups[$0]!.filter { $0.isError }.count) }
        self.avgResponseTimePerMinute = sortedMinutes.map { minute in
            let group = minuteGroups[minute]!
            let durations = group.compactMap { record -> TimeInterval? in
                if case .completed = record.state { return record.duration }
                return nil
            }
            let avg = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
            return (minute, avg)
        }

        // Top lists
        self.top10Slowest = Array(completedRecords.sorted { $0.duration > $1.duration }.prefix(10))
        self.top10Largest = Array(records.sorted { $0.responseSize > $1.responseSize }.prefix(10))

        // Most frequent URL patterns (path only)
        var pathCounts: [String: Int] = [:]
        for record in records {
            pathCounts[record.path, default: 0] += 1
        }
        self.top10MostFrequent = Array(pathCounts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) })

        // Recent errors
        self.recentErrors = Array(records.filter { $0.isError }.suffix(20).reversed())
    }
}

// MARK: - Empty Statistics

public extension TrafficStatistics {
    static var empty: TrafficStatistics {
        TrafficStatistics(from: [])
    }
}
