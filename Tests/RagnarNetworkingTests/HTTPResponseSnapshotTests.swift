//
//  HTTPResponseSnapshotTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("HTTPResponseSnapshot Tests")
struct HTTPResponseSnapshotTests {

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

}

@Suite("ErrorSnapshot Tests")
struct ErrorSnapshotTests {

    @Test("Memberwise init stores all fields")
    func memberwiseInitStoresFields() {
        let snapshot = ErrorSnapshot(
            typeName: "MyError",
            description: "something went wrong",
            localizedDescription: "Something went wrong."
        )
        #expect(snapshot.typeName == "MyError")
        #expect(snapshot.description == "something went wrong")
        #expect(snapshot.localizedDescription == "Something went wrong.")
    }

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

    @Test("Equatable: equal snapshots compare equal")
    func equalSnapshotsAreEqual() {
        let a = ErrorSnapshot(typeName: "E", description: "d", localizedDescription: "l")
        let b = ErrorSnapshot(typeName: "E", description: "d", localizedDescription: "l")
        #expect(a == b)
    }

    @Test("Equatable: snapshots with different fields are not equal")
    func differentSnapshotsAreNotEqual() {
        let a = ErrorSnapshot(typeName: "E", description: "d", localizedDescription: "l")
        let b = ErrorSnapshot(typeName: "X", description: "d", localizedDescription: "l")
        #expect(a != b)
    }

    @Test("CustomStringConvertible description matches description field")
    func descriptionMatchesStoredField() {
        let snapshot = ErrorSnapshot(typeName: "T", description: "my error text", localizedDescription: "l")
        #expect(snapshot.description == "my error text")
    }
}
