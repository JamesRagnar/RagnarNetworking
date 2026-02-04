//
//  DataTaskProviderTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Testing
import Foundation
@testable import RagnarNetworking

@Suite("DataTaskProvider Tests")
struct DataTaskProviderTests {

    // MARK: - Test Fixtures

    struct TestResponse: Codable, Sendable {
        let id: Int
        let name: String
    }

    struct TestInterface: Interface {
        struct Parameters: RequestParameters {
            typealias Body = EmptyBody
            let method: RequestMethod = .get
            let path: String
            let queryItems: [String: String?]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody? = nil
            let authentication: AuthenticationType = .none
        }

        typealias Response = TestResponse

        static var responseCases: ResponseCases {
            [
                200: .success(TestResponse.self),
                404: .failure(TestError.notFound)
            ]
        }
    }

    enum TestError: Error {
        case notFound
        case networkError
    }

    // Mock DataTaskProvider that doesn't make real network requests
    actor MockDataTaskProvider: DataTaskProvider {
        var mockResponse: (Data, URLResponse)?
        var shouldThrow: Error?
        var capturedRequest: URLRequest?

        func setMockResponse(data: Data, statusCode: Int, url: URL) {
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            mockResponse = (data, httpResponse)
        }

        func setError(_ error: Error) {
            shouldThrow = error
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            capturedRequest = request

            if let error = shouldThrow {
                throw error
            }

            guard let response = mockResponse else {
                throw TestError.networkError
            }

            return response
        }

        func reset() {
            mockResponse = nil
            shouldThrow = nil
            capturedRequest = nil
        }
    }

    // MARK: - Default Implementation Tests

    @Test("Default implementation constructs request and handles response")
    func testDefaultImplementationSuccess() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = """
        {"id": 1, "name": "John Doe"}
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        let result = try await provider.dataTask(
            TestInterface.self,
            params,
            config
        )

        #expect(result.id == 1)
        #expect(result.name == "John Doe")

        // Verify request was constructed correctly
        let capturedRequest = await provider.capturedRequest
        #expect(capturedRequest?.url?.path == "/users/1")
        #expect(capturedRequest?.httpMethod == "GET")
    }

    @Test("Default implementation handles error responses")
    func testDefaultImplementationErrorResponse() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = TestInterface.Parameters(path: "/users/999")

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: Data(), statusCode: 404, url: url)

        await #expect(throws: ResponseError.self) {
            try await provider.dataTask(
                TestInterface.self,
                params,
                config
            )
        }
    }

    @Test("Default implementation propagates network errors")
    func testDefaultImplementationNetworkError() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = TestInterface.Parameters(path: "/test")

        let provider = MockDataTaskProvider()
        await provider.setError(TestError.networkError)

        await #expect(throws: TestError.self) {
            try await provider.dataTask(
                TestInterface.self,
                params,
                config
            )
        }
    }

    @Test("Default implementation passes configuration to request builder")
    func testDefaultImplementationUsesConfiguration() async throws {
        let url = URL(string: "https://custom.api.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")

        struct AuthInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/secure"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .bearer
            }

            typealias Response = TestResponse

            static var responseCases: ResponseCases {
                [200: .success(TestResponse.self)]
            }
        }

        let params = AuthInterface.Parameters()
        let responseData = """
        {"id": 1, "name": "Secure Data"}
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        let result = try await provider.dataTask(
            AuthInterface.self,
            params,
            config
        )

        #expect(result.name == "Secure Data")

