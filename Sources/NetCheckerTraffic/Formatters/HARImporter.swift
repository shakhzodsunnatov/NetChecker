import Foundation

/// Импорт HAR-сессий: просмотр записанного трафика и его воспроизведение моками
@MainActor
public enum HARImporter {

    /// Результат импорта
    public struct Result: Sendable {
        /// Разобранные записи
        public let records: [TrafficRecord]

        /// Сколько записей добавлено в хранилище
        public let importedCount: Int

        /// Сколько правил моков создано
        public let mockRuleCount: Int
    }

    // MARK: - Импорт

    /// Загрузить HAR в хранилище трафика для просмотра
    @discardableResult
    public static func importRecords(from data: Data) throws -> Result {
        let records = try HARParser.parse(data)

        for record in records {
            TrafficStore.shared.add(record)
        }

        return Result(records: records, importedCount: records.count, mockRuleCount: 0)
    }

    /// Загрузить HAR и включить воспроизведение: каждая запись становится моком
    @discardableResult
    public static func importAndReplay(from data: Data, replaceExistingRules: Bool = false) throws -> Result {
        let records = try HARParser.parse(data)

        for record in records {
            TrafficStore.shared.add(record)
        }

        if replaceExistingRules {
            MockEngine.shared.clearRules()
        }

        let rules = mockRules(from: records)
        for rule in rules {
            MockEngine.shared.addRule(rule)
        }

        if !rules.isEmpty {
            MockEngine.shared.isEnabled = true
        }

        return Result(records: records, importedCount: records.count, mockRuleCount: rules.count)
    }

    /// Построить правила моков из записей, ничего не применяя
    public static func mockRules(from records: [TrafficRecord]) -> [MockRule] {
        var seen = Set<String>()
        var rules: [MockRule] = []

        for record in records {
            guard let response = record.response else { continue }

            let pattern = urlPattern(for: record.request.url)
            let key = "\(record.request.method.rawValue) \(pattern)"

            // Первое вхождение выигрывает: в HAR один эндпоинт встречается многократно,
            // а несколько правил на один паттерн только мешали бы друг другу
            guard seen.insert(key).inserted else { continue }

            rules.append(
                MockRule(
                    name: "HAR: \(record.request.method.rawValue) \(record.path)",
                    priority: 50,
                    matching: MockMatching(urlPattern: pattern, method: record.request.method),
                    action: .respond(
                        MockResponse(
                            statusCode: response.statusCode,
                            headers: response.headers,
                            body: response.body
                        )
                    )
                )
            )
        }

        return rules
    }

    // MARK: - Private

    /// Заменить числовые сегменты и UUID на `*`, чтобы правило покрывало похожие URL
    private static func urlPattern(for url: URL) -> String {
        let segments = url.path.split(separator: "/").map { segment -> String in
            let text = String(segment)
            if text.allSatisfy(\.isNumber) { return "*" }
            if UUID(uuidString: text) != nil { return "*" }
            return text
        }

        let path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        return "*\(url.host ?? "")\(path)"
    }
}
