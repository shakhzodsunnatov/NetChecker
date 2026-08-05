import Foundation

/// Поле JSON с готовым путём и значением
public struct FlowJSONField: Identifiable, Sendable, Hashable {
    public var id: String { path }

    /// Путь для `FlowValueSource.jsonPath`, сегменты через точку
    public let path: String

    /// Значение в текстовом виде — то, что подставится
    public let value: String

    /// Глубина вложенности, для отступа в списке
    public let depth: Int

    public init(path: String, value: String, depth: Int) {
        self.path = path
        self.value = value
        self.depth = depth
    }

    /// Последний сегмент — подходит как имя значения по умолчанию
    public var suggestedName: String {
        path.split(separator: ".").last.map(String.init) ?? path
    }
}

/// Разбор JSON в плоский список полей.
///
/// Нужен, чтобы значение выбиралось из настоящего ответа, а не вводилось
/// путём вручную: опечатка в пути видна только падением шага, а по списку
/// с реальными значениями ошибиться нечем.
public enum FlowJSONFields {

    /// Максимум элементов массива, попадающих в список.
    /// Иначе ответ на тысячу записей превращает выбор в бесконечную простыню.
    public static let maxArrayItems = 5

    /// Плоский список полей JSON-тела
    public static func fields(in data: Data?) -> [FlowJSONField] {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        var result: [FlowJSONField] = []
        walk(root, path: "", depth: 0, into: &result)
        return result
    }

    /// Имена полей верхнего уровня — для подстановки в тело запроса
    public static func topLevelKeys(in data: Data?) -> [String] {
        guard let data = data,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        return object.keys.sorted()
    }

    private static func walk(_ value: Any, path: String, depth: Int, into result: inout [FlowJSONField]) {
        switch value {
        case let dictionary as [String: Any]:
            for key in dictionary.keys.sorted() {
                let child = path.isEmpty ? key : "\(path).\(key)"
                walk(dictionary[key] as Any, path: child, depth: depth, into: &result)
            }

        case let array as [Any]:
            // Элементы массива не адресуются текущим форматом пути,
            // но показать их полезно — видно, что вообще пришло
            for (index, item) in array.prefix(maxArrayItems).enumerated() {
                walk(item, path: "\(path)[\(index)]", depth: depth + 1, into: &result)
            }

        default:
            result.append(
                FlowJSONField(path: path, value: describe(value), depth: depth)
            )
        }
    }

    private static func describe(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            if number.doubleValue == number.doubleValue.rounded() {
                return String(number.intValue)
            }
            return String(number.doubleValue)
        case is NSNull:
            return "null"
        default:
            return String(describing: value)
        }
    }

    /// Путь адресуем нашим извлечением — индексы массивов пока не поддержаны
    public static func isSelectable(_ field: FlowJSONField) -> Bool {
        !field.path.contains("[")
    }
}
