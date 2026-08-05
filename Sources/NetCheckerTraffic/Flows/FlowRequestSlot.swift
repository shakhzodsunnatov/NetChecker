import Foundation

/// Место в запросе, куда можно положить значение.
///
/// Раньше пользователь выбирал абстрактную категорию — «Заголовок / Путь /
/// Параметр / Тело» — и вводил имя руками. Слоты вычисляются из настоящего
/// запроса, поэтому вместо категорий видно конкретные места: `{orderId}` в пути,
/// поле `userId` в теле, заголовок `Authorization`.
public struct FlowRequestSlot: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// Плейсхолдер `{name}` в пути
        case pathPlaceholder
        /// Существующий заголовок
        case header
        /// Существующий query-параметр
        case queryItem
        /// Поле JSON-тела верхнего уровня
        case bodyField
        /// Заголовок, которого ещё нет, но он часто нужен
        case suggestedHeader
    }

    public var id: String { "\(kind)-\(name)" }

    public let kind: Kind
    public let name: String

    /// Что там сейчас — помогает понять, то ли это место
    public let currentValue: String?

    public init(kind: Kind, name: String, currentValue: String? = nil) {
        self.kind = kind
        self.name = name
        self.currentValue = currentValue
    }

    /// Куда это отображается в модели подстановки
    public var target: FlowValueTarget {
        switch kind {
        case .pathPlaceholder: return .pathPlaceholder(name)
        case .header, .suggestedHeader: return .header(name)
        case .queryItem: return .queryItem(name)
        case .bodyField: return .bodyField(name)
        }
    }

    /// Человеческое описание места, без жаргона
    public var kindTitle: String {
        switch kind {
        case .pathPlaceholder: return "в адресе"
        case .header: return "в заголовке"
        case .suggestedHeader: return "новый заголовок"
        case .queryItem: return "в параметре"
        case .bodyField: return "в теле"
        }
    }

    public var systemImage: String {
        switch kind {
        case .pathPlaceholder: return "link"
        case .header, .suggestedHeader: return "tag"
        case .queryItem: return "questionmark.circle"
        case .bodyField: return "curlybraces"
        }
    }
}

/// Поиск мест подстановки в запросе
public enum FlowRequestSlots {

    /// Заголовки, которые предлагаются, даже если их ещё нет:
    /// токен чаще всего кладут именно туда
    public static let suggestedHeaders = ["Authorization", "X-API-Key"]

    /// Все места, куда можно положить значение
    public static func slots(in request: RequestData) -> [FlowRequestSlot] {
        var result: [FlowRequestSlot] = []

        result.append(contentsOf: pathPlaceholders(in: request.url))
        result.append(contentsOf: queryItems(in: request.url))

        for name in request.headers.keys.sorted() {
            result.append(.init(kind: .header, name: name, currentValue: request.headers[name]))
        }

        let existing = Set(request.headers.keys.map { $0.lowercased() })
        for name in suggestedHeaders where !existing.contains(name.lowercased()) {
            result.append(.init(kind: .suggestedHeader, name: name))
        }

        if let body = request.body,
           let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            for key in object.keys.sorted() {
                result.append(
                    .init(kind: .bodyField, name: key, currentValue: describe(object[key]))
                )
            }
        }

        return result
    }

    /// Плейсхолдеры `{name}` в пути.
    /// URL хранит фигурные скобки экранированными, поэтому ищем обе формы.
    static func pathPlaceholders(in url: URL) -> [FlowRequestSlot] {
        let text = url.absoluteString
            .replacingOccurrences(of: "%7B", with: "{")
            .replacingOccurrences(of: "%7b", with: "{")
            .replacingOccurrences(of: "%7D", with: "}")
            .replacingOccurrences(of: "%7d", with: "}")

        guard let regex = try? NSRegularExpression(pattern: "\\{([^}/]+)\\}") else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: text) else { return nil }
            return FlowRequestSlot(kind: .pathPlaceholder, name: String(text[nameRange]))
        }
    }

    private static func queryItems(in url: URL) -> [FlowRequestSlot] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [] }

        return items.map { .init(kind: .queryItem, name: $0.name, currentValue: $0.value) }
    }

    private static func describe(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.doubleValue == number.doubleValue.rounded()
                ? String(number.intValue)
                : String(number.doubleValue)
        case is NSNull: return "null"
        default: return nil
        }
    }
}
