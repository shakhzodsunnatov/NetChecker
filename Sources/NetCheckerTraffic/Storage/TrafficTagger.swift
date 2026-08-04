import Foundation

/// Правило автоматической пометки трафика.
///
/// Позволяет заранее сказать «всё, что идёт на `/checkout` и `/payment`,
/// относится к потоку NewFeatureFlow», а потом отфильтровать список по этому
/// имени, не выискивая запросы глазами.
public struct TrafficTagRule: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID

    /// Имя тега, например `NewFeatureFlow`
    public var tag: String

    /// Подстрока или wildcard-паттерн URL
    public var urlPattern: String

    /// Метод (nil — любой)
    public var method: HTTPMethod?

    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        tag: String,
        urlPattern: String,
        method: HTTPMethod? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.tag = tag
        self.urlPattern = urlPattern
        self.method = method
        self.isEnabled = isEnabled
    }

    /// Подходит ли правило под запрос
    public func matches(url: URL, method requestMethod: HTTPMethod) -> Bool {
        guard isEnabled else { return false }

        if let method = method, method != requestMethod { return false }
        guard !urlPattern.isEmpty else { return false }

        let target = url.absoluteString.lowercased()
        let pattern = urlPattern.lowercased()

        guard pattern.contains("*") else {
            return target.contains(pattern)
        }

        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(target.startIndex..., in: target)
        return regex.firstMatch(in: target, options: [], range: range) != nil
    }
}

/// Хранилище правил пометки и применение их к трафику
@MainActor
public final class TrafficTagger: ObservableObject {
    public static let shared = TrafficTagger()

    /// Правила пометки
    @Published public private(set) var rules: [TrafficTagRule] = [] {
        didSet { persist() }
    }

    private let storageKey = "NetCheckerTagRules"

    private init() {
        load()
    }

    // MARK: - Правила

    public func addRule(_ rule: TrafficTagRule) {
        rules.append(rule)
    }

    /// Быстрое добавление: пометить всё по паттерну заданным тегом
    public func tag(_ tag: String, matching urlPattern: String, method: HTTPMethod? = nil) {
        addRule(TrafficTagRule(tag: tag, urlPattern: urlPattern, method: method))
    }

    public func updateRule(_ rule: TrafficTagRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
    }

    public func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    public func clearRules() {
        rules.removeAll()
    }

    /// Все теги, встречающиеся в правилах
    public var knownTags: [String] {
        Array(Set(rules.map(\.tag))).sorted()
    }

    // MARK: - Применение

    /// Теги, которые следует навесить на запрос
    public func tags(for url: URL, method: HTTPMethod) -> [String] {
        var result: [String] = []
        for rule in rules where rule.matches(url: url, method: method) {
            if !result.contains(rule.tag) {
                result.append(rule.tag)
            }
        }
        return result
    }

    /// Пометить уже записанный трафик — например, после добавления правила
    public func reapplyToStoredTraffic() {
        let store = TrafficStore.shared

        for record in store.records {
            let matched = tags(for: record.request.url, method: record.request.method)
            guard !matched.isEmpty else { continue }

            store.update(id: record.id) { stored in
                for tag in matched where !stored.metadata.tags.contains(tag) {
                    stored.metadata.tags.append(tag)
                }
            }
        }
    }

    // MARK: - Персистентность

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([TrafficTagRule].self, from: data) else {
            return
        }
        rules = stored
    }
}
