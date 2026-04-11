import Foundation

/// Генератор тестов из записанных MCP-потоков
public enum MCPTestGenerator {

    // MARK: - Генерация MockRules

    /// Сгенерировать MockRules из завершённого потока
    /// Каждый сетевой вызов → MockRule с записанным ответом
    @MainActor
    public static func generateMockRules(from flow: MCPFlow) -> [MockRule] {
        let store = TrafficStore.shared
        var rules: [MockRule] = []

        for (index, entry) in flow.entries.enumerated() {
            guard let record = store.record(for: entry.id),
                  let response = record.response else {
                continue
            }

            // Только сетевые вызовы
            guard entry.operationType.isNetworkRelated else { continue }

            let urlPattern = buildURLPattern(from: record.url)

            let mockResponse = MockResponse(
                statusCode: response.statusCode,
                headers: response.headers,
                body: response.body,
                delay: 0
            )

            let rule = MockRule(
                name: "Flow: \(flow.name) — Step \(index + 1)",
                priority: 100 - index,
                matching: MockMatching(
                    urlPattern: urlPattern,
                    method: record.method
                ),
                action: .respond(mockResponse)
            )

            rules.append(rule)
        }

        return rules
    }

    /// Добавить сгенерированные правила в MockEngine
    @MainActor
    public static func applyMockRules(from flow: MCPFlow) -> Int {
        let rules = generateMockRules(from: flow)
        let engine = MockEngine.shared

        for rule in rules {
            engine.addRule(rule)
        }

        return rules.count
    }

    // MARK: - Генерация тест-кода

    /// Сгенерировать Swift тест-код из потока
    @MainActor
    public static func generateTestCode(
        from flow: MCPFlow,
        testClassName: String = "GeneratedFlowTest"
    ) -> String {
        let store = TrafficStore.shared
        var code = """
        import XCTest
        @testable import NetCheckerTraffic

        /// Автогенерированный тест из MCP-потока: \(flow.name)
        /// Дата: \(ISO8601DateFormatter().string(from: Date()))
        final class \(testClassName): XCTestCase {

            override func setUp() {
                super.setUp()
                TrafficInterceptor.shared.start()
                MockEngine.shared.clearRules()
            }

            override func tearDown() {
                MockEngine.shared.clearRules()
                TrafficInterceptor.shared.stop()
                super.tearDown()
            }

            func testFlow_\(sanitize(flow.name))() async throws {
                // Настройка моков
        """

        // Генерируем моки для каждого сетевого вызова
        for (index, entry) in flow.entries.enumerated() {
            guard let record = store.record(for: entry.id),
                  entry.operationType.isNetworkRelated else {
                continue
            }

            let urlPattern = buildURLPattern(from: record.url)
            let method = record.method.rawValue
            let statusCode = record.statusCode ?? 200

            code += """

                    // Step \(index + 1): \(method) \(record.path)
                    MockEngine.shared.mockJSON(
                        url: "\(urlPattern)",
                        method: .\(method.lowercased()),
                        json: \"\"\"\n\(record.response?.bodyString ?? "{}")\n\"\"\",
                        statusCode: \(statusCode)
                    )
            """
        }

        code += """

                // Выполнение потока
        """

        // Генерируем assertions
        for (index, entry) in flow.entries.enumerated() {
            guard let record = store.record(for: entry.id),
                  entry.operationType.isNetworkRelated else {
                continue
            }

            let statusCode = record.statusCode ?? 200

            code += """

                    // Проверка Step \(index + 1)
                    let url\(index) = URL(string: "\(record.url.absoluteString)")!
                    let (data\(index), response\(index)) = try await URLSession.shared.data(from: url\(index))
                    let httpResponse\(index) = response\(index) as! HTTPURLResponse
                    XCTAssertEqual(httpResponse\(index).statusCode, \(statusCode))
            """
        }

        code += """

            }
        }

        """

        return code
    }

    // MARK: - Экспорт потока

    /// Формат экспорта потока
    public enum FlowExportFormat: String, CaseIterable, Sendable {
        /// JSON с MockRules
        case mockRules

        /// Swift тест-код
        case testCode

        /// HAR (переиспользует существующий форматтер)
        case har
    }

    /// Экспортировать поток в указанном формате
    @MainActor
    public static func exportFlow(
        _ flow: MCPFlow,
        format: FlowExportFormat
    ) -> Data? {
        switch format {
        case .mockRules:
            let rules = generateMockRules(from: flow)
            return try? JSONEncoder().encode(rules)

        case .testCode:
            let code = generateTestCode(from: flow)
            return code.data(using: .utf8)

        case .har:
            let store = TrafficStore.shared
            let records = flow.entries.compactMap { store.record(for: $0.id) }
            return HARFormatter.format(records: records)
        }
    }

    // MARK: - Private Helpers

    /// Построить URL-паттерн для MockRule
    private static func buildURLPattern(from url: URL) -> String {
        // Заменяем числовые сегменты пути на * (ID)
        var path = url.path
        let components = path.split(separator: "/")
        let wildcardedComponents = components.map { segment -> String in
            // Если сегмент — числовой ID или UUID, заменяем на *
            let str = String(segment)
            if str.allSatisfy({ $0.isNumber }) || UUID(uuidString: str) != nil {
                return "*"
            }
            return str
        }
        path = "/" + wildcardedComponents.joined(separator: "/")

        return "*\(url.host ?? "")\(path)"
    }

    /// Санитизировать имя для Swift-идентификатора
    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
