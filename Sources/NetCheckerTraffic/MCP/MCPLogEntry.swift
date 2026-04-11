import Foundation

/// Структурированная запись от AI-инструмента
public struct MCPLogEntry: Codable, Sendable {
    /// Уникальный ID записи
    public var id: UUID

    /// Временная метка
    public var timestamp: Date

    /// Тип операции
    public var operationType: MCPOperationType

    /// Информация об источнике (AI-инструмент)
    public var source: MCPSourceInfo

    /// Контекст потока (к какой задаче относится)
    public var flowContext: MCPFlowContext?

    /// Данные операции
    public var payload: MCPPayload

    /// Ожидания (для валидации)
    public var expectations: MCPExpectations?

    /// Серьёзность
    public var severity: MCPSeverity

    /// Пользовательские теги
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        operationType: MCPOperationType,
        source: MCPSourceInfo,
        flowContext: MCPFlowContext? = nil,
        payload: MCPPayload,
        expectations: MCPExpectations? = nil,
        severity: MCPSeverity = .info,
        tags: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operationType = operationType
        self.source = source
        self.flowContext = flowContext
        self.payload = payload
        self.expectations = expectations
        self.severity = severity
        self.tags = tags
    }
}

// MARK: - Источник

/// Информация об AI-инструменте
public struct MCPSourceInfo: Codable, Sendable, Hashable {
    /// Название инструмента
    public var toolName: String

    /// Версия инструмента
    public var toolVersion: String?

    /// ID сессии
    public var sessionId: String

    /// ID клиента
    public var clientId: String?

    public init(
        toolName: String,
        toolVersion: String? = nil,
        sessionId: String,
        clientId: String? = nil
    ) {
        self.toolName = toolName
        self.toolVersion = toolVersion
        self.sessionId = sessionId
        self.clientId = clientId
    }
}

// MARK: - Контекст потока

/// Контекст для группировки связанных операций
public struct MCPFlowContext: Codable, Sendable, Hashable {
    /// ID потока
    public var flowId: UUID

    /// Название потока / задачи
    public var flowName: String

    /// Описание
    public var flowDescription: String?

    /// Порядковый номер в потоке
    public var sequenceNumber: Int

    /// Родительский поток (для вложенности)
    public var parentFlowId: UUID?

    public init(
        flowId: UUID,
        flowName: String,
        flowDescription: String? = nil,
        sequenceNumber: Int = 0,
        parentFlowId: UUID? = nil
    ) {
        self.flowId = flowId
        self.flowName = flowName
        self.flowDescription = flowDescription
        self.sequenceNumber = sequenceNumber
        self.parentFlowId = parentFlowId
    }
}

// MARK: - Payload

/// Данные операции (зависят от типа)
public enum MCPPayload: Codable, Sendable {
    /// Сетевой вызов
    case networkCall(MCPNetworkPayload)

    /// Файловая операция
    case fileOperation(MCPFilePayload)

    /// Результат команды
    case commandResult(MCPCommandPayload)

    /// Результат теста
    case testResult(MCPTestPayload)

    /// Произвольные данные
    case raw(String)

