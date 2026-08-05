import Foundation

/// Оператор сравнения в условии шага
public enum FlowConditionOperator: String, Codable, Sendable, CaseIterable {
    case equals
    case notEquals
    case greaterThan
    case lessThan
    case isTrue
    case isFalse
    case exists
    case isEmpty

    public var title: String {
        switch self {
        case .equals: return "равно"
        case .notEquals: return "не равно"
        case .greaterThan: return "больше"
        case .lessThan: return "меньше"
        case .isTrue: return "истина"
        case .isFalse: return "ложь"
        case .exists: return "существует"
        case .isEmpty: return "пусто"
        }
    }

    /// Оператору нужен правый операнд
    public var needsOperand: Bool {
        switch self {
        case .equals, .notEquals, .greaterThan, .lessThan: return true
        case .isTrue, .isFalse, .exists, .isEmpty: return false
        }
    }
}

/// Условие выполнения шага.
///
/// Хранится на шаге, а рисуется на входящей связи: хранить проще — не нужно
/// заводить отдельную сущность «ребро с логикой», — а на связи читается
/// как развилка. Ложное условие означает пропуск, а не ошибку.
///
/// If / else получается из двух шагов с общим родителем: у одного условие,
/// у другого противоположное. Выполнится ровно один.
public struct FlowCondition: Codable, Sendable, Hashable {
    /// Имя значения, собранного предыдущими шагами
    public var valueName: String
    public var `operator`: FlowConditionOperator
    public var operand: String?

    public init(valueName: String, operator: FlowConditionOperator, operand: String? = nil) {
        self.valueName = valueName
        self.operator = `operator`
        self.operand = operand
    }

    /// Подпись для связи в графе
    public var summary: String {
        guard `operator`.needsOperand, let operand = operand else {
            return "\(valueName) \(`operator`.title)"
        }
        return "\(valueName) \(`operator`.title) \(operand)"
    }

    public func evaluate(values: [String: String]) -> Bool {
        // Эти два оператора осмысленны и для отсутствующего значения
        switch `operator` {
        case .exists:
            return values[valueName] != nil
        case .isEmpty:
            return values[valueName]?.isEmpty ?? true
        default:
            break
        }

        // Остальные без значения всегда ложны: трактовать отсутствие
        // как пустую строку значило бы молча уводить прогон не в ту ветку
        guard let value = values[valueName] else { return false }

        switch `operator` {
        case .equals:
            return value == operand
        case .notEquals:
            return value != operand
        case .isTrue:
            return value.lowercased() == "true"
        case .isFalse:
            return value.lowercased() == "false"
        case .greaterThan, .lessThan:
            guard let left = Double(value), let right = operand.flatMap(Double.init) else { return false }
            return `operator` == .greaterThan ? left > right : left < right
        case .exists, .isEmpty:
            return false
        }
    }
}
