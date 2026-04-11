import Foundation

/// Роутер MCP-запросов — маршрутизирует HTTP-запросы к обработчикам
@MainActor
final class MCPRouter {

    /// Максимальный размер payload (по умолчанию 5 MB)
    var maxPayloadSize: Int = 5 * 1024 * 1024

    /// JSON-декодер с ISO8601 датами (поддерживает формат с миллисекундами и без)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let withMs = ISO8601DateFormatter()
            withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withMs.date(from: str) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO8601 date, got: \(str)"
            )
        }
        return d
    }()

    // MARK: - Роутинг

    /// Обработать входящий запрос
    func handle(_ request: MCPHTTPRequest) async -> MCPHTTPResponse {
        // CORS preflight
        if request.method == "OPTIONS" {
            return .corsOK()
        }

        // Проверка размера payload
        if let body = request.body, body.count > maxPayloadSize {
            return .error("Payload too large (max \(maxPayloadSize) bytes)", statusCode: 413)
        }

        // Роутинг по path + method (cleanPath убирает query string)
        let path = request.cleanPath
        switch (request.method, path) {
        case ("POST", "/log"):
            return handleLogEntry(request)

        case ("POST", "/log/batch"):
            return handleBatchLog(request)

        case ("POST", "/flow/start"):
            return handleFlowStart(request)

        case ("POST", "/flow/end"):
            return handleFlowEnd(request)

        case ("GET", "/status"):
            return handleStatus()

        case ("GET", "/flows"):
            return handleListFlows()

        case ("GET", "/records"):
            return handleListRecords(request)

        case ("DELETE", "/records"):
            return handleClearRecords()

        case ("GET", _) where path.hasPrefix("/records/"):
            let id = String(path.dropFirst("/records/".count))
            return handleGetRecord(id: id)

        case ("POST", "/execute"):
            return await handleExecute(request)

        case ("GET", "/triggers"):
            return handleListTriggers()

        case ("POST", "/trigger"):
            return await handleTrigger(request)

        case ("GET", "/"):
            return handleRoot()

        default:
            return .error("Not found: \(request.method) \(path)", statusCode: 404)
        }
    }

    // MARK: - Обработчики

    /// Обработка одной записи
    private func handleLogEntry(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        let entry: MCPLogEntry
        do {
            entry = try decoder.decode(MCPLogEntry.self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        // Валидация ожиданий
        let validatedEntry = MCPSchemaValidator.validate(entry)

        // Трекинг потока
        if let flowContext = validatedEntry.flowContext {
            MCPFlowTracker.shared.addEntry(
                flowId: flowContext.flowId,
                entry: validatedEntry
            )
        }

        // Конвертация в TrafficRecord и сохранение
        let record = Self.convertToTrafficRecord(validatedEntry)
        TrafficStore.shared.add(record)

        return .json([
            "status": "ok",
            "recordId": record.id.uuidString,
            "violations": validatedEntry.expectations?.violations?.count ?? 0
        ])
    }

    /// Обработка пачки записей
    private func handleBatchLog(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        let entries: [MCPLogEntry]
        do {
            entries = try decoder.decode([MCPLogEntry].self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        var recordIds: [String] = []
        var totalViolations = 0

        for entry in entries {
            let validatedEntry = MCPSchemaValidator.validate(entry)

            if let flowContext = validatedEntry.flowContext {
                MCPFlowTracker.shared.addEntry(
                    flowId: flowContext.flowId,
                    entry: validatedEntry
                )
            }

            let record = Self.convertToTrafficRecord(validatedEntry)
            TrafficStore.shared.add(record)
            recordIds.append(record.id.uuidString)
            totalViolations += validatedEntry.expectations?.violations?.count ?? 0
        }

        return .json([
            "status": "ok",
            "count": entries.count,
            "recordIds": recordIds,
            "totalViolations": totalViolations
        ])
    }

    /// Начать новый поток
    private func handleFlowStart(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        struct FlowStartRequest: Decodable {
            let flowId: String
            let flowName: String
            let flowDescription: String?
            let source: MCPSourceInfo
        }

        let req: FlowStartRequest
        do {
            req = try decoder.decode(FlowStartRequest.self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        let flowUUID = UUID(uuidString: req.flowId) ?? UUID.deterministicUUID(from: req.flowId)
        MCPFlowTracker.shared.startFlow(
            id: flowUUID,
            name: req.flowName,
            description: req.flowDescription,
            source: req.source
        )

        return .json([
            "status": "ok",
            "flowId": flowUUID.uuidString
        ])
    }

    /// Завершить поток
    private func handleFlowEnd(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        struct FlowEndRequest: Decodable {
            let flowId: String
            let status: String?
        }

        let req: FlowEndRequest
        do {
            req = try decoder.decode(FlowEndRequest.self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        let flowUUID = UUID(uuidString: req.flowId) ?? UUID.deterministicUUID(from: req.flowId)
        guard let flow = MCPFlowTracker.shared.endFlow(id: flowUUID) else {
            return .error("Flow not found: \(req.flowId)", statusCode: 404)
        }

        return .json([
            "status": "ok",
            "flowId": flow.id.uuidString,
            "entriesCount": flow.entries.count,
            "violations": flow.violations.count
        ])
    }

    /// Статус сервера
    private func handleStatus() -> MCPHTTPResponse {
        let tracker = MCPFlowTracker.shared
        let store = TrafficStore.shared

        return .json([
            "running": true,
            "totalRecords": store.count,
            "activeFlows": tracker.activeFlows.count,
            "completedFlows": tracker.completedFlows.count
        ])
    }

    /// Список потоков
    private func handleListFlows() -> MCPHTTPResponse {
        let tracker = MCPFlowTracker.shared

        let flows: [[String: Any]] = (tracker.activeFlows + tracker.completedFlows).map { flow in
            [
                "id": flow.id.uuidString,
                "name": flow.name,
                "status": flow.status.rawValue,
                "entriesCount": flow.entries.count,
                "violations": flow.violations.count
            ]
        }

        return .json(["flows": flows])
    }

    /// Список записей трафика (для AI-инструментов)
    private func handleListRecords(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        let store = TrafficStore.shared

        // Параметры: ?limit=50&filter=mcp / all / errors
        let limit = request.queryInt("limit") ?? 50
        let filter = request.queryString("filter") ?? "all"

        let allRecords = store.lastRecords(min(limit, 200))
        let filtered: [TrafficRecord]
        switch filter {
        case "mcp":
            filtered = allRecords.filter { $0.metadata.mcpSource != nil }
        case "errors":
            filtered = allRecords.filter {
                if case .failed = $0.state { return true }
                return false
            }
        default:
            filtered = allRecords
        }

        let records = filtered.map { Self.summarizeRecord($0) }
        return .json([
            "total": store.count,
            "returned": records.count,
            "filter": filter,
            "records": records
        ])
    }

    /// Детали одной записи по ID
    private func handleGetRecord(id: String) -> MCPHTTPResponse {
        guard let uuid = UUID(uuidString: id),
              let record = TrafficStore.shared.record(for: uuid) else {
            return .error("Record not found: \(id)", statusCode: 404)
        }
        return .json(["record": Self.detailRecord(record)])
    }

    /// Очистить все записи
    private func handleClearRecords() -> MCPHTTPResponse {
        let count = TrafficStore.shared.count
        TrafficStore.shared.clear()
        return .json(["status": "ok", "cleared": count])
    }

    /// Корневой эндпоинт
    private func handleRoot() -> MCPHTTPResponse {
        .json([
            "service": "NetChecker MCP Server",
            "version": "1.0",
            "endpoints": [
                "POST /log",
                "POST /log/batch",
                "POST /flow/start",
                "POST /flow/end",
                "POST /execute",
                "POST /trigger",
                "GET /status",
                "GET /flows",
                "GET /records",
                "GET /records/{id}",
                "GET /triggers",
                "DELETE /records"
            ]
        ])
    }

    // MARK: - Execute: AI отправляет HTTP-запрос через iOS

    /// Выполнить HTTP-запрос через URLSession iOS-устройства
    private func handleExecute(_ request: MCPHTTPRequest) async -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        struct ExecuteRequest: Decodable {
            let url: String
            let method: String?
            let headers: [String: String]?
            let body: String?
            let timeoutSeconds: Double?
        }

        let req: ExecuteRequest
        do {
            req = try decoder.decode(ExecuteRequest.self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        guard let url = URL(string: req.url) else {
            return .error("Invalid URL: \(req.url)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = (req.method ?? "GET").uppercased()
        urlRequest.timeoutInterval = req.timeoutSeconds ?? 30
        if let headers = req.headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let bodyStr = req.body {
            urlRequest.httpBody = bodyStr.data(using: .utf8)
        }

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let duration = Date().timeIntervalSince(start)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .error("Not an HTTP response")
            }

            var result: [String: Any] = [
                "statusCode": httpResponse.statusCode,
                "duration": round(duration * 1000) / 1000,
                "headers": Dictionary(uniqueKeysWithValues:
                    httpResponse.allHeaderFields.map { ("\($0.key)", "\($0.value)") }
                ),
                "bodySize": data.count
            ]

            // Тело ответа — текст или base64
            if let text = String(data: data, encoding: .utf8) {
                // Обрезать до 100KB для MCP-транспорта
                if text.count > 100_000 {
                    result["body"] = String(text.prefix(100_000)) + "\n... (truncated)"
                } else {
                    result["body"] = text
                }
            } else {
                result["body"] = "(binary \(data.count) bytes)"
            }

            return .json(["status": "ok", "response": result])

        } catch {
            let duration = Date().timeIntervalSince(start)
            return .json([
                "status": "error",
                "error": error.localizedDescription,
                "duration": round(duration * 1000) / 1000
            ])
        }
    }

    // MARK: - Triggers: AI управляет действиями приложения

    /// Список доступных триггеров
    private func handleListTriggers() -> MCPHTTPResponse {
        let triggers = MCPActionRegistry.shared.allActions.map { action -> [String: Any] in
            var item: [String: Any] = [
                "tag": action.tag,
                "name": action.name,
                "description": action.actionDescription
            ]
            if !action.parameterNames.isEmpty {
                item["parameters"] = action.parameterNames
            }
            return item
        }
        return .json(["triggers": triggers, "count": triggers.count])
    }

    /// Выполнить триггер по тегу
    private func handleTrigger(_ request: MCPHTTPRequest) async -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        struct TriggerRequest: Decodable {
            let tag: String
            let params: [String: String]?
        }

        let req: TriggerRequest
        do {
            req = try decoder.decode(TriggerRequest.self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        guard let action = MCPActionRegistry.shared.action(for: req.tag) else {
            let available = MCPActionRegistry.shared.allActions.map(\.tag)
            return .error("Unknown trigger: '\(req.tag)'. Available: \(available.joined(separator: ", "))", statusCode: 404)
        }

        do {
            let result = try await action.execute(params: req.params ?? [:])
            return .json([
                "status": "ok",
                "tag": req.tag,
                "result": result
            ])
        } catch {
            return .json([
                "status": "error",
                "tag": req.tag,
                "error": error.localizedDescription
            ])
        }
    }

    // MARK: - Сериализация TrafficRecord

    /// Краткое представление записи для списка
    private static func summarizeRecord(_ r: TrafficRecord) -> [String: Any] {
        var item: [String: Any] = [
            "id": r.id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: r.timestamp),
            "url": r.request.url.absoluteString,
            "method": r.request.method.rawValue,
            "duration": r.duration
        ]
        if let resp = r.response {
            item["statusCode"] = resp.statusCode
        }
        switch r.state {
        case .completed: item["state"] = "completed"
        case .failed(let e): item["state"] = "failed"; item["error"] = e.localizedDescription
        case .pending: item["state"] = "pending"
        default: item["state"] = "unknown"
        }
        if let mcp = r.metadata.mcpSource {
            item["mcpTool"] = mcp.toolName
        }
        if !r.metadata.tags.isEmpty {
            item["tags"] = r.metadata.tags
        }
        return item
    }

    /// Детальное представление записи
    private static func detailRecord(_ r: TrafficRecord) -> [String: Any] {
        var item = summarizeRecord(r)
        item["requestHeaders"] = r.request.headers
        if let body = r.request.body,
           let text = String(data: body, encoding: .utf8) {
            item["requestBody"] = text
        }
        if let resp = r.response {
            item["responseHeaders"] = resp.headers
            if let body = resp.body,
               let text = String(data: body, encoding: .utf8) {
                item["responseBody"] = text
            }
        }
        return item
    }

    // MARK: - Конвертация MCPLogEntry → TrafficRecord

    /// Конвертировать MCP-запись в TrafficRecord для TrafficStore
    static func convertToTrafficRecord(_ entry: MCPLogEntry) -> TrafficRecord {
        let request: RequestData
        let response: ResponseData?
        let duration: TimeInterval

        switch entry.payload {
        case .networkCall(let net):
            let url = URL(string: net.url) ?? URL(string: "mcp://\(entry.source.toolName)/unknown")!
            request = RequestData(
                url: url,
                method: HTTPMethod(rawValue: net.method.uppercased()) ?? .get,
                headers: net.requestHeaders ?? [:],
                body: net.requestBody?.data(using: .utf8)
            )
            if let statusCode = net.statusCode {
                response = ResponseData(
                    statusCode: statusCode,
                    headers: net.responseHeaders ?? [:],
                    body: net.responseBody?.data(using: .utf8)
                )
            } else {
                response = nil
            }
            duration = net.duration ?? 0

        case .fileOperation(let file):
            let url = URL(string: "mcp://\(entry.source.toolName)/file/\(file.operation)")!
            request = RequestData(
                url: url,
                method: file.operation == "read" ? .get : .post,
                headers: ["X-MCP-FilePath": file.filePath],
                body: file.contentPreview?.data(using: .utf8)
            )
            response = ResponseData(
                statusCode: 200,
                headers: [:],
                body: "Lines: \(file.lineCount ?? 0), Size: \(file.sizeBytes ?? 0)".data(using: .utf8)
            )
            duration = 0

        case .commandResult(let cmd):
            let url = URL(string: "mcp://\(entry.source.toolName)/command")!
            request = RequestData(
                url: url,
                method: .post,
                headers: ["X-MCP-Command": cmd.command],
                body: cmd.command.data(using: .utf8)
            )
            let exitCode = cmd.exitCode ?? 0
            response = ResponseData(
                statusCode: exitCode == 0 ? 200 : 500,
                headers: ["X-Exit-Code": "\(exitCode)"],
                body: (cmd.stdout ?? cmd.stderr ?? "").data(using: .utf8)
            )
            duration = cmd.duration ?? 0

        case .testResult(let test):
            let url = URL(string: "mcp://\(entry.source.toolName)/test/\(test.testName)")!
            request = RequestData(
                url: url,
                method: .get,
                headers: ["X-MCP-TestSuite": test.testSuite ?? ""],
                body: nil
            )
            response = ResponseData(
                statusCode: test.passed ? 200 : 500,
                headers: ["X-Test-Passed": "\(test.passed)"],
                body: test.errorMessage?.data(using: .utf8)
            )
            duration = test.duration ?? 0

        case .raw(let text):
            let url = URL(string: "mcp://\(entry.source.toolName)/raw")!
            request = RequestData(
                url: url,
                method: .post,
                headers: [:],
                body: text.data(using: .utf8)
            )
            response = nil
            duration = 0
        }

        // Собираем теги
        var tags = entry.tags
        tags.append("mcp")
        tags.append(entry.operationType.rawValue)
        tags.append(entry.source.toolName)
        if let violations = entry.expectations?.violations {
            for v in violations {
                tags.append("violation:\(v.field)")
            }
        }

        let state: TrafficRecordState
        if let violations = entry.expectations?.violations, !violations.isEmpty,
           violations.contains(where: { $0.severity >= .error }) {
            state = .failed(TrafficError(
                code: -1,
                domain: "mcp.violation",
                localizedDescription: "Schema violations detected"
            ))
        } else if response != nil {
            state = .completed
        } else {
            state = .pending
        }

        var metadata = TrafficMetadata(from: request.url)
        metadata.tags = tags
        metadata.sdkSource = entry.source.toolName
        metadata.mcpSource = entry.source

        return TrafficRecord(
            id: entry.id,
            timestamp: entry.timestamp,
            duration: duration,
            state: state,
            request: request,
            response: response,
            metadata: metadata
        )
    }
}
