//
//  ResponseErrorHelpersTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("ResponseError Helper Methods Tests", .timeLimit(.minutes(1)))
struct ResponseErrorHelpersTests {

    // MARK: - Test Fixtures

    enum ErrorKind: CaseIterable, Sendable, CustomTestStringConvertible {
        case unknownResponse
        case unknownResponseCase
        case decoding
        case generic
        case decoded

        var testDescription: String {
            switch self {
            case .unknownResponse: "unknownResponse"
            case .unknownResponseCase: "unknownResponseCase"
            case .decoding: "decoding"
            case .generic: "generic"
            case .decoded: "decoded"
            }
        }
    }

    struct FixtureError: Error, Sendable, CustomStringConvertible {
        var description: String { "fixture error" }
    }

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

    func makeSnapshot(from response: URLResponse) -> HTTPResponseSnapshot {
        HTTPResponseSnapshot(response: response)
    }

    func makeError(
        _ kind: ErrorKind,
        data: Data = Data(),
        statusCode: Int = 400,
        headers: [String: String]? = nil
    ) -> ResponseError {
        let response = kind == .unknownResponse
            ? makeURLResponse()
            : makeHTTPResponse(statusCode: statusCode, headers: headers)
        let body = ResponseBody(data)
        let snapshot = makeSnapshot(from: response)

        switch kind {
        case .unknownResponse:
            return .unknownResponse(body, snapshot)

        case .unknownResponseCase:
            return .unknownResponseCase(body, snapshot)

        case .decoding:
            return .decoding(body, snapshot, .missingString)

        case .generic:
            return .generic(body, snapshot, FixtureError())

        case .decoded:
            return .decoded(body, snapshot, FixtureError())
        }
    }

    // MARK: - Body Accessor Tests

    @Test("body exposes the ResponseBody for every error case", arguments: ErrorKind.allCases)
    func testBodyAccessorForAllCases(_ kind: ErrorKind) {
        let data = "payload".data(using: .utf8)!
        let error = makeError(kind, data: data)

        #expect(error.body.data == data)
        #expect(error.responseData == data)
    }

    @Test("body carries the decoder the response was handled with")
    func testBodyCarriesDecoder() {
        struct SnakeCasePayload: Decodable, Equatable {
            let errorCode: Int
        }

        let error = ResponseError.unknownResponseCase(
            ResponseBody(
                #"{"error_code": 7}"#.data(using: .utf8)!,
                decoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
            ),
            makeSnapshot(from: makeHTTPResponse(statusCode: 400))
        )

        // Reached through the error's own body, with no decoder supplied at the catch site.
        #expect(error.body.decode(as: SnakeCasePayload.self) == SnakeCasePayload(errorCode: 7))
        #expect(error.decodeError(as: SnakeCasePayload.self) == SnakeCasePayload(errorCode: 7))
    }

    @Test("decodeError returns the already-decoded error without re-decoding")
    func testDecodeErrorReturnsStoredValue() {
        struct StoredError: Decodable, Error, Equatable {
            let code: Int
        }

        // An empty body: decoding it would fail, so a returned value can only be the stored one.
        let error = ResponseError.decoded(
            ResponseBody(Data()),
            makeSnapshot(from: makeHTTPResponse(statusCode: 400)),
            StoredError(code: 9)
        )

        #expect(error.decodeError(as: StoredError.self) == StoredError(code: 9))
    }

    // MARK: - Status Code Tests

    @Test("statusCode reflects every error case", arguments: ErrorKind.allCases)
    func testStatusCode(_ kind: ErrorKind) {
        let error = makeError(kind, statusCode: 418)
        let expectedStatusCode = kind == .unknownResponse ? nil : 418

        #expect(error.statusCode == expectedStatusCode)
    }

    @Test(
        "statusCode preserves HTTP status values",
        arguments: [200, 201, 400, 401, 403, 404, 500, 502, 503]
    )
    func testVariousStatusCodes(_ statusCode: Int) {
        let error = makeError(.unknownResponseCase, statusCode: statusCode)

        #expect(error.statusCode == statusCode)
    }

    // MARK: - Response Body String Tests

    @Test("Returns body string for all error types", arguments: ErrorKind.allCases)
    func testBodyStringAllErrorTypes(_ kind: ErrorKind) {
        let bodyString = "test error"
        let data = bodyString.data(using: .utf8)!
        let error = makeError(kind, data: data)

        #expect(error.responseBodyString == bodyString)
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
        let error = ResponseError.unknownResponseCase(ResponseBody(data), makeSnapshot(from: response))

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
        let error = ResponseError.unknownResponseCase(ResponseBody(data), makeSnapshot(from: response))

        let decodedError = error.decodeError(as: APIError.self)

        #expect(decodedError == nil)
    }

    @Test("decodeError falls back to raw data when decoded type mismatches")
    func testDecodeErrorFallbackToRawData() {
        struct StoredError: Codable, Error {
            let message: String
        }

        struct ExpectedError: Codable {
            let code: Int
        }

        let data = #"{"code":123}"#.data(using: .utf8)!
        let response = makeHTTPResponse(statusCode: 400)
        let stored = StoredError(message: "stored")
        let error = ResponseError.decoded(ResponseBody(data), makeSnapshot(from: response), stored)

        let decoded = error.decodeError(as: ExpectedError.self)

        #expect(decoded?.code == 123)
    }

    // MARK: - Headers Tests

