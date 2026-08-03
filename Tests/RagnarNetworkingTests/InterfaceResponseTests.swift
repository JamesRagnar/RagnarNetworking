//
//  InterfaceResponseTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("Interface Response Handling Tests", .timeLimit(.minutes(1)))
struct InterfaceResponseTests {

    // MARK: - Test Fixtures

    struct SuccessResponse: Codable, Sendable, InterfaceResponse {
        let message: String
        let code: Int
    }

    struct TestInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/test"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        static let responses = ResponseContract<Response>(
            success: .exact(200),
            additionalSuccesses: [.exact(201)],
            failures: [
                .code(400, .error(TestError.badRequest)),
                .code(401, .error(TestError.unauthorized)),
                .code(500, .error(TestError.serverError))
            ]
        )
    }

    struct StringInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/string"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = String

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    struct DataInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/data"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = Data

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    struct NoContentInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/no-content"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = Data

        static let responses = ResponseContract<Response>(success: .exact(204))
    }

    struct NoContentStringInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/no-content-string"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = String

        static let responses = ResponseContract<Response>(success: .exact(204))
    }

    struct NoContentJSONInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/no-content-json"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        static let responses = ResponseContract<Response>(success: .exact(204))
    }

    struct EmptyDecodeInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/empty-decode"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = EmptyResponse

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    struct SnakeCaseResponse: Codable, Sendable, Equatable, InterfaceResponse {
        let userId: Int
    }

    struct SnakeCaseInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/snake-case"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SnakeCaseResponse

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    struct DatedResponse: Codable, Sendable, Equatable, InterfaceResponse {
        let createdAt: Date
    }

    struct DatedInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/dated"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = DatedResponse

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    struct RangeInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/range"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        static let responses = ResponseContract<Response>(success: .success)
    }

    struct OverlapInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/overlap"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        static let responses = ResponseContract<Response>(
            success: .success,
            failures: [.code(201, .error(TestError.unauthorized))]
        )
    }

    struct DecodeErrorInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/decode-error"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        struct APIError: Decodable, Sendable, Error {
            let error: String
        }

        struct CustomError: Sendable, Error {
            let message: String
        }

        static let responses = ResponseContract<Response>(
            success: .exact(200),
            failures: [
                .code(400, .decodeError(APIError.self)),
                .code(418, .decodeError(body: { data, _ in
                    guard let message = String(data: data, encoding: .utf8) else {
                        return CustomError(message: "")
                    }
                    return CustomError(message: message)
                }))
            ]
        )
    }

    struct SnakeCaseDecodeErrorInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/snake-case-decode-error"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        struct SnakeCaseAPIError: Decodable, Sendable, Error, Equatable {
            let errorCode: Int
        }

        static let responses = ResponseContract<Response>(
            success: .exact(200),
            failures: [.code(400, .decodeError(SnakeCaseAPIError.self))]
        )
    }

    struct ThrowingDecodeErrorInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/decode-error-throws"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        struct CustomThrownError: Error, Sendable {
            let message: String
        }

        static let responses = ResponseContract<Response>(
            success: .exact(200),
            failures: [
                .code(400, .decodeError(body: { _, _ in
                    throw CustomThrownError(message: "decode closure failed")
                }))
            ]
        )
    }

    struct EmptyTolerantResponse: Decodable, Sendable, InterfaceResponse {
        private enum CodingKeys: String, CodingKey {
            case ignored
        }

        init(from decoder: Decoder) throws {
            _ = try decoder.container(keyedBy: CodingKeys.self)
        }
    }

    struct NoContentCustomDecodableInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/no-content-custom-decoding"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = EmptyTolerantResponse

        static let responses = ResponseContract<Response>(success: .exact(204))
    }

    struct RangeOrderInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/range-order"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = SuccessResponse

        static let responses = ResponseContract<Response>(
            success: .exact(204),
            failures: [
                .range(200..<300, .error(TestError.badRequest)),
                .range(200..<400, .error(TestError.unauthorized))
            ]
        )
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

        let result = try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

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

        let result = try StringInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

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

        let result = try DataInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result == responseData)
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

        let result = try NoContentInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result.isEmpty)
    }

    @Test("no-content with Decodable response throws decoding error")
    func testNoContentDecodableThrowsDecodingError() {
        let responseData = Data()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try NoContentJSONInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
            #expect(Bool(false), "Should have thrown")
        } catch let error {
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

    @Test("no-content with custom Decodable still throws decoding error for empty payload")
    func testNoContentCustomDecodableThrowsDecodingError() {
        let responseData = Data()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try NoContentCustomDecodableInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .jsonDecoder(let diagnostics) = decodingError {
                    #expect(diagnostics.kind == .dataCorrupted)
                } else {
                    #expect(Bool(false), "Expected jsonDecoder error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    @Test("no-content with String response returns empty string")
    func testNoContentStringReturnsEmptyString() throws {
        let responseData = Data()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try NoContentStringInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result == "")
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

        let result = try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

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

        let result = try RangeInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

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
            _ = try OverlapInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path = "/category"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = SuccessResponse

            static let responses = ResponseContract<Response>(
                success: .exact(200),
                failures: [.clientError(.error(TestError.badRequest))]
            )
        }

        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 418,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try CategoryInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            try TestInterface.handleResponse((data: responseData, response: response), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
        }
    }

    @Test("Throws unknownResponseCase for undefined status code")
    func testUndefinedStatusCode() {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 404, // Not defined in responses
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try DecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try DecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .jsonDecoder(let diagnostics) = decodingError {
                    #expect(diagnostics.debugDescription.isEmpty == false)
                } else {
                    #expect(Bool(false), "Expected jsonDecoder error")
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
            _ = try DecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .jsonDecoder(let diagnostics) = decodingError {
                    #expect(diagnostics.debugDescription.isEmpty == false)
                } else {
                    #expect(Bool(false), "Expected jsonDecoder error")
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
            _ = try DecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .jsonDecoder(let diagnostics) = decodingError {
                    #expect(diagnostics.debugDescription.isEmpty == false)
                } else {
                    #expect(Bool(false), "Expected jsonDecoder error")
                }
            } else {
                #expect(Bool(false), "Expected .decoding error case")
            }
        }
    }

    @Test("decodeError closure thrown errors map to custom decoding errors")
    func testDecodeErrorCustomClosureThrownError() {
        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try ThrowingDecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
            #expect(Bool(false), "Should have thrown")
        } catch let error {
            if case .decoding(_, _, let decodingError) = error {
                if case .custom(let message) = decodingError {
                    #expect(message.contains("decode closure failed"))
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
            _ = try DecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try DecodeErrorInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try RangeOrderInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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
            _ = try StringInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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

    /// A snapshot for `decode` call sites that do not exercise response metadata.
    static func snapshot(
        statusCode: Int = 200,
        headers: [String: String]? = nil
    ) -> HTTPResponseSnapshot {
        HTTPResponseSnapshot(
            response: HTTPURLResponse(
                url: URL(string: "https://api.example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
        )
    }

    @Test("Decodes JSON response directly")
    func testDecodeJSONDirect() throws {
        let responseData = """
        {"message": "direct", "code": 100}
        """.data(using: .utf8)!

        let result = try DefaultResponseHandler().decode(
            responseData,
            as: TestInterface.self,
            metadata: Self.snapshot(),
            responseDecoder: ResponseDecoder()
        )

        #expect(result.message == "direct")
        #expect(result.code == 100)
    }

    @Test("Decodes String response directly")
    func testDecodeStringDirect() throws {
        let responseData = "Test String".data(using: .utf8)!

        let result = try DefaultResponseHandler().decode(
            responseData,
            as: StringInterface.self,
            metadata: Self.snapshot(),
            responseDecoder: ResponseDecoder()
        )

        #expect(result == "Test String")
    }

    @Test("Decodes Data response directly")
    func testDecodeDataDirect() throws {
        let responseData = Data([0x10, 0x20, 0x30])

        let result = try DefaultResponseHandler().decode(
            responseData,
            as: DataInterface.self,
            metadata: Self.snapshot(),
            responseDecoder: ResponseDecoder()
        )

        #expect(result == responseData)
    }

    @Test("Throws jsonDecoder error for malformed JSON")
    func testDecodeMalformedJSON() {
        let responseData = "{invalid}".data(using: .utf8)!

        #expect(throws: InterfaceDecodingError.self) {
            try DefaultResponseHandler().decode(
                responseData,
                as: TestInterface.self,
                metadata: Self.snapshot(),
                responseDecoder: ResponseDecoder()
            )
        }
    }

    // MARK: - Complex JSON Structures

    @Test("Handles nested JSON structures")
    func testNestedJSON() throws {
        struct NestedResponse: Codable, Sendable, InterfaceResponse {
            struct User: Codable, Sendable {
                let name: String
                let id: Int
            }
            let user: User
            let timestamp: String
        }

        struct NestedInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path = "/nested"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = NestedResponse

            static let responses = ResponseContract<Response>(success: .exact(200))
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

        let result = try NestedInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result.user.name == "John Doe")
        #expect(result.user.id == 123)
        #expect(result.timestamp == "2025-01-16T12:00:00Z")
    }

    @Test("Handles array responses")
    func testArrayResponse() throws {
        struct ArrayInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path = "/array"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = [String]

            static let responses = ResponseContract<Response>(success: .exact(200))
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

        let result = try ArrayInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result.count == 3)
        #expect(result[0] == "apple")
        #expect(result[1] == "banana")
        #expect(result[2] == "cherry")
    }

    // MARK: - Empty Responses

    @Test("Handles empty JSON object")
    func testEmptyJSONObject() throws {
        struct EmptyInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path = "/empty"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = EmptyResponse

            static let responses = ResponseContract<Response>(success: .exact(204))
        }

        let responseData = "{}".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try EmptyInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result == EmptyResponse())
    }

    @Test("EmptyResponse decode ignores non-empty body")
    func testEmptyResponseDecodeIgnoresBody() throws {
        let responseData = "non-empty".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try EmptyDecodeInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result == EmptyResponse())
    }

    @Test("Handles no-content success with EmptyResponse")
    func testNoContentEmptyResponse() throws {
        struct EmptyInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path = "/no-content"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = EmptyResponse

            static let responses = ResponseContract<Response>(success: .exact(204))
        }

        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try EmptyInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
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

        let result = try StringInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

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

        let result = try DataInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())

        #expect(result.isEmpty)
    }

    @Test("Handles many concurrent response decodes safely")
    func testConcurrentHandleCalls() async throws {
        let responseData = """
        {"message": "concurrent", "code": 200}
        """.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let expectedCount = 200

        let results = try await withThrowingTaskGroup(of: SuccessResponse.self) { group in
            for _ in 0..<expectedCount {
                group.addTask {
                    try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
                }
            }

            var responses: [SuccessResponse] = []
            responses.reserveCapacity(expectedCount)
            for try await response in group {
                responses.append(response)
            }
            return responses
        }

        #expect(results.count == expectedCount)
        #expect(results.allSatisfy { $0.message == "concurrent" && $0.code == 200 })
    }

    // MARK: - Composing a Custom ResponseHandler on DefaultResponseHandler

    /// Delegates to `DefaultResponseHandler.handle` instead of reimplementing status-code
    /// matching, demonstrating the composition pattern that `handle` and `decode` being
    /// public (rather than internal) enables.
    struct ComposingResponseHandler: ResponseHandler {
        private let base = DefaultResponseHandler()

        func handle<T: Interface>(
            _ response: (data: Data, response: URLResponse),
            for interface: T.Type,
            context: ResponseContext
        ) throws(ResponseError) -> T.Response {
            // A real handler would inspect the raw response here before delegating.
            try base.handle(response, for: interface, context: context)
        }
    }

    @Test("Composed ResponseHandler produces the same result as the default handler for the success path")
    func testComposedHandlerMatchesDefaultForSuccess() throws {
        let responseData = try JSONEncoder().encode(SuccessResponse(message: "ok", code: 200))
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let expected = try TestInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
        let actual = try ComposingResponseHandler().handle((data: responseData, response: httpResponse), for: TestInterface.self, context: ResponseContext(responseDecoder: ResponseDecoder()))

        #expect(actual.message == expected.message)
        #expect(actual.code == expected.code)
    }

    @Test("Composed ResponseHandler produces the same result as the default handler for a no-body success")
    func testComposedHandlerMatchesDefaultForNoBodySuccess() throws {
        struct NoContentEmptyInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .get
                let path = "/no-content-empty"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = EmptyResponse

            static let responses = ResponseContract<Response>(success: .exact(204))
        }

        let responseData = Data()
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let expected = try NoContentEmptyInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
        let actual = try ComposingResponseHandler().handle(
            (data: responseData, response: httpResponse),
            for: NoContentEmptyInterface.self,
            context: ResponseContext(responseDecoder: ResponseDecoder())
        )

        #expect(actual == expected)
    }

    @Test("Composed ResponseHandler produces the same result as the default handler for the error path")
    func testComposedHandlerMatchesDefaultForError() {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try ComposingResponseHandler().handle((data: Data(), response: httpResponse), for: TestInterface.self, context: ResponseContext(responseDecoder: ResponseDecoder()))
            Issue.record("Expected ResponseError.generic to be thrown")
        } catch {
            #expect(error.statusCode == 400)
        }
    }

    // MARK: - Response Decoder Tests

    @Test("A configured responseDecoder decodes snake_case keys into camelCase properties")
    func testConfiguredResponseDecoderConvertsSnakeCase() throws {
        let responseData = #"{"user_id": 42}"#.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try SnakeCaseInterface.handleResponse(
            (data: responseData, response: httpResponse),
            context: ResponseContext(responseDecoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)),
            handler: DefaultResponseHandler()
        )

        #expect(result.userId == 42)
    }

    @Test("A configured responseDecoder decodes ISO-8601 dates; the default decoder fails on the same payload")
    func testConfiguredResponseDecoderHandlesISO8601Dates() throws {
        let responseData = #"{"createdAt": "2026-02-03T10:00:00Z"}"#.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try DatedInterface.handleResponse(
            (data: responseData, response: httpResponse),
            context: ResponseContext(responseDecoder: ResponseDecoder(dateDecodingStrategy: .iso8601)),
            handler: DefaultResponseHandler()
        )
        let expectedDate = ISO8601DateFormatter().date(from: "2026-02-03T10:00:00Z")
        #expect(result.createdAt == expectedDate)

        #expect(throws: ResponseError.self) {
            try DatedInterface.handleResponse((data: responseData, response: httpResponse), context: ResponseContext(responseDecoder: ResponseDecoder()), handler: DefaultResponseHandler())
        }
    }

    @Test("ResponseError.decodeError(as:) decodes the body with the decoder the response carried")
    func testResponseErrorDecodeErrorUsesCarriedDecoder() {
        let responseData = #"{"error_code": 42}"#.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        // Simulate a raw failure that was never routed through FailureOutcome.decodeError,
        // so decodeError(as:) has to decode the body itself.
        let error = ResponseError.unknownResponseCase(
            ResponseBody(responseData, decoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)),
            HTTPResponseSnapshot(response: httpResponse)
        )

        #expect(error.decodeError(as: SnakeCaseDecodeErrorInterface.SnakeCaseAPIError.self)?.errorCode == 42)

        // The same body with a plain decoder cannot read the snake_case key.
        let plainError = ResponseError.unknownResponseCase(
            ResponseBody(responseData),
            HTTPResponseSnapshot(response: httpResponse)
        )
        #expect(plainError.decodeError(as: SnakeCaseDecodeErrorInterface.SnakeCaseAPIError.self) == nil)
    }

    @Test("FailureOutcome.decodeError decodes structured error bodies with the response's decoder")
    func testFailureOutcomeDecodeErrorUsesResponseDecoder() {
        let responseData = #"{"error_code": 99}"#.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try SnakeCaseDecodeErrorInterface.handleResponse(
                (data: responseData, response: httpResponse),
                context: ResponseContext(responseDecoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)),
                handler: DefaultResponseHandler()
            )
            Issue.record("Expected ResponseError.decoded to be thrown")
        } catch {
            guard case .decoded(_, _, let decodedError) = error,
                  let apiError = decodedError as? SnakeCaseDecodeErrorInterface.SnakeCaseAPIError else {
                Issue.record("Expected .decoded with SnakeCaseAPIError")
                return
            }
            #expect(apiError.errorCode == 99)
        }
    }

    @Test("FailureOutcome.decodeError fails when the response decoder cannot read the error body")
    func testFailureOutcomeDecodeErrorRespectsPlainDecoder() {
        let responseData = #"{"error_code": 99}"#.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        // A plain decoder cannot map error_code -> errorCode, so the outcome surfaces as a
        // decoding failure rather than a decoded error. This is the observable proof that the
        // error body goes through the same decoder as success bodies.
        do {
            _ = try SnakeCaseDecodeErrorInterface.handleResponse(
                (data: responseData, response: httpResponse),
                context: ResponseContext(responseDecoder: ResponseDecoder()),
                handler: DefaultResponseHandler()
            )
            Issue.record("Expected ResponseError.decoding to be thrown")
        } catch {
            guard case .decoding = error else {
                Issue.record("Expected .decoding, got \(error)")
                return
            }
        }
    }

    // MARK: - Custom InterfaceResponse Conformances

    /// A non-JSON response type. Before `InterfaceResponse`, a response shape outside the
    /// built-in `Decodable`/`String`/`Data`/`EmptyResponse` set could not be expressed without
    /// editing the package's decode ladder.
    struct CSVRows: InterfaceResponse, Sendable, Equatable {
        let rows: [[String]]

        static func decode(
            from data: Data,
            metadata: HTTPResponseSnapshot,
            using decoder: ResponseDecoder
        ) throws -> CSVRows {
            guard let text = String(data: data, encoding: .utf8) else {
                throw InterfaceDecodingError.missingString
            }

            let rows = text
                .split(separator: "\n")
                .map { $0.split(separator: ",").map(String.init) }

            return CSVRows(rows: rows)
        }
    }

    struct CSVInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/report.csv"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = CSVRows

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    @Test("A non-JSON InterfaceResponse conformance decodes without any change to the package")
    func testCustomInterfaceResponseConformance() throws {
        let responseData = "a,b\nc,d".data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try CSVInterface.handleResponse(
            (data: responseData, response: httpResponse),
            context: ResponseContext(responseDecoder: ResponseDecoder()),
            handler: DefaultResponseHandler()
        )

        #expect(result == CSVRows(rows: [["a", "b"], ["c", "d"]]))
    }

    /// An `InterfaceResponse` that throws its own error type, proving a conformance is not
    /// required to launder failures through `InterfaceDecodingError`.
    struct StrictlyPositiveCount: InterfaceResponse, Sendable {
        enum Failure: Error { case notPositive }

        let value: Int

        static func decode(
            from data: Data,
            metadata: HTTPResponseSnapshot,
            using decoder: ResponseDecoder
        ) throws -> StrictlyPositiveCount {
            let value = try decoder.makeJSONDecoder().decode(Int.self, from: data)
            guard value > 0 else { throw Failure.notPositive }
            return StrictlyPositiveCount(value: value)
        }
    }

    struct CountInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/count"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = StrictlyPositiveCount

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    @Test("An InterfaceResponse throwing its own error type surfaces as ResponseError.decoding")
    func testCustomInterfaceResponseErrorIsNormalized() {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            _ = try CountInterface.handleResponse(
                (data: "0".data(using: .utf8)!, response: httpResponse),
                context: ResponseContext(responseDecoder: ResponseDecoder()),
                handler: DefaultResponseHandler()
            )
            Issue.record("Expected ResponseError.decoding to be thrown")
        } catch {
            guard case .decoding(_, _, let decodingError) = error else {
                Issue.record("Expected .decoding, got \(error)")
                return
            }
            guard case .custom(let message) = decodingError else {
                Issue.record("Expected .custom, got \(decodingError)")
                return
            }
            #expect(message.contains("notPositive"))
        }
    }

    // MARK: - Configuration-level Response Handler

    /// A server-wide concern: every response is wrapped in `{ "data": ... }`. Written once on
    /// the configuration rather than restated on every Interface.
    struct UnwrappingResponseHandler: ResponseHandler {
        private let base = DefaultResponseHandler()

        func handle<T: Interface>(
            _ response: (data: Data, response: URLResponse),
            for interface: T.Type,
            context: ResponseContext
        ) throws(ResponseError) -> T.Response {
            let snapshot = HTTPResponseSnapshot(
                response: response.response,
                redactedQueryItemNames: context.redactedQueryItemNames
            )
            let body = ResponseBody(response.data, decoder: context.responseDecoder)

            guard
                let envelope = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
                let inner = envelope["data"],
                let unwrapped = try? JSONSerialization.data(withJSONObject: inner)
            else {
                throw .decoding(body, snapshot, .custom(message: "Missing data envelope"))
            }

            return try base.handle(
                (data: unwrapped, response: response.response),
                for: interface,
                context: context
            )
        }
    }

    @Test("A configuration-level responseHandler applies to Interfaces")
    func testConfigurationResponseHandlerApplies() throws {
        let responseData = #"{"data":{"message":"hello","code":200}}"#.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try TestInterface.handleResponse(
            (data: responseData, response: httpResponse),
            context: ResponseContext(responseDecoder: ResponseDecoder()),
            handler: UnwrappingResponseHandler()
        )

        #expect(result.message == "hello")
    }

    // MARK: - Built-in InterfaceResponse Conformances

    struct CollectionInterface<T: InterfaceResponse & Sendable>: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/collection"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = T

        static var responses: ResponseContract<Response> {
            ResponseContract(success: .exact(200))
        }
    }

    private func decodeCollection<T: InterfaceResponse & Sendable>(
        _ type: T.Type,
        from json: String
    ) throws -> T {
        try DefaultResponseHandler().decode(
            json.data(using: .utf8)!,
            as: CollectionInterface<T>.self,
            metadata: Self.snapshot(),
            responseDecoder: ResponseDecoder()
        )
    }

    @Test("Array response decodes a top-level JSON array")
    func testArrayConformance() throws {
        #expect(try decodeCollection([Int].self, from: "[1,2,3]") == [1, 2, 3])
        #expect(try decodeCollection([String].self, from: #"["a","b"]"#) == ["a", "b"])
        #expect(try decodeCollection([[Int]].self, from: "[[1],[2]]") == [[1], [2]])
    }

    @Test("Dictionary response decodes a JSON object for String and Int keys")
    func testDictionaryConformanceForObjectKeys() throws {
        #expect(try decodeCollection([String: Int].self, from: #"{"a":1}"#) == ["a": 1])
        #expect(try decodeCollection([Int: String].self, from: #"{"1":"x"}"#) == [1: "x"])
    }

    enum PlainKey: String, Decodable, Hashable, Sendable {
        case alpha
    }

    enum RepresentableKey: String, Decodable, Hashable, Sendable, CodingKeyRepresentable {
        case alpha
    }

    /// Pins the stdlib behavior the `Dictionary` conformance inherits: a key type that is
    /// neither `String`, `Int`, nor `CodingKeyRepresentable` decodes from an alternating
    /// unkeyed array, not from an object. Documented on the conformance because it is
    /// surprising, and pinned here because it is not ours to change.
    @Test("Dictionary with a non-representable key decodes from an array, not an object")
    func testDictionaryConformanceForNonRepresentableKeys() throws {
        #expect(throws: InterfaceDecodingError.self) {
            try decodeCollection([PlainKey: Int].self, from: #"{"alpha":1}"#)
        }

        #expect(try decodeCollection([PlainKey: Int].self, from: #"["alpha",1]"#) == [.alpha: 1])

        // Conforming the key to CodingKeyRepresentable restores object decoding.
        #expect(try decodeCollection([RepresentableKey: Int].self, from: #"{"alpha":1}"#) == [.alpha: 1])
    }

    @Test("Scalar and Optional responses decode")
    func testScalarAndOptionalConformances() throws {
        #expect(try decodeCollection(Int.self, from: "42") == 42)
        #expect(try decodeCollection(Double.self, from: "1.5") == 1.5)
        #expect(try decodeCollection(Bool.self, from: "true") == true)
        #expect(try decodeCollection(String?.self, from: #""x""#) == "x")
        #expect(try decodeCollection(String?.self, from: "null") == nil)
    }

    // MARK: - Response Metadata

    /// A response whose value depends on a header. Before `decode` received the response
    /// metadata, this required writing a whole `ResponseHandler`.
    struct PagedNames: InterfaceResponse, Sendable, Equatable {
        let names: [String]
        let totalCount: Int?

        static func decode(
            from data: Data,
            metadata: HTTPResponseSnapshot,
            using decoder: ResponseDecoder
        ) throws -> PagedNames {
            let names = try decoder.makeJSONDecoder().decode([String].self, from: data)
            let header = metadata.headers.first {
                $0.key.caseInsensitiveCompare("X-Total-Count") == .orderedSame
            }

            return PagedNames(
                names: names,
                totalCount: header.flatMap { Int($0.value) }
            )
        }
    }

    struct PagedInterface: Interface {
        struct Request: InterfaceRequest {
            let method: RequestMethod = .get
            let path = "/names"
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationScheme? = nil
        }

        typealias Response = PagedNames

        static let responses = ResponseContract<Response>(success: .exact(200))
    }

    @Test("InterfaceResponse can build its value from a response header")
    func testResponseMetadataReachesDecode() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/names")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["X-Total-Count": "137"]
        )!

        let result = try PagedInterface.handleResponse(
            (data: #"["a","b"]"#.data(using: .utf8)!, response: httpResponse),
            context: ResponseContext(responseDecoder: ResponseDecoder()),
            handler: DefaultResponseHandler()
        )

        #expect(result == PagedNames(names: ["a", "b"], totalCount: 137))
    }

    @Test("Response metadata is available for a no-body success")
    func testResponseMetadataOnNoContentPath() throws {
        struct StatusEcho: InterfaceResponse, Sendable, Equatable {
            let statusCode: Int?

            static func decode(
                from data: Data,
                metadata: HTTPResponseSnapshot,
                using decoder: ResponseDecoder
            ) throws -> StatusEcho {
                StatusEcho(statusCode: metadata.statusCode)
            }
        }

        struct EchoInterface: Interface {
            struct Request: InterfaceRequest {
                let method: RequestMethod = .delete
                let path = "/thing"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationScheme? = nil
            }

            typealias Response = StatusEcho

            static let responses = ResponseContract<Response>(success: .exact(204))
        }

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/thing")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )!

        let result = try EchoInterface.handleResponse(
            (data: Data(), response: httpResponse),
            context: ResponseContext(responseDecoder: ResponseDecoder()),
            handler: DefaultResponseHandler()
        )

        #expect(result == StatusEcho(statusCode: 204))
    }

}
