import XCTest
@testable import NetCheckerTrafficCore

@MainActor
final class TrafficTests: XCTestCase {

    func testTrafficStoreInitialization() {
        let store = TrafficStore.shared
        XCTAssertNotNil(store)
    }

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.get.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.post.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.put.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.delete.rawValue, "DELETE")
    }

    func testStatusCategoryClassification() {
        XCTAssertEqual(StatusCategory(statusCode: 200), .success)
        XCTAssertEqual(StatusCategory(statusCode: 301), .redirect)
        XCTAssertEqual(StatusCategory(statusCode: 404), .clientError)
        XCTAssertEqual(StatusCategory(statusCode: 500), .serverError)
    }

    func testContentTypeDetection() {
        XCTAssertEqual(ContentType(mimeType: "application/json"), .json)
        XCTAssertEqual(ContentType(mimeType: "text/html"), .html)
        XCTAssertEqual(ContentType(mimeType: "text/plain"), .plainText)
    }

    func testCURLFormatting() {
        let request = RequestData(
            url: URL(string: "https://api.example.com/users")!,
            method: .get,
            headers: ["Authorization": "Bearer token123"]
        )
        let record = TrafficRecord(request: request)
        let curl = CURLFormatter.format(record: record)

        XCTAssertTrue(curl.contains("curl"))
        XCTAssertTrue(curl.contains("https://api.example.com/users"))
        XCTAssertTrue(curl.contains("Authorization"))
    }
}