    @Test(
        "headers exposes HTTP headers for every response error case",
        arguments: ErrorKind.allCases
    )
    func testHeadersDictionary(_ kind: ErrorKind) {
        let headers = [
            "Content-Type": "application/json",
            "X-Request-ID": "12345",
            "Cache-Control": "no-cache"
        ]
        let error = makeError(kind, headers: headers)
        let expectedHeaders = kind == .unknownResponse ? nil : headers

        #expect(error.headers == expectedHeaders)
    }

    // MARK: - Header Method Tests

    @Test("Header lookup is case-insensitive")
    func testHeaderCaseSensitivity() {
        let headers = ["Content-Type": "application/json"]
        let data = Data()
        let response = makeHTTPResponse(statusCode: 200, headers: headers)
        let error = ResponseError.unknownResponseCase(ResponseBody(data), makeSnapshot(from: response))

        #expect(error.header("Content-Type") == "application/json")
        #expect(error.header("content-type") == "application/json")
        #expect(error.header("CONTENT-TYPE") == "application/json")
    }

    // MARK: - Is Retryable Tests

    @Test(
        "isRetryable classifies status codes",
        arguments: [
            (200, false),
            (204, false),
            (301, false),
            (308, false),
            (400, false),
            (401, false),
            (422, false),
            (428, false),
            (429, true),
            (500, true),
            (504, true),
            (599, true),
            (600, false)
        ]
    )
    func testRetryability(statusCode: Int, expected: Bool) {
        let error = makeError(.unknownResponseCase, statusCode: statusCode)

        #expect(error.isRetryable == expected)
    }

    @Test("Returns false for unknownResponse")
    func testNotRetryableUnknownResponse() {
        let error = ResponseError.unknownResponse(ResponseBody(Data()), makeSnapshot(from: makeURLResponse()))

        #expect(error.isRetryable == false)
    }

    // MARK: - Debug Description Tests

    @Test(
        "Debug description includes every error type",
        arguments: [
            (ErrorKind.unknownResponse, "unknownResponse"),
            (.unknownResponseCase, "unknownResponseCase"),
            (.decoding, "decoding"),
            (.generic, "generic"),
            (.decoded, "decoded")
        ]
    )
    func testDebugDescriptionIncludesErrorType(_ kind: ErrorKind, expected: String) {
        let error = makeError(kind)

        #expect(error.debugDescription.contains(expected))
    }

    @Test("Debug description redacts Set-Cookie and Authorization headers")
    func testDebugDescriptionRedactsSensitiveHeaders() {
        let headers = [
            "Set-Cookie": "session=abc123",
            "Authorization": "Bearer server-echoed-token",
            "Proxy-Authorization": "Basic proxy-secret",
            "X-Request-ID": "12345"
        ]
        let error = ResponseError.unknownResponseCase(
            ResponseBody(Data()),
            makeSnapshot(from: makeHTTPResponse(statusCode: 400, headers: headers))
        )

        #expect(error.debugDescription.contains("abc123") == false)
        #expect(error.debugDescription.contains("server-echoed-token") == false)
        #expect(error.debugDescription.contains("proxy-secret") == false)
        #expect(error.debugDescription.contains("X-Request-ID: 12345"))

        // The full, unredacted headers remain available directly.
        #expect(error.headers?["Set-Cookie"] == "session=abc123")
        #expect(error.headers?["Authorization"] == "Bearer server-echoed-token")
    }

    @Test("String interpolation of the error does not expose sensitive headers or the auth token")
    func testStringInterpolationIsRedacted() {
        let url = URL(string: "https://api.example.com/test?token=secret-token-value")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 401,
            httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": "session=abc123"]
        )!
        let error = ResponseError.unknownResponseCase(ResponseBody(Data()), makeSnapshot(from: response))

        let interpolated = "\(error)"

        #expect(interpolated.contains("secret-token-value") == false)
        #expect(interpolated.contains("abc123") == false)
        #expect(interpolated == error.debugDescription)
    }

    @Test("Debug description truncates long bodies")
    func testDebugDescriptionTruncatesLongBody() {
        let longBody = String(repeating: "x", count: 250)
        let data = longBody.data(using: .utf8)!
        let error = ResponseError.unknownResponseCase(
            ResponseBody(data),
            makeSnapshot(from: makeHTTPResponse(statusCode: 500))
        )

        #expect(error.debugDescription.contains("..."))
        // Should be truncated to 200 chars plus "..."
    }

    // MARK: - Localized Description Tests

    @Test(
        "errorDescription is concise for every error case",
        arguments: [
            (ErrorKind.unknownResponse, "Received a non-HTTP response."),
            (.unknownResponseCase, "Received an unhandled HTTP status code (418)."),
            (.decoding, "Failed to decode the server response."),
            (.generic, "fixture error"),
            (.decoded, "fixture error")
        ]
    )
    func testErrorDescription(_ kind: ErrorKind, expected: String) {
        let error = makeError(kind, data: Data("oops".utf8), statusCode: 418)

        #expect(error.errorDescription == expected)
    }

    @Test("unknownResponseCase describes a non-HTTP snapshot")
    func testUnknownResponseCaseWithoutStatusCode() {
        let error = ResponseError.unknownResponseCase(
            ResponseBody(Data()),
            makeSnapshot(from: makeURLResponse())
        )

        #expect(error.errorDescription == "Received an unhandled response.")
    }

}
