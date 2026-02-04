import Foundation
import Combine

/// Движок моков
@MainActor
public final class MockEngine: ObservableObject {
    // MARK: - Singleton

    public static let shared = MockEngine()

    // MARK: - Published Properties

    /// Все правила моков
    @Published public private(set) var rules: [MockRule] = []

    /// Включен ли движок
    @Published public var isEnabled: Bool = true

    // MARK: - Properties

    private let userDefaultsKey = "NetCheckerMockRules"

    // MARK: - Initialization

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - Rule Management

    /// Добавить правило
    public func addRule(_ rule: MockRule) {
        rules.append(rule)
        sortRules()
        saveToUserDefaults()
    }

    /// Удалить правило
    public func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveToUserDefaults()
    }

    /// Обновить правило
    public func updateRule(_ rule: MockRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            sortRules()
            saveToUserDefaults()
        }
    }

    /// Включить/выключить правило
    public func setRuleEnabled(id: UUID, enabled: Bool) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules[index].isEnabled = enabled
            saveToUserDefaults()
        }
    }

    /// Очистить все правила
    public func clearRules() {
        rules.removeAll()
        saveToUserDefaults()
    }

    // MARK: - Matching

    /// Найти соответствующее правило для запроса
    public func match(request: URLRequest) -> MockResponse? {
        guard isEnabled else { return nil }

        for index in rules.indices {
            if rules[index].matches(request: request) {
                rules[index].activationCount += 1

                switch rules[index].action {
                case .respond(let response):
                    return response

                case .error(let mockError):
                    // Return error as nil response - will be handled separately
                    return nil

                case .delay(let seconds):
                    // Apply delay but let request through
                    Thread.sleep(forTimeInterval: seconds)
                    return nil

                case .passthrough:
                    return nil

                case .modifyResponse:
                    // Will be handled when response comes back
                    return nil
                }
            }
        }

        return nil
    }

    /// Найти ошибку мока для запроса
    public func matchError(request: URLRequest) -> NSError? {
        guard isEnabled else { return nil }

        for rule in rules {
            if rule.matches(request: request) {
                if case .error(let mockError) = rule.action {
                    return mockError.nsError
                }
            }
        }

        return nil
    }

    // MARK: - Private Methods

    private func sortRules() {
        rules.sort { $0.priority > $1.priority }
    }

    private func saveToUserDefaults() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([MockRule].self, from: data) else {
            return
        }
        rules = decoded
        sortRules()
    }
}

// MARK: - Convenience Methods

public extension MockEngine {
    /// Быстрое добавление mock response
    func mock(
        url pattern: String,
        method: HTTPMethod? = nil,
        response: MockResponse
    ) {
        let rule = MockRule(
            matching: MockMatching(urlPattern: pattern, method: method),
            action: .respond(response)
        )
        addRule(rule)
    }

    /// Быстрое добавление mock JSON
    func mockJSON(
        url pattern: String,
        method: HTTPMethod? = nil,
        json: String,
        statusCode: Int = 200
    ) {
        mock(url: pattern, method: method, response: .json(json, statusCode: statusCode))
    }

    /// Быстрое добавление mock error
    func mockError(
        url pattern: String,
        method: HTTPMethod? = nil,
        error: MockError
    ) {
        let rule = MockRule(
            matching: MockMatching(urlPattern: pattern, method: method),
            action: .error(error)
        )
        addRule(rule)
    }

    /// Быстрое добавление delay
    func mockDelay(
        url pattern: String,
        method: HTTPMethod? = nil,
        seconds: TimeInterval
    ) {
        let rule = MockRule(
            matching: MockMatching(urlPattern: pattern, method: method),
            action: .delay(seconds: seconds)
        )
        addRule(rule)
    }
}
