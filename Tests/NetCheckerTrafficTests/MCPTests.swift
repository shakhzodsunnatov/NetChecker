import XCTest
@testable import NetCheckerTrafficCore

@MainActor
final class MCPTests: XCTestCase {

    // MARK: - MCPLogEntry Codable

    func testMCPLogEntryEncoding() throws {
        let entry = MCPLogEntry(
            operationType: .apiCall,
            source: MCPSourceInfo(
                toolName: "claude-code",
                sessionId: "test-session"
            ),
            payload: .networkCall(MCPNetworkPayload(
                url: "https://api.example.com/users",
                method: "GET",
                statusCode: 200,
                responseBody: "{\"id\": 1}"
            )),
            severity: .info,
            tags: ["test"]
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MCPLogEntry.self, from: data)

        XCTAssertEqual(decoded.operationType, .apiCall)
        XCTAssertEqual(decoded.source.toolName, "claude-code")
        XCTAssertEqual(decoded.severity, .info)
        XCTAssertEqual(decoded.tags, ["test"])
    }

    func testMCPLogEntryWithFlowContext() throws {
        let flowId = UUID()
        let entry = MCPLogEntry(
            operationType: .fileWrite,
            source: MCPSourceInfo(toolName: "cursor", sessionId: "s1"),
            flowContext: MCPFlowContext(
                flowId: flowId,
                flowName: "Login Feature",
                sequenceNumber: 3
            ),
            payload: .fileOperation(MCPFilePayload(
                filePath: "/src/login.swift",
                operation: "write",
                lineCount: 42
            ))
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MCPLogEntry.self, from: data)

        XCTAssertEqual(decoded.flowContext?.flowId, flowId)
        XCTAssertEqual(decoded.flowContext?.flowName, "Login Feature")
        XCTAssertEqual(decoded.flowContext?.sequenceNumber, 3)
    }

    // MARK: - MCPPayload Variants

    func testNetworkPayloadCodable() throws {
        let payload = MCPPayload.networkCall(MCPNetworkPayload(
            url: "https://api.test.com",
            method: "POST",
            statusCode: 201,
            requestBody: "{\"name\": \"test\"}",
            responseBody: "{\"id\": 42}"
        ))

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(MCPPayload.self, from: data)

        if case .networkCall(let net) = decoded {
            XCTAssertEqual(net.url, "https://api.test.com")
            XCTAssertEqual(net.method, "POST")
            XCTAssertEqual(net.statusCode, 201)
        } else {
            XCTFail("Expected networkCall payload")
        }
    }

    func testCommandPayloadCodable() throws {
        let payload = MCPPayload.commandResult(MCPCommandPayload(
            command: "swift build",
            exitCode: 0,
            stdout: "Build complete!",
            duration: 5.2
        ))

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(MCPPayload.self, from: data)

        if case .commandResult(let cmd) = decoded {
            XCTAssertEqual(cmd.command, "swift build")
            XCTAssertEqual(cmd.exitCode, 0)
        } else {
            XCTFail("Expected commandResult payload")
        }
    }

    func testTestPayloadCodable() throws {
        let payload = MCPPayload.testResult(MCPTestPayload(
            testName: "testLogin",
            testSuite: "AuthTests",
            passed: false,
            errorMessage: "Expected 200 got 401"
        ))

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(MCPPayload.self, from: data)

        if case .testResult(let test) = decoded {
            XCTAssertEqual(test.testName, "testLogin")
            XCTAssertFalse(test.passed)
        } else {
            XCTFail("Expected testResult payload")
        }
    }

    // MARK: - MCPRequestParser

    func testParseValidHTTPRequest() {
        let raw = "POST /log HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"test\": true}"
        let data = Data(raw.utf8)

        let request = MCPRequestParser.parse(data)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/log")
        XCTAssertEqual(request?.contentType, "application/json")
        XCTAssertNotNil(request?.body)
    }

    func testParseGETRequest() {
        let raw = "GET /status HTTP/1.1\r\nHost: localhost:9876\r\n\r\n"
        let data = Data(raw.utf8)

        let request = MCPRequestParser.parse(data)

        XCTAssertNotNil(request)
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/status")
        XCTAssertNil(request?.body)
    }

    func testParseIncompleteRequest() {
        let raw = "POST /log HTTP/1.1\r\nContent-Type: application/json\r\n"
        let data = Data(raw.utf8)

        let request = MCPRequestParser.parse(data)
        XCTAssertNil(request) // Нет завершения заголовков
    }

    // MARK: - MCPSchemaValidator

    func testValidateStatusCodeMismatch() {
        let entry = MCPLogEntry(
            operationType: .apiCall,
            source: MCPSourceInfo(toolName: "test", sessionId: "s1"),
            payload: .networkCall(MCPNetworkPayload(
                url: "https://api.test.com",
                method: "GET",
                statusCode: 500
            )),
            expectations: MCPExpectations(expectedStatusCode: 200)
        )

        let validated = MCPSchemaValidator.validate(entry)

        XCTAssertFalse(validated.expectations?.met ?? true)
        XCTAssertEqual(validated.expectations?.violations?.count, 1)
        XCTAssertEqual(validated.expectations?.violations?.first?.field, "statusCode")
        XCTAssertEqual(validated.expectations?.violations?.first?.expected, "200")
        XCTAssertEqual(validated.expectations?.violations?.first?.actual, "500")
    }

