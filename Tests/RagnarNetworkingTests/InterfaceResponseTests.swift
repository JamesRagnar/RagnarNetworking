//
//  InterfaceResponseTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("Interface Response Handling Tests")
struct InterfaceResponseTests {

    // MARK: - Test Fixtures

    struct SuccessResponse: Codable, Sendable {
        let message: String
        let code: Int
    }

    struct TestInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/test"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = SuccessResponse

        static var responseCases: ResponseMap {
            [
                .code(200, .decode),
                .code(201, .decode),
                .code(400, .error(TestError.badRequest)),
                .code(401, .error(TestError.unauthorized)),
                .code(500, .error(TestError.serverError))
            ]
        }
    }

    struct StringInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/string"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = String

        static var responseCases: ResponseMap {
            [.code(200, .decode)]
        }
    }

    struct DataInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/data"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = Data

        static var responseCases: ResponseMap {
            [.code(200, .decode)]
        }
    }

    struct NoContentInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/no-content"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = Data

        static var responseCases: ResponseMap {
            [.code(204, .noContent)]
        }
    }

    struct CustomHandlerInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/custom-handler"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = String

        enum CustomHandlerError: Error, Sendable {
            case notFound
        }

        static var responseCases: ResponseMap {
            [
                .code(200, .decode),
                .code(404, .error(CustomHandlerError.notFound))
            ]
        }

        static var responseHandler: ResponseHandler.Type {
            CustomHandler.self
        }

        struct CustomHandler: ResponseHandler {
            static func handle<T: Interface>(
                _ response: (data: Data, response: URLResponse),
                for interface: T.Type
            ) throws(ResponseError) -> T.Response {
                let snapshot = HTTPResponseSnapshot(response: response.response)
                guard let statusCode = snapshot.statusCode else {
                    throw ResponseError.unknownResponse(
                        response.data,
                        snapshot
                    )
                }

                if statusCode == 200 {
                    return "overridden" as! T.Response
                }

                return try DefaultResponseHandler.handle(response, for: interface)
            }
        }
    }

    struct RangeInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/range"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = SuccessResponse

        static var responseCases: ResponseMap {
            [.success(.decode)]
        }
    }

    struct OverlapInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/overlap"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = SuccessResponse

        static var responseCases: ResponseMap {
            [
                .success(.decode),
                .code(201, .error(TestError.unauthorized))
            ]
        }
    }

    struct DecodeErrorInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/decode-error"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = SuccessResponse

        struct APIError: Decodable, Sendable, Error {
            let error: String
        }

        struct CustomError: Sendable, Error {
            let message: String
        }

        static var responseCases: ResponseMap {
            [
                .code(200, .decode),
                .code(400, .decodeError(APIError.self)),
                .code(418, .decodeError(body: { data in
                    guard let message = String(data: data, encoding: .utf8) else {
                        return CustomError(message: "")
                    }
                    return CustomError(message: message)
                }))
            ]
        }
    }

    struct RangeOrderInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path = "/range-order"
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = SuccessResponse

        static var responseCases: ResponseMap {
            [
                .range(200..<300, .error(TestError.badRequest)),
                .range(200..<400, .error(TestError.unauthorized))
            ]
        }
    }

    enum TestError: Error, Sendable {
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

    @Test("Custom response handler overrides decoding")
    func testCustomHandlerOverride() throws {
        let responseData = "ignored".data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try CustomHandlerInterface.handle((data: responseData, response: httpResponse))

        #expect(result == "overridden")
    }

    @Test("Custom response handler falls back to default handler")
    func testCustomHandlerFallback() {
        let responseData = Data()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try CustomHandlerInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .generic(_, _, let underlyingError) = error {
                #expect(underlyingError is CustomHandlerInterface.CustomHandlerError)
            } else {
                #expect(Bool(false), "Expected .generic error case")
            }
        }
    }

    @Test("Handles no-content outcome")
    func testNoContentOutcome() throws {
        let responseData = Data()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try DefaultResponseHandler.handleOutcome(
            (data: responseData, response: httpResponse),
            for: NoContentInterface.self
        )

        switch result {
        case .noContent:
            break

        default:
            #expect(Bool(false), "Expected noContent outcome")
        }
    }

    @Test("handle returns empty data for no-content when Response is Data")
    func testNoContentHandleReturnsEmptyData() throws {
        let responseData = Data()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try NoContentInterface.handle((data: responseData, response: httpResponse))

        #expect(result.isEmpty)
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

    @Test("Matches range-based success codes")
    func testRangeBasedSuccess() throws {
        let responseData = """
        {"message": "range", "code": 201}
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try RangeInterface.handle((data: responseData, response: httpResponse))

        #expect(result.message == "range")
        #expect(result.code == 201)
    }

    @Test("Exact status codes beat overlapping ranges")
    func testExactBeatsRange() {
        let responseData = """
        {"message": "overlap", "code": 201}
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try OverlapInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .generic(_, _, let underlyingError) = error {
                #expect(underlyingError is TestError)
            } else {
                #expect(Bool(false), "Expected .generic error case")
            }
        }
    }

    @Test("Matches HTTP category shortcuts")
    func testCategoryShortcutMatching() {
        struct CategoryInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/category"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = SuccessResponse

            static var responseCases: ResponseMap {
                [.clientError(.error(TestError.badRequest))]
            }
        }

        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 418,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try CategoryInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .generic(_, _, let underlyingError) = error {
                #expect(underlyingError is TestError)
            } else {
                #expect(Bool(false), "Expected .generic error case")
            }
        }
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

        do {
            _ = try TestInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .unknownResponseCase = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected .unknownResponseCase error case")
            }
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

    @Test("Decodes error bodies with decodeError")
    func testDecodeErrorResponse() {
        let responseData = """
        {"error": "Invalid request"}
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try DecodeErrorInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch {
            let responseError: ResponseError = error
            if case .decoded(_, _, let decodedError) = responseError,
               let apiError = decodedError as? DecodeErrorInterface.APIError {
                #expect(apiError.error == "Invalid request")
                #expect(responseError.decodeError(as: DecodeErrorInterface.APIError.self) != nil)
            } else {
                #expect(Bool(false), "Expected .decoded error case")
            }
        }
    }

    @Test("decodeError surfaces custom decoding errors for malformed JSON")
    func testDecodeErrorInvalidJSON() {
        let responseData = "not json".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try DecodeErrorInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .custom(let message) = decodingError {
                    #expect(message.isEmpty == false)
                    // Expected
                } else {
                    #expect(Bool(false), "Expected custom decoding error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    @Test("decodeError surfaces custom decoding errors for empty bodies")
    func testDecodeErrorEmptyBody() {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try DecodeErrorInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .custom(let message) = decodingError {
                    #expect(message.isEmpty == false)
                    // Expected
                } else {
                    #expect(Bool(false), "Expected custom decoding error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    @Test("decodeError surfaces custom decoding errors for HTML bodies")
    func testDecodeErrorHTMLBody() {
        let responseData = "<html><body>Error</body></html>".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try DecodeErrorInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .custom(let message) = decodingError {
                    #expect(message.isEmpty == false)
                    // Expected
                } else {
                    #expect(Bool(false), "Expected custom decoding error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    @Test("Decoded errors participate in error inspection helpers")
    func testDecodedErrorInspectionHelpers() {
        let responseData = """
        {"error": "Inspect me"}
        """.data(using: .utf8)!

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: ["X-Request-ID": "req-123"]
        )!

        do {
            _ = try DecodeErrorInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error.statusCode == 400)
            #expect(error.responseBodyString?.contains("Inspect me") == true)
            #expect(error.header("X-Request-ID") == "req-123")
        }
    }

    @Test("decodeError supports custom decoder closures")
    func testDecodeErrorCustomClosure() {
        let responseData = "teapot".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 418,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try DecodeErrorInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoded(_, _, let decodedError) = error,
               let customError = decodedError as? DecodeErrorInterface.CustomError {
                #expect(customError.message == "teapot")
            } else {
                #expect(Bool(false), "Expected .decoded error case")
            }
        }
    }

    @Test("Range matching respects definition order")
    func testRangeOrderPriority() {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try RangeOrderInterface.handle((data: responseData, response: httpResponse))
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .generic(_, _, let underlyingError) = error,
               let testError = underlyingError as? TestError {
                #expect(testError == .badRequest)
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
                if case .jsonDecoder(let diagnostics) = decodingError {
                    #expect(diagnostics.debugDescription.isEmpty == false)
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

    // MARK: - DefaultResponseHandler Decode Tests

    @Test("Decodes JSON response directly")
    func testDecodeJSONDirect() throws {
        let responseData = """
        {"message": "direct", "code": 100}
        """.data(using: .utf8)!

        let result = try DefaultResponseHandler.decode(responseData, as: TestInterface.self)

        #expect(result.message == "direct")
        #expect(result.code == 100)
    }

    @Test("Decodes String response directly")
    func testDecodeStringDirect() throws {
        let responseData = "Test String".data(using: .utf8)!

        let result = try DefaultResponseHandler.decode(responseData, as: StringInterface.self)

        #expect(result == "Test String")
    }

    @Test("Decodes Data response directly")
    func testDecodeDataDirect() throws {
        let responseData = Data([0x10, 0x20, 0x30])

        let result = try DefaultResponseHandler.decode(responseData, as: DataInterface.self)

        #expect(result == responseData)
    }

    @Test("Throws jsonDecoder error for malformed JSON")
    func testDecodeMalformedJSON() {
        let responseData = "{invalid}".data(using: .utf8)!

        #expect(throws: InterfaceDecodingError.self) {
            try DefaultResponseHandler.decode(responseData, as: TestInterface.self)
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
                let method: RequestMethod = .get
                let path = "/nested"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = NestedResponse

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
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
                let method: RequestMethod = .get
                let path = "/array"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = [String]

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
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
        struct EmptyInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/empty"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = EmptyResponse

            static var responseCases: ResponseMap {
                [.code(204, .decode)]
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

    @Test("Handles no-content success with EmptyResponse")
    func testNoContentEmptyResponse() throws {
        struct EmptyInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/no-content"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = EmptyResponse

            static var responseCases: ResponseMap {
                [.code(204, .noContent)]
            }
        }

        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try EmptyInterface.handle((data: responseData, response: httpResponse))
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
