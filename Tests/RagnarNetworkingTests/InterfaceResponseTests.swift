//
//  InterfaceResponseTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Testing
import Foundation
@testable import RagnarNetworking

@Suite("Interface Response Handling Tests")
struct InterfaceResponseTests {

    // MARK: - Test Fixtures

    struct SuccessResponse: Codable, Sendable {
        let message: String
        let code: Int
    }

    struct TestInterface: Interface {
        struct Parameters: RequestParameters {
            typealias Body = EmptyBody
            let method: RequestMethod = .get
            let path = "/test"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = SuccessResponse

        static var responseCases: ResponseCases {
            [
                200: .success(SuccessResponse.self),
                201: .success(SuccessResponse.self),
                400: .failure(TestError.badRequest),
                401: .failure(TestError.unauthorized),
                500: .failure(TestError.serverError)
            ]
        }
    }

    struct StringInterface: Interface {
        struct Parameters: RequestParameters {
            typealias Body = EmptyBody
            let method: RequestMethod = .get
            let path = "/string"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = String

        static var responseCases: ResponseCases {
            [200: .success(String.self)]
        }
    }

    struct DataInterface: Interface {
        struct Parameters: RequestParameters {
            typealias Body = EmptyBody
            let method: RequestMethod = .get
            let path = "/data"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = Data

        static var responseCases: ResponseCases {
            [200: .success(Data.self)]
        }
    }

    enum TestError: Error {
        case badRequest
        case unauthorized
        case serverError
    }

    // MARK: - Successful Response Handling

    @Test("Handles successful JSON response")
    func testSuccessfulJSONResponse() throws {
        let responseData = """
        {"message": "success", "code": 200}
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try TestInterface.handle((data: responseData, response: httpResponse))

        #expect(result.message == "success")
        #expect(result.code == 200)
    }

    @Test("Handles successful String response")
    func testSuccessfulStringResponse() throws {
        let responseData = "Hello, World!".data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try StringInterface.handle((data: responseData, response: httpResponse))

        #expect(result == "Hello, World!")
    }

    @Test("Handles successful Data response")
    func testSuccessfulDataResponse() throws {
        let responseData = Data([0x00, 0x01, 0x02, 0x03])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try DataInterface.handle((data: responseData, response: httpResponse))

        #expect(result == responseData)
    }

    @Test("Handles multiple success status codes")
    func testMultipleSuccessCodes() throws {
        let responseData = """
        {"message": "created", "code": 201}
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try TestInterface.handle((data: responseData, response: httpResponse))

        #expect(result.message == "created")
        #expect(result.code == 201)
    }

    // MARK: - Error Response Handling

    @Test("Throws unknownResponse for non-HTTP response")
    func testNonHTTPResponse() {
        let responseData = Data()
        let response = URLResponse(
            url: URL(string: "https://api.example.com")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        #expect(throws: ResponseError.self) {
            try TestInterface.handle((data: responseData, response: response))
        }
    }

    @Test("Throws unknownResponseCase for undefined status code")
    func testUndefinedStatusCode() {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 404, // Not defined in responseCases
            httpVersion: nil,
            headerFields: nil
        )!

        #expect(throws: ResponseError.self) {
            try TestInterface.handle((data: responseData, response: httpResponse))
        }
    }

    @Test("Throws generic error for predefined failure")
    func testPredefinedFailureResponse() {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try TestInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            // Verify it's a generic error
            if case .generic(_, _, let underlyingError) = error {
                #expect(underlyingError is TestError)
            } else {
                #expect(Bool(false), "Expected .generic error case")
            }
        }
    }

    @Test("Throws decoding error for invalid JSON")
    func testInvalidJSONResponse() {
        let responseData = "invalid json".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try TestInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            // Verify it's a decoding error
            if case .decoding(_, _, let decodingError) = error {
                if case .jsonDecoder = decodingError {
                    // Expected
                } else {
                    #expect(Bool(false), "Expected jsonDecoder error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    @Test("Throws missingString error for invalid UTF-8")
    func testInvalidUTF8StringResponse() {
        let responseData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try StringInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .missingString = decodingError {
                    // Expected
                } else {
                    #expect(Bool(false), "Expected missingString error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    // MARK: - Decode Function Tests

    @Test("Decodes JSON response directly")
    func testDecodeJSONDirect() throws {
        let responseData = """
        {"message": "direct", "code": 100}
        """.data(using: .utf8)!

        let result = try TestInterface.decode(response: responseData)

        #expect(result.message == "direct")
        #expect(result.code == 100)
    }

    @Test("Decodes String response directly")
    func testDecodeStringDirect() throws {
        let responseData = "Test String".data(using: .utf8)!

        let result = try StringInterface.decode(response: responseData)

        #expect(result == "Test String")
    }

    @Test("Decodes Data response directly")
    func testDecodeDataDirect() throws {
        let responseData = Data([0x10, 0x20, 0x30])

        let result = try DataInterface.decode(response: responseData)

        #expect(result == responseData)
    }

    @Test("Throws jsonDecoder error for malformed JSON")
    func testDecodeMalformedJSON() {
        let responseData = "{invalid}".data(using: .utf8)!

        #expect(throws: InterfaceDecodingError.self) {
            try TestInterface.decode(response: responseData)
        }
    }

    // MARK: - Complex JSON Structures

    @Test("Handles nested JSON structures")
    func testNestedJSON() throws {
        struct NestedResponse: Codable, Sendable {
            struct User: Codable, Sendable {
                let name: String
                let id: Int
            }
            let user: User
            let timestamp: String
        }

        struct NestedInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/nested"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = NestedResponse

            static var responseCases: ResponseCases {
                [200: .success(NestedResponse.self)]
            }
        }

        let responseData = """
        {
            "user": {
                "name": "John Doe",
                "id": 123
            },
            "timestamp": "2025-01-16T12:00:00Z"
        }
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try NestedInterface.handle((data: responseData, response: httpResponse))

        #expect(result.user.name == "John Doe")
        #expect(result.user.id == 123)
        #expect(result.timestamp == "2025-01-16T12:00:00Z")
    }

    @Test("Handles array responses")
    func testArrayResponse() throws {
        struct ArrayInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/array"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = [String]

            static var responseCases: ResponseCases {
                [200: .success([String].self)]
            }
        }

        let responseData = """
        ["apple", "banana", "cherry"]
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try ArrayInterface.handle((data: responseData, response: httpResponse))

        #expect(result.count == 3)
        #expect(result[0] == "apple")
        #expect(result[1] == "banana")
        #expect(result[2] == "cherry")
    }

    // MARK: - Empty Responses

    @Test("Handles empty JSON object")
    func testEmptyJSONObject() throws {
        struct EmptyResponse: Codable, Sendable {}

        struct EmptyInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/empty"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = EmptyResponse

            static var responseCases: ResponseCases {
                [204: .success(EmptyResponse.self)]
            }
        }

        let responseData = "{}".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try EmptyInterface.handle((data: responseData, response: httpResponse))

        // Just verify it doesn't throw - result is always non-nil for struct types
        _ = result
    }

    @Test("Handles empty string response")
    func testEmptyStringResponse() throws {
        let responseData = "".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try StringInterface.handle((data: responseData, response: httpResponse))

        #expect(result == "")
    }

    @Test("Handles empty data response")
    func testEmptyDataResponse() throws {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try DataInterface.handle((data: responseData, response: httpResponse))

        #expect(result.isEmpty)
    }

}
