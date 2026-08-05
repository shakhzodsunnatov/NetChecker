import Foundation

/// Перенос сценария между устройствами.
///
/// Это и есть замена нынешнему обходному пути: вместо сборки мок-сцены в коде
/// и выкладки в TestFlight ради бэкендера — файл, который он открывает у себя.
public enum FlowExporter {

    /// Заглушка вместо секрета при экспорте
    public static let redaction = "***REDACTED***"

    /// Сериализовать сценарий для отправки.
    ///
    /// Значения чувствительных заголовков заменяются заглушкой: файл уходит
    /// другому человеку, и живой токен уходить вместе с ним не должен.
    public static func export(_ flow: Flow) -> Data {
        var sanitised = flow
        let sensitive = Set(HeaderFormatter.sensitiveHeaders.map { $0.lowercased() })

        sanitised.steps = flow.steps.map { step in
            var copy = step
            copy.request.headers = step.request.headers.reduce(into: [:]) { result, item in
                result[item.key] = sensitive.contains(item.key.lowercased()) ? redaction : item.value
            }
            return copy
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(sanitised)) ?? Data()
    }

    public static func load(_ data: Data) throws -> Flow {
        try JSONDecoder().decode(Flow.self, from: data)
    }
}