    func testValidateMissingFields() {
        let entry = MCPLogEntry(
            operationType: .apiCall,
            source: MCPSourceInfo(toolName: "test", sessionId: "s1"),
            payload: .networkCall(MCPNetworkPayload(
                url: "https://api.test.com",
                method: "GET",
                statusCode: 200,
                responseBody: "{\"token\": \"abc\"}"
            )),
            expectations: MCPExpectations(
                expectedStatusCode: 200,
                expectedFields: ["token", "refreshToken", "expiresIn"]
            )
        )

        let validated = MCPSchemaValidator.validate(entry)

        // token есть, refreshToken и expiresIn — нет
        let violations = validated.expectations?.violations ?? []
        XCTAssertEqual(violations.count, 2)

        let violatedFields = Set(violations.map { $0.field })
        XCTAssertTrue(violatedFields.contains("refreshToken"))
        XCTAssertTrue(violatedFields.contains("expiresIn"))
    }

    func testValidateNoViolationsWhenExpectationsMet() {
        let entry = MCPLogEntry(
            operationType: .apiCall,
            source: MCPSourceInfo(toolName: "test", sessionId: "s1"),
            payload: .networkCall(MCPNetworkPayload(
                url: "https://api.test.com",
                method: "GET",
                statusCode: 200,
                responseBody: "{\"token\": \"abc\", \"refreshToken\": \"def\"}"
            )),
            expectations: MCPExpectations(
                expectedStatusCode: 200,
                expectedFields: ["token", "refreshToken"]
            )
        )

        let validated = MCPSchemaValidator.validate(entry)
        XCTAssertTrue(validated.expectations?.met ?? false)
    }

    func testValidateTestFailure() {
        let entry = MCPLogEntry(
            operationType: .testExecution,
            source: MCPSourceInfo(toolName: "test", sessionId: "s1"),
            payload: .testResult(MCPTestPayload(
                testName: "testLogin",
                passed: false,
                errorMessage: "Auth failed"
            )),
            expectations: MCPExpectations()
        )

        let validated = MCPSchemaValidator.validate(entry)

        let violations = validated.expectations?.violations ?? []
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.field, "testPassed")
    }

    // MARK: - MCPOperationType

    func testOperationTypeProperties() {
        XCTAssertTrue(MCPOperationType.apiCall.isNetworkRelated)
        XCTAssertTrue(MCPOperationType.webhookReceived.isNetworkRelated)
        XCTAssertFalse(MCPOperationType.fileRead.isNetworkRelated)
        XCTAssertFalse(MCPOperationType.testExecution.isNetworkRelated)
    }

    // MARK: - MCPSeverity

    func testSeverityComparable() {
        XCTAssertTrue(MCPSeverity.debug < MCPSeverity.info)
        XCTAssertTrue(MCPSeverity.info < MCPSeverity.warning)
        XCTAssertTrue(MCPSeverity.warning < MCPSeverity.error)
        XCTAssertTrue(MCPSeverity.error < MCPSeverity.critical)
    }

    // MARK: - TrafficRecord Conversion

    func testMCPLogEntryToTrafficRecord() {
        let entry = MCPLogEntry(
            operationType: .apiCall,
            source: MCPSourceInfo(toolName: "claude-code", sessionId: "s1"),
            payload: .networkCall(MCPNetworkPayload(
                url: "https://api.example.com/users",
                method: "GET",
                statusCode: 200,
                responseBody: "{\"users\": []}"
            )),
            tags: ["auth"]
        )

        let record = MCPRouter.convertToTrafficRecord(entry)

        XCTAssertEqual(record.url.absoluteString, "https://api.example.com/users")
        XCTAssertEqual(record.method, .get)
        XCTAssertEqual(record.statusCode, 200)
        XCTAssertNotNil(record.metadata.mcpSource)
        XCTAssertEqual(record.metadata.mcpSource?.toolName, "claude-code")
        XCTAssertTrue(record.metadata.tags.contains("mcp"))
        XCTAssertTrue(record.metadata.tags.contains("apiCall"))
        XCTAssertTrue(record.metadata.tags.contains("auth"))
    }

    func testFileOperationToTrafficRecord() {
        let entry = MCPLogEntry(
            operationType: .fileWrite,
            source: MCPSourceInfo(toolName: "cursor", sessionId: "s1"),
            payload: .fileOperation(MCPFilePayload(
                filePath: "/src/app.swift",
                operation: "write",
                lineCount: 100
            ))
        )

        let record = MCPRouter.convertToTrafficRecord(entry)

        XCTAssertTrue(record.url.absoluteString.contains("mcp://"))
        XCTAssertTrue(record.url.absoluteString.contains("cursor"))
        XCTAssertTrue(record.metadata.tags.contains("fileWrite"))
    }

    // MARK: - TrafficFilter MCP

    func testMCPOnlyFilter() {
        var filter = TrafficFilter()
        filter.onlyMCP = true

        let mcpRecord = createMCPRecord()
        let regularRecord = TrafficRecord(request: RequestData(
            url: URL(string: "https://api.test.com")!
        ))

        let filtered = filter.apply(to: [mcpRecord, regularRecord])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertNotNil(filtered.first?.metadata.mcpSource)
    }

    // MARK: - Helpers

    private func createMCPRecord() -> TrafficRecord {
        let entry = MCPLogEntry(
            operationType: .apiCall,
            source: MCPSourceInfo(toolName: "test-tool", sessionId: "s1"),
            payload: .networkCall(MCPNetworkPayload(
                url: "https://api.test.com/data",
                method: "GET",
                statusCode: 200
            ))
        )
        return MCPRouter.convertToTrafficRecord(entry)
    }
}
