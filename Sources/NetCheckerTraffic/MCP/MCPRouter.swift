import Foundation

/// Роутер MCP-запросов — маршрутизирует HTTP-запросы к обработчикам
@MainActor
final class MCPRouter {

    /// Максимальный размер payload (по умолчанию 5 MB)
    var maxPayloadSize: Int = 5 * 1024 * 1024

    /// JSON-декодер с ISO8601 датами
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Роутинг

    /// Обработать входящий запрос
    func handle(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        // CORS preflight
        if request.method == "OPTIONS" {
            return .corsOK()
        }

        // Проверка размера payload
        if let body = request.body, body.count > maxPayloadSize {
            return .error("Payload too large (max \(maxPayloadSize) bytes)", statusCode: 413)
        }

        // Роутинг по path + method
        switch (request.method, request.path) {
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

        case ("GET", "/"):
            return handleRoot()

        default:
            return .error("Not found: \(request.method) \(request.path)", statusCode: 404)
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
            let flowId: UUID
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

        MCPFlowTracker.shared.startFlow(
            id: req.flowId,
            name: req.flowName,
            description: req.flowDescription,
            source: req.source
        )

        return .json([
            "status": "ok",
            "flowId": req.flowId.uuidString
        ])
    }

    /// Завершить поток
    private func handleFlowEnd(_ request: MCPHTTPRequest) -> MCPHTTPResponse {
        guard let body = request.body else {
            return .error("Request body is required")
        }

        struct FlowEndRequest: Decodable {
            let flowId: UUID
        }

        let req: FlowEndRequest
        do {
            req = try decoder.decode(FlowEndRequest.self, from: body)
        } catch {
            return .error("Invalid JSON: \(error.localizedDescription)")
        }

        guard let flow = MCPFlowTracker.shared.endFlow(id: req.flowId) else {
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
                "GET /status",
                "GET /flows"
            ]
        ])
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