    // MARK: - Custom Codable

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "networkCall":
            let data = try container.decode(MCPNetworkPayload.self, forKey: .data)
            self = .networkCall(data)
        case "fileOperation":
            let data = try container.decode(MCPFilePayload.self, forKey: .data)
            self = .fileOperation(data)
        case "commandResult":
            let data = try container.decode(MCPCommandPayload.self, forKey: .data)
            self = .commandResult(data)
        case "testResult":
            let data = try container.decode(MCPTestPayload.self, forKey: .data)
            self = .testResult(data)
        default:
            let data = try container.decodeIfPresent(String.self, forKey: .data) ?? ""
            self = .raw(data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .networkCall(let data):
            try container.encode("networkCall", forKey: .type)
            try container.encode(data, forKey: .data)
        case .fileOperation(let data):
            try container.encode("fileOperation", forKey: .type)
            try container.encode(data, forKey: .data)
        case .commandResult(let data):
            try container.encode("commandResult", forKey: .type)
            try container.encode(data, forKey: .data)
        case .testResult(let data):
            try container.encode("testResult", forKey: .type)
            try container.encode(data, forKey: .data)
        case .raw(let data):
            try container.encode("raw", forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }
}

// MARK: - Payload-варианты

/// Данные сетевого вызова
public struct MCPNetworkPayload: Codable, Sendable {
    public var url: String
    public var method: String
    public var statusCode: Int?
    public var requestHeaders: [String: String]?
    public var requestBody: String?
    public var responseHeaders: [String: String]?
    public var responseBody: String?
    public var duration: TimeInterval?

    public init(
        url: String,
        method: String = "GET",
        statusCode: Int? = nil,
        requestHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.statusCode = statusCode
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.duration = duration
    }
}

/// Данные файловой операции
public struct MCPFilePayload: Codable, Sendable {
    public var filePath: String
    public var operation: String // "read", "write", "delete"
    public var contentPreview: String?
    public var lineCount: Int?
    public var sizeBytes: Int64?

    public init(
        filePath: String,
        operation: String,
        contentPreview: String? = nil,
        lineCount: Int? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.filePath = filePath
        self.operation = operation
        self.contentPreview = contentPreview
        self.lineCount = lineCount
        self.sizeBytes = sizeBytes
    }
}

/// Данные результата команды
public struct MCPCommandPayload: Codable, Sendable {
    public var command: String
    public var exitCode: Int?
    public var stdout: String?
    public var stderr: String?
    public var duration: TimeInterval?

    public init(
        command: String,
        exitCode: Int? = nil,
        stdout: String? = nil,
        stderr: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.duration = duration
    }
}

/// Данные результата теста
public struct MCPTestPayload: Codable, Sendable {
    public var testName: String
    public var testSuite: String?
    public var passed: Bool
    public var errorMessage: String?
    public var duration: TimeInterval?
    public var assertions: Int?

    public init(
        testName: String,
        testSuite: String? = nil,
        passed: Bool,
        errorMessage: String? = nil,
        duration: TimeInterval? = nil,
        assertions: Int? = nil
    ) {
        self.testName = testName
        self.testSuite = testSuite
        self.passed = passed
        self.errorMessage = errorMessage
        self.duration = duration
        self.assertions = assertions
    }
}

// MARK: - Ожидания и нарушения

/// Ожидания для валидации
public struct MCPExpectations: Codable, Sendable {
    /// Ожидаемый статус-код
    public var expectedStatusCode: Int?

    /// Ожидаемые поля в ответе
    public var expectedFields: [String]?

    /// Ожидаемый тип контента
    public var expectedContentType: String?

    /// Нарушения (заполняются валидатором)
    public var violations: [MCPViolation]?

    /// Совпали ли ожидания
    public var met: Bool { violations?.isEmpty ?? true }

    public init(
        expectedStatusCode: Int? = nil,
        expectedFields: [String]? = nil,
        expectedContentType: String? = nil,
        violations: [MCPViolation]? = nil
    ) {
        self.expectedStatusCode = expectedStatusCode
        self.expectedFields = expectedFields
        self.expectedContentType = expectedContentType
        self.violations = violations
    }
}

/// Нарушение ожидания
public struct MCPViolation: Codable, Sendable, Hashable {
    /// Поле с нарушением
    public var field: String

    /// Ожидаемое значение
    public var expected: String

    /// Фактическое значение
    public var actual: String

    /// Серьёзность
    public var severity: MCPSeverity

    public init(
        field: String,
        expected: String,
        actual: String,
        severity: MCPSeverity = .warning
    ) {
        self.field = field
        self.expected = expected
        self.actual = actual
        self.severity = severity
    }
}
