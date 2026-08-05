import Foundation

/// Ошибка выполнения шага
public enum FlowRunError: Error, Equatable, Sendable {
    /// Значение не найдено среди собранных предыдущими шагами
    case missingValue(String)
    /// Ответ не совпал с ожидаемым статусом
    case unexpectedStatus(expected: Int, actual: Int)
    /// Сетевая ошибка
    case transport(String)

    public var message: String {
        switch self {
        case .missingValue(let name):
            return "Значение «\(name)» отсутствует в ответах предыдущих шагов"
        case .unexpectedStatus(let expected, let actual):
            return "Ожидался статус \(expected), получен \(actual)"
        case .transport(let text):
            return text
        }
    }
}

/// Состояние шага в прогоне
public enum FlowStepState: Codable, Sendable, Hashable {
    case pending
    case running
    case succeeded
    case failed(String)
    /// Условие оказалось ложным — это не ошибка
    case skipped
    /// Прогон остановился раньше, до этого шага дело не дошло
    case notRun
}

/// Итог одного шага
public struct FlowStepOutcome: Identifiable, Sendable, Hashable {
    public var id: UUID { stepId }
    public let stepId: UUID
    public var state: FlowStepState
    public var statusCode: Int?
    public var duration: TimeInterval
    /// Что подставилось в запрос — ломается обычно именно это,
    /// а не сам запрос
    public var substitutions: [String: String]

    /// Запрос в том виде, в каком он ушёл, — уже с подстановками.
    /// Без него непонятно, что именно отправилось.
    public var sentRequest: RequestData?

    /// Ответ целиком. Нужен не для показа: по нему выбираются значения
    /// для следующих шагов — вместо ручного ввода JSON-пути
    public var response: ResponseData?

    public init(
        stepId: UUID,
        state: FlowStepState = .pending,
        statusCode: Int? = nil,
        duration: TimeInterval = 0,
        substitutions: [String: String] = [:],
        sentRequest: RequestData? = nil,
        response: ResponseData? = nil
    ) {
        self.stepId = stepId
        self.state = state
        self.statusCode = statusCode
        self.duration = duration
        self.substitutions = substitutions
        self.sentRequest = sentRequest
        self.response = response
    }
}

/// Значения, собранные за прогон.
///
/// Переживает падение шага: именно поэтому «Повторить с шага N»
/// не заставляет логиниться заново.
public struct FlowRunContext: Sendable {
    public private(set) var values: [String: String] = [:]

    /// Выходы, которых не оказалось в ответе
    public private(set) var unresolvedOutputs: [String] = []

    public init() {}

    /// Записать выходы шага
    public mutating func record(_ response: ResponseData, for step: FlowStep) {
        for output in step.outputs {
            if let value = FlowValueExtractor.extract(output, from: response) {
                values[output.name] = value
            } else if !unresolvedOutputs.contains(output.name) {
                unresolvedOutputs.append(output.name)
            }
        }
    }

    /// Собрать запрос шага с подстановками.
    ///
    /// Бросает, если значения нет: подставить пустую строку значит отправить
    /// заведомо неверный запрос и получить непонятную ошибку от сервера
    /// вместо ясной «значения нет».
    public func prepared(_ step: FlowStep) throws -> RequestData {
        var request = step.request

        for input in step.inputs {
            guard let value = values[input.name] else {
                throw FlowRunError.missingValue(input.name)
            }
            FlowValueInjector.apply(input, value: value, to: &request)
        }

        return request
    }

    /// Подстановки шага для показа в разборе
    public func substitutions(for step: FlowStep) -> [String: String] {
        var result: [String: String] = [:]
        for input in step.inputs {
            result[input.name] = values[input.name] ?? "—"
        }
        return result
    }

    public mutating func reset() {
        values.removeAll()
        unresolvedOutputs.removeAll()
    }
}
