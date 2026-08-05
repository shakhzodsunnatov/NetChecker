import Foundation

/// Шаг сценария — один запрос вместе со своими связями
public struct FlowStep: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String

    /// Запрос, снятый с пойманного трафика
    public var request: RequestData

    /// Шаги, завершения которых он ждёт.
    ///
    /// Пустой список означает старт сразу — вместе со всеми такими же.
    /// Отдельного переключателя «параллельно / последовательно» нет:
    /// порядок целиком задаётся связями.
    public var dependsOn: [UUID]

    /// Условие выполнения. Ложное — шаг пропускается, но не считается ошибкой
    public var condition: FlowCondition?

    /// Что извлечь из ответа
    public var outputs: [FlowOutput]

    /// Что подставить в запрос
    public var inputs: [FlowInput]

    /// Ожидаемый статус ответа. Несовпадение — ошибка шага
    public var expectedStatusCode: Int?

    /// Пауза перед запуском, секунды
    public var delay: TimeInterval

    public init(
        id: UUID = UUID(),
        name: String,
        request: RequestData,
        dependsOn: [UUID] = [],
        condition: FlowCondition? = nil,
        outputs: [FlowOutput] = [],
        inputs: [FlowInput] = [],
        expectedStatusCode: Int? = nil,
        delay: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.request = request
        self.dependsOn = dependsOn
        self.condition = condition
        self.outputs = outputs
        self.inputs = inputs
        self.expectedStatusCode = expectedStatusCode
        self.delay = max(0, delay)
    }
}
