import Foundation

/// Валидатор схем — проверяет ожидания vs реальность в MCP-записях
public enum MCPSchemaValidator {

    /// Валидировать MCP-запись и заполнить нарушения
    public static func validate(_ entry: MCPLogEntry) -> MCPLogEntry {
        guard var expectations = entry.expectations else {
            return entry
        }

        var violations: [MCPViolation] = []

        // Валидация для сетевых вызовов
        if case .networkCall(let net) = entry.payload {
            violations.append(contentsOf: validateNetworkCall(net, expectations: expectations))
        }

        // Валидация для тестов
        if case .testResult(let test) = entry.payload {
            violations.append(contentsOf: validateTestResult(test))
        }

        // Валидация для команд
        if case .commandResult(let cmd) = entry.payload {
            violations.append(contentsOf: validateCommandResult(cmd))
        }

        expectations.violations = violations.isEmpty ? nil : violations

        var result = entry
        result.expectations = expectations

        // Повышаем severity если есть критические нарушения
        if violations.contains(where: { $0.severity >= .error }) {
            result.severity = max(result.severity, .error)
        } else if violations.contains(where: { $0.severity >= .warning }) {
            result.severity = max(result.severity, .warning)
        }

        return result
    }

    // MARK: - Валидация сетевых вызовов

    private static func validateNetworkCall(
        _ payload: MCPNetworkPayload,
        expectations: MCPExpectations
    ) -> [MCPViolation] {
        var violations: [MCPViolation] = []

        // Проверка статус-кода
        if let expectedStatus = expectations.expectedStatusCode,
           let actualStatus = payload.statusCode,
           expectedStatus != actualStatus {
            violations.append(MCPViolation(
                field: "statusCode",
                expected: "\(expectedStatus)",
                actual: "\(actualStatus)",
                severity: actualStatus >= 500 ? .error : .warning
            ))
        }

        // Проверка полей ответа
        if let expectedFields = expectations.expectedFields,
           let responseBody = payload.responseBody {
            let missingFields = findMissingFields(expectedFields, in: responseBody)
            for field in missingFields {
                violations.append(MCPViolation(
                    field: field,
                    expected: "present",
                    actual: "missing",
                    severity: .warning
                ))
            }
        }

        // Проверка типа контента
        if let expectedContentType = expectations.expectedContentType,
           let responseHeaders = payload.responseHeaders {
            let actualContentType = responseHeaders["Content-Type"]
                ?? responseHeaders["content-type"]
                ?? "unknown"
            if !actualContentType.contains(expectedContentType) {
                violations.append(MCPViolation(
                    field: "contentType",
                    expected: expectedContentType,
                    actual: actualContentType,
                    severity: .warning
                ))
            }
        }

        return violations
    }

    // MARK: - Валидация тестов

    private static func validateTestResult(_ payload: MCPTestPayload) -> [MCPViolation] {
        var violations: [MCPViolation] = []

        if !payload.passed {
            violations.append(MCPViolation(
                field: "testPassed",
                expected: "true",
                actual: "false",
                severity: .error
            ))
        }

        return violations
    }

    // MARK: - Валидация команд

    private static func validateCommandResult(_ payload: MCPCommandPayload) -> [MCPViolation] {
        var violations: [MCPViolation] = []

        if let exitCode = payload.exitCode, exitCode != 0 {
            violations.append(MCPViolation(
                field: "exitCode",
                expected: "0",
                actual: "\(exitCode)",
                severity: .error
            ))
        }

        return violations
    }

    // MARK: - Поиск отсутствующих полей в JSON

    private static func findMissingFields(_ fields: [String], in jsonString: String) -> [String] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fields // Если JSON невалиден — все поля "отсутствуют"
        }

        return fields.filter { field in
            // Поддерживаем вложенные пути: "user.name"
            let parts = field.split(separator: ".")
            var current: Any = json

            for part in parts {
                guard let dict = current as? [String: Any],
                      let value = dict[String(part)] else {
                    return true // Поле отсутствует
                }
                current = value
            }

            return false // Поле найдено
        }
    }
}