        // Verify auth token was added
        let capturedRequest = await provider.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("Uses custom InterfaceConstructor when provided")
    func testCustomConstructorIsUsed() async throws {
        struct CustomConstructor: InterfaceConstructor {
            static func applyHeaders(
                _ headers: [String: String]?,
                authentication: AuthenticationType,
                authToken: String?,
                to request: inout URLRequest
            ) throws(RequestError) {
                try URLRequest.applyHeaders(
                    headers,
                    authentication: authentication,
                    authToken: authToken,
                    to: &request
                )

                var current = request.allHTTPHeaderFields ?? [:]
                current["X-Test-Constructor"] = "true"
                request.allHTTPHeaderFields = current
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = """
        {"id": 1, "name": "John Doe"}
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        _ = try await provider.dataTask(
            TestInterface.self,
            params,
            config,
            constructor: CustomConstructor.self
        )

        let capturedRequest = await provider.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Test-Constructor") == "true")
    }

    // MARK: - URLSession Conformance Tests

    @Test("URLSession conforms to DataTaskProvider")
    func testURLSessionConformance() {
        let session = URLSession.shared
        let _: any DataTaskProvider = session

        // Just verify it compiles, proving conformance
    }

    // MARK: - Integration with Interface Types

    @Test("Works with String response type")
    func testStringResponseType() async throws {
        struct StringInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/message"
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

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = StringInterface.Parameters()

        let responseData = "Hello, World!".data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        let result = try await provider.dataTask(
            StringInterface.self,
            params,
            config
        )

        #expect(result == "Hello, World!")
    }

    @Test("Works with Data response type")
    func testDataResponseType() async throws {
        struct DataInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/binary"
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

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = DataInterface.Parameters()

        let responseData = Data([0x00, 0x01, 0x02, 0x03])

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        let result = try await provider.dataTask(
            DataInterface.self,
            params,
            config
        )

        #expect(result == responseData)
    }

    @Test("Works with complex nested response types")
    func testComplexNestedResponseType() async throws {
        struct ComplexResponse: Codable, Sendable {
            struct User: Codable, Sendable {
                let id: Int
                let email: String
            }
            let user: User
            let token: String
        }

        struct ComplexInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .post
                let path = "/login"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = ComplexResponse

            static var responseCases: ResponseCases {
                [200: .success(ComplexResponse.self)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ComplexInterface.Parameters()

        let responseData = """
        {
            "user": {
                "id": 42,
                "email": "user@example.com"
            },
            "token": "jwt-token-here"
        }
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        let result = try await provider.dataTask(
            ComplexInterface.self,
            params,
            config
        )

        #expect(result.user.id == 42)
        #expect(result.user.email == "user@example.com")
        #expect(result.token == "jwt-token-here")
    }

    @Test("Works with array response types")
    func testArrayResponseType() async throws {
        struct Item: Codable, Sendable {
            let id: Int
            let name: String
        }

        struct ArrayInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/items"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .none
            }

            typealias Response = [Item]

            static var responseCases: ResponseCases {
                [200: .success([Item].self)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = ArrayInterface.Parameters()

        let responseData = """
        [
            {"id": 1, "name": "First"},
            {"id": 2, "name": "Second"},
            {"id": 3, "name": "Third"}
        ]
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        let result = try await provider.dataTask(
            ArrayInterface.self,
            params,
            config
        )

        #expect(result.count == 3)
        #expect(result[0].name == "First")
        #expect(result[1].name == "Second")
        #expect(result[2].name == "Third")
    }

    // MARK: - Request Construction Tests

    @Test("Passes all request parameters correctly")
    func testRequestParametersPassed() async throws {
        struct CompleteParameters: RequestParameters {
            typealias Body = BinaryBody
            let method: RequestMethod = .post
            let path = "/api/resource"
            let queryItems: [String: String?]? = ["page": "1"]
            let headers: [String: String]? = ["X-Custom": "value"]
            let body: BinaryBody?
            let authentication: AuthenticationType = .bearer
        }

        struct CompleteInterface: Interface {
            typealias Parameters = CompleteParameters
            typealias Response = TestResponse

            static var responseCases: ResponseCases {
                [200: .success(TestResponse.self)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "auth-token")
        let bodyData = "{\"test\":\"data\"}".data(using: .utf8)!
        let params = CompleteParameters(body: BinaryBody(data: bodyData, contentType: "application/octet-stream"))

        let responseData = """
        {"id": 1, "name": "Test"}
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        _ = try await provider.dataTask(
            CompleteInterface.self,
            params,
            config
        )

        let capturedRequest = await provider.capturedRequest

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/api/resource")
        #expect(capturedRequest?.url?.query?.contains("page=1") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer auth-token")
        #expect(capturedRequest?.httpBody == bodyData)
    }

    @Test("Throws RequestError when configuration is invalid")
    func testInvalidConfiguration() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url) // No auth token

        struct AuthRequiredInterface: Interface {
            struct Parameters: RequestParameters {
                typealias Body = EmptyBody
                let method: RequestMethod = .get
                let path = "/secure"
                let queryItems: [String: String?]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody? = nil
                let authentication: AuthenticationType = .bearer // Requires token
            }

            typealias Response = TestResponse

            static var responseCases: ResponseCases {
                [200: .success(TestResponse.self)]
            }
        }

        let params = AuthRequiredInterface.Parameters()
        let provider = MockDataTaskProvider()

        await #expect(throws: RequestError.self) {
            try await provider.dataTask(
                AuthRequiredInterface.self,
                params,
                config
            )
        }
    }

    // MARK: - Sendable Conformance Tests

    @Test("DataTaskProvider operations are Sendable-safe")
    func testSendableConformance() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url)
        let params = TestInterface.Parameters(path: "/test")

        let responseData = """
        {"id": 1, "name": "Test"}
        """.data(using: .utf8)!

        let provider = MockDataTaskProvider()
        await provider.setMockResponse(data: responseData, statusCode: 200, url: url)

        // This compiles and runs, proving Sendable safety
        async let result1 = provider.dataTask(TestInterface.self, params, config)
        async let result2 = provider.dataTask(TestInterface.self, params, config)

        let (r1, r2) = try await (result1, result2)

        #expect(r1.id == 1)
        #expect(r2.id == 1)
    }

}
