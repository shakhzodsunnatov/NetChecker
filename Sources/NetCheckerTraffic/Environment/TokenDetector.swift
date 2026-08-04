import Foundation

/// Найденный в трафике токен
public struct DetectedToken: Identifiable, Sendable, Hashable {
    public var id: String { "\(host)|\(headerName)|\(value)" }

    /// Хост, на котором встретился токен
    public let host: String

    /// Имя заголовка
    public let headerName: String

    /// Значение
    public let value: String

    /// Сколько запросов его использовали
    public let occurrences: Int

    /// Значение с закрытой серединой
    public var masked: String {
        let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let scheme = parts.count == 2 ? String(parts[0]) + " " : ""
        let secret = parts.count == 2 ? String(parts[1]) : value

        guard secret.count > 10 else { return scheme + String(repeating: "•", count: max(secret.count, 3)) }
        return scheme + secret.prefix(4) + "…" + secret.suffix(4)
    }
}

/// Поиск токенов авторизации в записанном трафике.
///
/// Избавляет от копирования токена руками: если приложение уже сходило
/// в сеть, значение можно взять прямо оттуда и положить в окружение.
@MainActor
public enum TokenDetector {

    /// Найти токены в текущих записях трафика
    public static func detect(in records: [TrafficRecord]? = nil) -> [DetectedToken] {
        let source = records ?? TrafficStore.shared.records

        // Ключ — хост + заголовок + значение; считаем, сколько раз встретилось
        var counts: [String: (host: String, header: String, value: String, count: Int)] = [:]

        for record in source {
            let host = record.host
            guard !host.isEmpty else { continue }

            for (name, value) in record.request.headers {
                guard Environment.tokenHeaderNames.contains(name.lowercased()) else { continue }

                let trimmed = value.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !isRedacted(trimmed) else { continue }

                let key = "\(host.lowercased())|\(name.lowercased())|\(trimmed)"
                if let existing = counts[key] {
                    counts[key] = (existing.host, existing.header, existing.value, existing.count + 1)
                } else {
                    counts[key] = (host, name, trimmed, 1)
                }
            }
        }

        return counts.values
            .map { DetectedToken(host: $0.host, headerName: $0.header, value: $0.value, occurrences: $0.count) }
            .sorted { $0.occurrences > $1.occurrences }
    }

    /// Токены, встреченные на хостах указанного окружения
    public static func detect(forHost host: String) -> [DetectedToken] {
        let needle = host.lowercased()
        return detect().filter { $0.host.lowercased().contains(needle) || needle.contains($0.host.lowercased()) }
    }

    /// Значение уже замаскировано политикой захвата — подставлять его бессмысленно
    private static func isRedacted(_ value: String) -> Bool {
        value.contains("REDACTED") || value.allSatisfy { $0 == "*" }
    }
}
