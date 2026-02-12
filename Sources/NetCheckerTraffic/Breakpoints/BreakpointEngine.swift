import Foundation
import Combine

/// Движок breakpoints
@MainActor
public final class BreakpointEngine: ObservableObject {
    // MARK: - Singleton

    public static let shared = BreakpointEngine()

    // MARK: - Published Properties

    /// Все правила
    @Published public private(set) var rules: [BreakpointRule] = []

    /// Включен ли движок
    @Published public var isEnabled: Bool = false {
        didSet {
            saveEnabledState()
        }
    }

    /// Приостановленные запросы
    @Published public private(set) var pausedRequests: [PausedRequest] = []

    // MARK: - Properties

    private let userDefaultsKey = "NetCheckerBreakpointRules"
    private let enabledKey = "NetCheckerBreakpointsEnabled"
    private var continuations: [UUID: CheckedContinuation<URLRequest?, Never>] = [:]

    // MARK: - Initialization

    private init() {
        loadFromUserDefaults()
        loadEnabledState()
    }

    // MARK: - Rule Management

    /// Добавить правило
    public func addRule(_ rule: BreakpointRule) {
        rules.append(rule)
        saveToUserDefaults()
    }

    /// Удалить правило
    public func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveToUserDefaults()
    }

    /// Обновить правило
    public func updateRule(_ rule: BreakpointRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
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

    // MARK: - Breakpoint Handling

    /// Проверить, нужно ли остановиться на запросе
    public func shouldPause(request: URLRequest) -> Bool {
        guard isEnabled else { return false }

        for rule in rules {
            if rule.matches(request: request) &&
               (rule.direction == .request || rule.direction == .both) {
                return true
            }
        }

        return false
    }

    /// Проверить, нужно ли остановиться на ответе
    public func shouldPauseResponse(request: URLRequest) -> Bool {
        guard isEnabled else { return false }

        for rule in rules {
            if rule.matches(request: request) &&
               (rule.direction == .response || rule.direction == .both) {
                return true
            }
        }

        return false
    }

    /// Приостановить запрос и ждать
    public func pause(request: URLRequest, phase: BreakpointPhase = .request) async -> URLRequest? {
        let id = UUID()
        let pausedRequest = PausedRequest(id: id, originalRequest: request, phase: phase)

        pausedRequests.append(pausedRequest)

        // Get matching rule for auto-resume
        let matchingRule = rules.first { $0.matches(request: request) }

        return await withCheckedContinuation { continuation in
            continuations[id] = continuation

            // Setup auto-resume if configured
            if let autoResume = matchingRule?.autoResume {
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(autoResume * 1_000_000_000))
                    await self.resume(id: id, with: nil)
                }
            }
        }
    }

    /// Продолжить запрос
    public func resume(id: UUID, with modifiedRequest: URLRequest?) {
        guard let index = pausedRequests.firstIndex(where: { $0.id == id }) else { return }

        let paused = pausedRequests[index]
        pausedRequests.remove(at: index)

        if let continuation = continuations[id] {
            continuation.resume(returning: modifiedRequest ?? paused.originalRequest)
            continuations.removeValue(forKey: id)
        }
    }

    /// Отменить запрос
    public func cancel(id: UUID) {
        guard let index = pausedRequests.firstIndex(where: { $0.id == id }) else { return }

        pausedRequests.remove(at: index)

        if let continuation = continuations[id] {
            continuation.resume(returning: nil)
            continuations.removeValue(forKey: id)
        }
    }

    /// Продолжить все приостановленные запросы
    public func resumeAll() {
        for paused in pausedRequests {
            resume(id: paused.id, with: nil)
        }
    }

    /// Отменить все приостановленные запросы
    public func cancelAll() {
        for paused in pausedRequests {
            cancel(id: paused.id)
        }
    }

    // MARK: - Private Methods

    private func saveToUserDefaults() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([BreakpointRule].self, from: data) else {
            return
        }
        rules = decoded
    }

    private func saveEnabledState() {
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
    }

    private func loadEnabledState() {
        // Only load if value was previously saved, otherwise use default (false)
        if UserDefaults.standard.object(forKey: enabledKey) != nil {
            isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
    }
}

// MARK: - Paused Request

/// Phase at which a breakpoint paused the request
public enum BreakpointPhase: String, Sendable, Codable {
    /// Paused before sending the request to the server
    case request
    /// Paused after receiving the response, before delivering to the app
    case response
}

public struct PausedRequest: Identifiable, Sendable {
    public let id: UUID
    public let originalRequest: URLRequest
    public let pausedAt: Date
    public let phase: BreakpointPhase

    init(id: UUID, originalRequest: URLRequest, phase: BreakpointPhase = .request) {
        self.id = id
        self.originalRequest = originalRequest
        self.pausedAt = Date()
        self.phase = phase
    }

    public var url: URL? {
        originalRequest.url
    }

    public var method: String {
        originalRequest.httpMethod ?? "GET"
    }

    public var host: String {
        originalRequest.url?.host ?? ""
    }

    public var path: String {
        originalRequest.url?.path ?? "/"
    }

    public var pausedDuration: TimeInterval {
        Date().timeIntervalSince(pausedAt)
    }

    public var phaseLabel: String {
        switch phase {
        case .request: return "Request"
        case .response: return "Response"
        }
    }
}

// MARK: - Convenience Methods

public extension BreakpointEngine {
    /// Быстрое добавление breakpoint для URL
    func breakpoint(url pattern: String, direction: BreakpointDirection = .request) {
        let rule = BreakpointRule(
            matching: .url(pattern),
            direction: direction
        )
        addRule(rule)
    }

    /// Быстрое добавление breakpoint для хоста
    func breakpoint(host: String, direction: BreakpointDirection = .request) {
        let rule = BreakpointRule(
            matching: .host(host),
            direction: direction
        )
        addRule(rule)
    }
}
