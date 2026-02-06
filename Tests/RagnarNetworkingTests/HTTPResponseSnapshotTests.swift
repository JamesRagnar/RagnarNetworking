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

        #expect(snapshot.statusCode == 204)
        #expect(snapshot.headers["X-Request-ID"] == "req-123")
        #expect(snapshot.url == url)
    }

}
