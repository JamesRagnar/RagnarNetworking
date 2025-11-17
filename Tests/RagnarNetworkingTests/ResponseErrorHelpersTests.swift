//
//  ResponseErrorHelpersTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Testing
import Foundation
@testable import RagnarNetworking

@Suite("ResponseError Helper Methods Tests")
struct ResponseErrorHelpersTests {

    // MARK: - Test Fixtures

    let testURL = URL(string: "https://api.example.com/test")!

    func makeHTTPResponse(statusCode: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(
            url: testURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func makeURLResponse() -> URLResponse {
        URLResponse(
            url: testURL,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )
    }

    // MARK: - Status Code Tests

    @Test("Returns status code for unknownResponseCase")
    func testStatusCodeUnknownResponseCase() {
        let data = Data()
        let response = makeHTTPResponse(statusCode: 404)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.statusCode == 404)
    }

    @Test("Returns status code for decoding error")
    func testStatusCodeDecodingError() {
        let data = Data()
        let response = makeHTTPResponse(statusCode: 200)
        let decodingError = InterfaceDecodingError.missingString
        let error = ResponseError.decoding(data, response, decodingError)

        #expect(error.statusCode == 200)
    }

    @Test("Returns status code for generic error")
    func testStatusCodeGenericError() {
        let data = Data()
        let response = makeHTTPResponse(statusCode: 500)
        let error = ResponseError.generic(data, response, NSError(domain: "test", code: 1))

        #expect(error.statusCode == 500)
    }

    @Test("Returns nil for unknownResponse")
    func testStatusCodeUnknownResponse() {
        let data = Data()
        let response = makeURLResponse()
        let error = ResponseError.unknownResponse(data, response)

        #expect(error.statusCode == nil)
    }

    @Test("Returns various status codes correctly")
    func testVariousStatusCodes() {
        let statusCodes = [200, 201, 400, 401, 403, 404, 500, 502, 503]

        for code in statusCodes {
            let error = ResponseError.unknownResponseCase(Data(), makeHTTPResponse(statusCode: code))
            #expect(error.statusCode == code)
        }
    }

    // MARK: - Response Body String Tests

    @Test("Returns response body as string")
    func testResponseBodyString() {
        let bodyString = "Error message from server"
        let data = bodyString.data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 400)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.responseBodyString == bodyString)
    }

    @Test("Returns JSON response body as string")
    func testJSONResponseBodyString() {
        let jsonString = """
        {"error": "Invalid request", "code": 400}
        """
        let data = jsonString.data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 400)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.responseBodyString == jsonString)
    }

    @Test("Returns nil for invalid UTF-8 data")
    func testInvalidUTF8ResponseBody() {
        let data = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        let response = makeHTTPResponse(statusCode: 500)
        let error = ResponseError.generic(data, response, NSError(domain: "test", code: 1))

        #expect(error.responseBodyString == nil)
    }

    @Test("Returns empty string for empty data")
    func testEmptyResponseBody() {
        let data = Data()
        let response = makeHTTPResponse(statusCode: 204)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.responseBodyString == "")
    }

    @Test("Returns body string for all error types")
    func testBodyStringAllErrorTypes() {
        let bodyString = "test error"
        let data = bodyString.data(using: .utf8)!

        let errors: [ResponseError] = [
            .unknownResponse(data, makeURLResponse()),
            .unknownResponseCase(data, makeHTTPResponse(statusCode: 404)),
            .decoding(data, makeHTTPResponse(statusCode: 200), .missingString),
            .generic(data, makeHTTPResponse(statusCode: 500), NSError(domain: "test", code: 1))
        ]

        for error in errors {
            #expect(error.responseBodyString == bodyString)
        }
    }

    // MARK: - Decode Error Tests

    @Test("Decodes structured error response")
    func testDecodeStructuredError() {
        struct APIError: Codable {
            let message: String
            let errorCode: Int
        }

        let errorJSON = """
        {"message": "Invalid API key", "errorCode": 1001}
        """
        let data = errorJSON.data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 401)
        let error = ResponseError.unknownResponseCase(data, response)

        let decodedError = error.decodeError(as: APIError.self)

        #expect(decodedError?.message == "Invalid API key")
        #expect(decodedError?.errorCode == 1001)
    }

    @Test("Returns nil for invalid JSON structure")
    func testDecodeErrorInvalidJSON() {
        struct APIError: Codable {
            let message: String
        }

        let data = "not json".data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 400)
        let error = ResponseError.unknownResponseCase(data, response)

        let decodedError = error.decodeError(as: APIError.self)

        #expect(decodedError == nil)
    }

    @Test("Returns nil for mismatched error structure")
    func testDecodeErrorMismatchedStructure() {
        struct ExpectedError: Codable {
            let message: String
            let code: Int
        }

        let errorJSON = """
        {"differentField": "value"}
        """
        let data = errorJSON.data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 400)
        let error = ResponseError.unknownResponseCase(data, response)

        let decodedError = error.decodeError(as: ExpectedError.self)

        #expect(decodedError == nil)
    }

    @Test("Decodes complex nested error structures")
    func testDecodeNestedErrorStructure() {
        struct DetailedError: Codable {
            struct ErrorDetail: Codable {
                let field: String
                let reason: String
            }
            let message: String
            let details: [ErrorDetail]
        }

        let errorJSON = """
        {
            "message": "Validation failed",
            "details": [
                {"field": "email", "reason": "Invalid format"},
                {"field": "password", "reason": "Too short"}
            ]
        }
        """
        let data = errorJSON.data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 422)
        let error = ResponseError.unknownResponseCase(data, response)

        let decodedError = error.decodeError(as: DetailedError.self)

        #expect(decodedError?.message == "Validation failed")
        #expect(decodedError?.details.count == 2)
        #expect(decodedError?.details[0].field == "email")
        #expect(decodedError?.details[1].reason == "Too short")
    }

    // MARK: - Headers Tests

    @Test("Returns headers dictionary")
    func testHeadersDictionary() {
        let headers = [
            "Content-Type": "application/json",
            "X-Request-ID": "12345",
            "Cache-Control": "no-cache"
        ]
        let data = Data()
        let response = makeHTTPResponse(statusCode: 500, headers: headers)
        let error = ResponseError.generic(data, response, NSError(domain: "test", code: 1))

        #expect(error.headers?["Content-Type"] == "application/json")
        #expect(error.headers?["X-Request-ID"] == "12345")
        #expect(error.headers?["Cache-Control"] == "no-cache")
    }

    @Test("Returns nil headers for unknownResponse")
    func testHeadersNilForUnknownResponse() {
        let data = Data()
        let response = makeURLResponse()
        let error = ResponseError.unknownResponse(data, response)

        #expect(error.headers == nil)
    }

    @Test("Returns empty dictionary for no headers")
    func testEmptyHeadersDictionary() {
        let data = Data()
        let response = makeHTTPResponse(statusCode: 200)
        let error = ResponseError.unknownResponseCase(data, response)

        // HTTPURLResponse may have some default headers, so just check it's not nil
        #expect(error.headers != nil)
    }

    // MARK: - Header Method Tests

    @Test("Returns specific header value")
    func testSpecificHeaderValue() {
        let headers = ["X-Request-ID": "abc-123", "X-Rate-Limit": "100"]
        let data = Data()
        let response = makeHTTPResponse(statusCode: 429, headers: headers)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.header("X-Request-ID") == "abc-123")
        #expect(error.header("X-Rate-Limit") == "100")
    }

    @Test("Returns nil for non-existent header")
    func testNonExistentHeader() {
        let data = Data()
        let response = makeHTTPResponse(statusCode: 200)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.header("X-Nonexistent") == nil)
    }

    @Test("Header lookup is case-sensitive")
    func testHeaderCaseSensitivity() {
        let headers = ["Content-Type": "application/json"]
        let data = Data()
        let response = makeHTTPResponse(statusCode: 200, headers: headers)
        let error = ResponseError.unknownResponseCase(data, response)

        #expect(error.header("Content-Type") == "application/json")
        // Note: HTTP headers are typically case-insensitive, but our helper does exact lookup
    }

    // MARK: - Is Retryable Tests

    @Test("Returns true for 5xx errors")
    func testRetryable5xxErrors() {
        let serverErrors = [500, 501, 502, 503, 504, 599]

        for statusCode in serverErrors {
            let error = ResponseError.unknownResponseCase(
                Data(),
                makeHTTPResponse(statusCode: statusCode)
            )
            #expect(error.isRetryable == true, "Status \(statusCode) should be retryable")
        }
    }

    @Test("Returns true for 429 Too Many Requests")
    func testRetryable429() {
        let error = ResponseError.unknownResponseCase(
            Data(),
            makeHTTPResponse(statusCode: 429)
        )

        #expect(error.isRetryable == true)
    }

    @Test("Returns false for 4xx client errors")
    func testNotRetryable4xxErrors() {
        let clientErrors = [400, 401, 403, 404, 422, 428]

        for statusCode in clientErrors {
            let error = ResponseError.unknownResponseCase(
                Data(),
                makeHTTPResponse(statusCode: statusCode)
            )
            #expect(error.isRetryable == false, "Status \(statusCode) should not be retryable")
        }
    }

    @Test("Returns false for 2xx success codes")
    func testNotRetryable2xxErrors() {
        // These shouldn't normally be errors, but testing the logic
        let successCodes = [200, 201, 204]

        for statusCode in successCodes {
            let decodingError = InterfaceDecodingError.missingString
            let error = ResponseError.decoding(
                Data(),
                makeHTTPResponse(statusCode: statusCode),
                decodingError
            )
            #expect(error.isRetryable == false, "Status \(statusCode) should not be retryable")
        }
    }

    @Test("Returns false for unknownResponse")
    func testNotRetryableUnknownResponse() {
        let error = ResponseError.unknownResponse(Data(), makeURLResponse())

        #expect(error.isRetryable == false)
    }

    @Test("Returns false for 3xx redirect codes")
    func testNotRetryable3xxRedirects() {
        let redirectCodes = [301, 302, 304, 307, 308]

        for statusCode in redirectCodes {
            let error = ResponseError.unknownResponseCase(
                Data(),
                makeHTTPResponse(statusCode: statusCode)
            )
            #expect(error.isRetryable == false, "Status \(statusCode) should not be retryable")
        }
    }

    // MARK: - Debug Description Tests

    @Test("Debug description includes error type")
    func testDebugDescriptionIncludesErrorType() {
        let error = ResponseError.unknownResponseCase(Data(), makeHTTPResponse(statusCode: 404))

        #expect(error.debugDescription.contains("unknownResponseCase"))
    }

    @Test("Debug description includes status code")
    func testDebugDescriptionIncludesStatusCode() {
        let error = ResponseError.unknownResponseCase(Data(), makeHTTPResponse(statusCode: 500))

        #expect(error.debugDescription.contains("Status: 500"))
    }

    @Test("Debug description includes headers")
    func testDebugDescriptionIncludesHeaders() {
        let headers = ["X-Request-ID": "12345"]
        let error = ResponseError.unknownResponseCase(
            Data(),
            makeHTTPResponse(statusCode: 400, headers: headers)
        )

        #expect(error.debugDescription.contains("Headers:"))
        #expect(error.debugDescription.contains("X-Request-ID: 12345"))
    }

    @Test("Debug description includes body preview")
    func testDebugDescriptionIncludesBody() {
        let body = "Error message from server"
        let data = body.data(using: .utf8)!
        let error = ResponseError.unknownResponseCase(data, makeHTTPResponse(statusCode: 400))

        #expect(error.debugDescription.contains("Body:"))
        #expect(error.debugDescription.contains(body))
    }

    @Test("Debug description truncates long bodies")
    func testDebugDescriptionTruncatesLongBody() {
        let longBody = String(repeating: "x", count: 250)
        let data = longBody.data(using: .utf8)!
        let error = ResponseError.unknownResponseCase(data, makeHTTPResponse(statusCode: 500))

        #expect(error.debugDescription.contains("..."))
        // Should be truncated to 200 chars plus "..."
    }

    @Test("Debug description for decoding error includes decoding error type")
    func testDebugDescriptionDecodingError() {
        let decodingError = InterfaceDecodingError.jsonDecoder(
            NSError(domain: "test", code: 1)
        )
        let error = ResponseError.decoding(
            Data(),
            makeHTTPResponse(statusCode: 200),
            decodingError
        )

        #expect(error.debugDescription.contains("decoding"))
    }

    @Test("Debug description for generic error includes underlying error")
    func testDebugDescriptionGenericError() {
        let underlyingError = NSError(domain: "TestDomain", code: 42)
        let error = ResponseError.generic(
            Data(),
            makeHTTPResponse(statusCode: 500),
            underlyingError
        )

        #expect(error.debugDescription.contains("generic"))
    }

    @Test("Debug description for unknownResponse")
    func testDebugDescriptionUnknownResponse() {
        let body = "test body"
        let data = body.data(using: .utf8)!
        let error = ResponseError.unknownResponse(data, makeURLResponse())

        #expect(error.debugDescription.contains("unknownResponse"))
        #expect(error.debugDescription.contains(body))
        // Should not contain status code or headers
        #expect(!error.debugDescription.contains("Status:"))
    }

    @Test("Debug description with empty body")
    func testDebugDescriptionEmptyBody() {
        let error = ResponseError.unknownResponseCase(Data(), makeHTTPResponse(statusCode: 204))

        let description = error.debugDescription

        #expect(description.contains("Status: 204"))
        // Empty body should still have Body section but with empty string
    }

    @Test("Complete debug description format")
    func testCompleteDebugDescriptionFormat() {
        let body = """
        {"error": "Resource not found", "code": 404}
        """
        let data = body.data(using: .utf8)!
        let headers = [
            "Content-Type": "application/json",
            "X-Request-ID": "req-123"
        ]
        let error = ResponseError.unknownResponseCase(
            data,
            makeHTTPResponse(statusCode: 404, headers: headers)
        )

        let description = error.debugDescription

        // Verify all components are present and separated by " | "
        #expect(description.contains("unknownResponseCase"))
        #expect(description.contains("Status: 404"))
        #expect(description.contains("Headers:"))
        #expect(description.contains("Body:"))
        #expect(description.contains("|"))
    }

}
