//
//  HTTPResponseSnapshotTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("HTTPResponseSnapshot Tests", .timeLimit(.minutes(1)))
struct HTTPResponseSnapshotTests {

    struct RedactionScenario: Sendable, CustomTestStringConvertible {
        let name: String
        let url: String
        let redactedNames: Set<String>
        let expectedURL: String

        var testDescription: String { name }
    }

    @Test("Captures non-HTTP response properties")
    func testNonHTTPResponseCapture() {
        let url = URL(string: "https://api.example.com/test")!
        let response = URLResponse(
            url: url,
            mimeType: "application/json",
            expectedContentLength: 42,
            textEncodingName: "utf-8"
        )

        let snapshot = HTTPResponseSnapshot(response: response)

        #expect(snapshot.isHTTPResponse == false)
        #expect(snapshot.statusCode == nil)
        #expect(snapshot.headers.isEmpty == true)
        #expect(snapshot.url == url)
        #expect(snapshot.mimeType == "application/json")
        #expect(snapshot.expectedContentLength == 42)
        #expect(snapshot.textEncodingName == "utf-8")
    }

    @Test("Captures HTTP status code and headers")
    func testHTTPResponseCapture() {
        let url = URL(string: "https://api.example.com/test")!
        let headers = ["X-Request-ID": "req-123"]
        let response = HTTPURLResponse(
            url: url,
            statusCode: 204,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!

        let snapshot = HTTPResponseSnapshot(response: response)

        #expect(snapshot.isHTTPResponse == true)
        #expect(snapshot.statusCode == 204)
        #expect(snapshot.headers["X-Request-ID"] == "req-123")
        #expect(snapshot.url == url)
    }

    @Test("Coerces unusual raw header key/value types to strings")
    func testCoerceHeadersFromAnyHashableTypes() {
        let coerced = HTTPResponseSnapshot.coerceHeaders([
            AnyHashable(NSNumber(value: 1)): NSNumber(value: 2),
            AnyHashable("X-Token"): UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!
        ])

        #expect(coerced["1"] == "2")
        #expect(coerced["X-Token"]?.contains("123E4567-E89B-12D3-A456-426614174000") == true)
    }

    // MARK: - Query Item Redaction

    @Test(
        "Redacts configured query items without changing unrelated URL content",
        arguments: [
            RedactionScenario(
                name: "matching name",
                url: "https://api.example.com/test?token=secret-value&other=kept",
                redactedNames: ["token"],
                expectedURL: "https://api.example.com/test?other=kept"
            ),
            RedactionScenario(
                name: "case-insensitive name",
                url: "https://api.example.com/test?Token=secret-value",
                redactedNames: ["token"],
                expectedURL: "https://api.example.com/test"
            ),
            RedactionScenario(
                name: "multiple names",
                url: "https://api.example.com/test?token=a&access_token=b&other=kept",
                redactedNames: ["token", "access_token"],
                expectedURL: "https://api.example.com/test?other=kept"
            ),
            RedactionScenario(
                name: "no matching name",
                url: "https://api.example.com/test?other=kept",
                redactedNames: ["token"],
                expectedURL: "https://api.example.com/test?other=kept"
            ),
            RedactionScenario(
                name: "no configured names",
                url: "https://api.example.com/test?token=secret-value",
                redactedNames: [],
                expectedURL: "https://api.example.com/test?token=secret-value"
            )
        ]
    )
    func testQueryItemRedaction(_ scenario: RedactionScenario) throws {
        let url = try #require(URL(string: scenario.url))
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        let snapshot = HTTPResponseSnapshot(
            response: response,
            redactedQueryItemNames: scenario.redactedNames
        )

        #expect(snapshot.url?.absoluteString == scenario.expectedURL)
    }

}

@Suite("ErrorSnapshot Tests", .timeLimit(.minutes(1)))
struct ErrorSnapshotTests {

    @Test("Error init captures type name, description, and localized description")
    func errorInitCapturesProperties() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "A test error occurred." }
        }
        let snapshot = ErrorSnapshot(TestError())
        #expect(snapshot.typeName == "TestError")
        #expect(snapshot.localizedDescription == "A test error occurred.")
        #expect(snapshot.description.isEmpty == false)
    }

}
