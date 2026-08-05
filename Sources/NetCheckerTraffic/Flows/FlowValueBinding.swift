import Foundation

/// Откуда берётся значение из ответа шага
public enum FlowValueSource: Codable, Sendable, Hashable {
    /// Путь по JSON-телу, сегменты через точку: `data.order.id`
    case jsonPath(String)
    /// Заголовок ответа
    case header(String)

    public var summary: String {
        switch self {
        case .jsonPath(let path): return path
        case .header(let name): return "заголовок \(name)"
        }
    }
}

/// Куда значение подставляется в следующий запрос
public enum FlowValueTarget: Codable, Sendable, Hashable {
    case header(String)
    /// Плейсхолдер в пути: `/orders/{orderId}/pay`
    case pathPlaceholder(String)
    case queryItem(String)
    /// Поле JSON-тела верхнего уровня
    case bodyField(String)

    public var summary: String {
        switch self {
        case .header(let name): return "заголовок \(name)"
        case .pathPlaceholder(let name): return "путь {\(name)}"
        case .queryItem(let name): return "параметр \(name)"
        case .bodyField(let name): return "поле тела \(name)"
        }
    }
}

/// Значение, извлекаемое из ответа шага
public struct FlowOutput: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var source: FlowValueSource

    public init(id: UUID = UUID(), name: String, source: FlowValueSource) {
        self.id = id
        self.name = name
        self.source = source
    }
}

/// Значение, подставляемое в запрос шага
public struct FlowInput: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Имя значения, объявленного выходом одного из предыдущих шагов
    public var name: String
    public var target: FlowValueTarget

    public init(id: UUID = UUID(), name: String, target: FlowValueTarget) {
        self.id = id
        self.name = name
        self.target = target
    }
}

/// Извлечение значений из ответа
public enum FlowValueExtractor {

    /// Достать значение.
    ///
    /// `nil` означает «в ответе такого нет». Вызывающая сторона обязана считать
    /// это ошибкой шага: подставить пустую строку значит отправить заведомо
    /// неверный запрос и получить непонятную ошибку от сервера.
    public static func extract(_ output: FlowOutput, from response: ResponseData) -> String? {
        switch output.source {
        case .header(let name):
            let needle = name.lowercased()
            for (headerName, value) in response.headers where headerName.lowercased() == needle {
                return value
            }
            return nil

        case .jsonPath(let path):
            guard let body = response.body,
                  let root = try? JSONSerialization.jsonObject(with: body) else { return nil }
            return value(at: path, in: root)
        }
    }

    private static func value(at path: String, in root: Any) -> String? {
        var current: Any? = root

        for segment in path.split(separator: ".") {
            guard let dictionary = current as? [String: Any] else { return nil }
            current = dictionary[String(segment)]
        }

        switch current {
        case let text as String: return text
        case let number as NSNumber: return describe(number)
        default: return nil
        }
    }

    /// NSNumber одинаково представляет число и булево — различаем по CFTypeID,
    /// иначе `true` превратилось бы в «1» и условие «истина» перестало бы работать
    private static func describe(_ number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if number.doubleValue == number.doubleValue.rounded() {
            return String(number.intValue)
        }
        return String(number.doubleValue)
    }
}

/// Подстановка значений в запрос
public enum FlowValueInjector {

    public static func apply(_ input: FlowInput, value: String, to request: inout RequestData) {
        switch input.target {
        case .header(let name):
            request.headers[name] = value

        case .pathPlaceholder(let name):
            replacePlaceholder(name, with: value, in: &request)

        case .queryItem(let name):
            guard var components = URLComponents(url: request.url, resolvingAgainstBaseURL: false) else { return }
            var items = components.queryItems ?? []
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
            components.queryItems = items
            if let url = components.url { request.url = url }

        case .bodyField(let name):
            guard let body = request.body,
                  var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return }
            object[name] = value
            guard let updated = try? JSONSerialization.data(withJSONObject: object) else { return }
            request.body = updated
            request.bodySize = Int64(updated.count)
        }
    }

    /// Фигурные скобки в URL недопустимы, поэтому в `URL` они хранятся
    /// процентно-экранированными. Заменяем обе формы.
    private static func replacePlaceholder(_ name: String, with value: String, in request: inout RequestData) {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
        let replaced = request.url.absoluteString
            .replacingOccurrences(of: "%7B\(name)%7D", with: encoded)
            .replacingOccurrences(of: "%7b\(name)%7d", with: encoded)
            .replacingOccurrences(of: "{\(name)}", with: encoded)

        if let url = URL(string: replaced) { request.url = url }
    }
}
