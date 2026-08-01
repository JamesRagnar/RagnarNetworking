//
//  RequestPipelineTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-16.
//

import Foundation
@testable import RagnarNetworking
import Testing

@Suite("RequestPipeline Tests", .timeLimit(.minutes(1)))
struct RequestPipelineTests {

    // MARK: - Test Fixtures

    struct TestResponse: Codable, Sendable, InterfaceResponse {
        let id: Int
        let name: String
    }

    struct TestInterface: Interface {
        struct Parameters: RequestParameters {
            let method: RequestMethod = .get
            let path: String
            let queryItems: [URLQueryItem]? = nil
            let headers: [String: String]? = nil
            let body: EmptyBody = .init()
            let authentication: AuthenticationType = .none
        }

        typealias Response = TestResponse

        static var responseCases: ResponseMap {
            [
                .code(200, .decode),
                .code(404, .error(TestError.notFound))
            ]
        }
    }

    enum TestError: Error {
        case notFound
        case networkError
    }

    // Mock Transport that doesn't make real network requests
    actor MockTransport: Transport {
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

    // MARK: - Pipeline Tests

    @Test("Builds the request, executes it, and handles the response")
    func testPipelineSuccess() async throws {
        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = """
        {"id": 1, "name": "John Doe"}
        """.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            TestInterface.self,
            params,
            context: context
        )

        #expect(result.id == 1)
        #expect(result.name == "John Doe")

        // Verify request was constructed correctly
        let capturedRequest = await transport.capturedRequest
        #expect(capturedRequest?.url?.path == "/users/1")
        #expect(capturedRequest?.httpMethod == "GET")
    }

    @Test("Handles error responses")
    func testPipelineErrorResponse() async throws {
        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestInterface.Parameters(path: "/users/999")

        let transport = MockTransport()
        await transport.setMockResponse(data: Data(), statusCode: 404, url: url)
        let pipeline = RequestPipeline(transport: transport)

        await #expect(throws: ResponseError.self) {
            try await pipeline.send(
                TestInterface.self,
                params,
                context: context
            )
        }
    }

    @Test("Propagates network errors")
    func testPipelineNetworkError() async throws {
        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestInterface.Parameters(path: "/test")

        let transport = MockTransport()
        await transport.setError(TestError.networkError)
        let pipeline = RequestPipeline(transport: transport)

        await #expect(throws: TestError.self) {
            try await pipeline.send(
                TestInterface.self,
                params,
                context: context
            )
        }
    }

    @Test("Passes the context's token to the request builder")
    func testPipelineUsesContextToken() async throws {
        let url = URL(string: "https://custom.api.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(url: url),
            authToken: "test-token"
        )

        struct AuthInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/secure"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .bearer
            }

            typealias Response = TestResponse

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let params = AuthInterface.Parameters()
        let responseData = """
        {"id": 1, "name": "Secure Data"}
        """.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            AuthInterface.self,
            params,
            context: context
        )

        #expect(result.name == "Secure Data")

        // Verify auth token was added
        let capturedRequest = await transport.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
    }

    @Test("Uses a custom RequestBuilder when provided")
    func testCustomBuilderIsUsed() async throws {
        struct CustomBuilder: RequestBuilder {
            func applyHeaders(
                _ headers: [String: String],
                authentication: AuthenticationType,
                authToken: String?,
                to request: inout URLRequest
            ) throws(RequestError) {
                try URLRequestBuilder().applyHeaders(
                    headers,
                    authentication: authentication,
                    authToken: authToken,
                    to: &request
                )

                var current = request.allHTTPHeaderFields ?? [:]
                current["X-Test-Builder"] = "true"
                request.allHTTPHeaderFields = current
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                builder: CustomBuilder()
            )
        )
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = """
        {"id": 1, "name": "John Doe"}
        """.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        _ = try await pipeline.send(
            TestInterface.self,
            params,
            context: context
        )

        let capturedRequest = await transport.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Test-Builder") == "true")
    }

    @Test("A stateful RequestBuilder can carry its own configuration")
    func testStatefulBuilder() async throws {
        struct SigningBuilder: RequestBuilder {
            let signature: String

            func applyHeaders(
                _ headers: [String: String],
                authentication: AuthenticationType,
                authToken: String?,
                to request: inout URLRequest
            ) throws(RequestError) {
                try URLRequestBuilder().applyHeaders(
                    headers,
                    authentication: authentication,
                    authToken: authToken,
                    to: &request
                )

                var current = request.allHTTPHeaderFields ?? [:]
                current["X-Signature"] = signature
                request.allHTTPHeaderFields = current
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                builder: SigningBuilder(signature: "abc123")
            )
        )
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = #"{"id": 1, "name": "John Doe"}"#.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        _ = try await pipeline.send(TestInterface.self, params, context: context)

        let capturedRequest = await transport.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Signature") == "abc123")
    }

    @Test("A RequestBuilder that reimplements buildRequest still gets the configuration's defaultHeaders")
    func testCustomBuildRequestKeepsDefaultHeaders() async throws {
        // Headers are resolved by ServerConfiguration, not by the default pipeline, so even a
        // builder that replaces buildRequest wholesale cannot silently drop defaultHeaders.
        struct ReimplementingBuilder: RequestBuilder {
            func buildRequest<Parameters: RequestParameters>(
                _ requestParameters: Parameters,
                context: RequestContext
            ) throws(RequestError) -> URLRequest {
                var components = try makeComponents(context: context)
                applyPath(requestParameters.path, to: &components)
                var request = makeRequest(url: try makeURL(from: components))
                applyMethod(requestParameters.method, to: &request)
                try applyHeaders(
                    context.resolvedHeaders(for: requestParameters),
                    authentication: requestParameters.authentication,
                    authToken: context.authToken,
                    to: &request
                )
                return request
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                defaultHeaders: ["X-App-Version": "1.0"],
                builder: ReimplementingBuilder()
            )
        )
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = #"{"id": 1, "name": "John Doe"}"#.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        _ = try await pipeline.send(TestInterface.self, params, context: context)

        let capturedRequest = await transport.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-App-Version") == "1.0")
    }

    @Test("Uses configuration.responseDecoder to decode the response")
    func testConfiguredResponseDecoderIsUsed() async throws {
        struct SnakeCaseResponse: Codable, Sendable, InterfaceResponse {
            let userId: Int
        }

        struct SnakeCaseInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/snake-case"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .none
            }

            typealias Response = SnakeCaseResponse

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                responseDecoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
            )
        )
        let params = SnakeCaseInterface.Parameters()

        let responseData = #"{"user_id": 55}"#.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            SnakeCaseInterface.self,
            params,
            context: context
        )

        #expect(result.userId == 55)
    }

    @Test("A thrown ResponseError carries the configured decoder for its error body")
    func testErrorBodyCarriesConfiguredDecoder() async throws {
        struct SnakeCaseErrorBody: Decodable {
            let errorMessage: String
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                responseDecoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
            )
        )
        let params = TestInterface.Parameters(path: "/users/999")

        let transport = MockTransport()
        await transport.setMockResponse(
            data: #"{"error_message": "not found"}"#.data(using: .utf8)!,
            statusCode: 404,
            url: url
        )
        let pipeline = RequestPipeline(transport: transport)

        do {
            _ = try await pipeline.send(TestInterface.self, params, context: context)
            #expect(Bool(false), "Expected a ResponseError")
        } catch let error as ResponseError {
            // No decoder passed at the catch site; the error carries the client's own.
            let body = error.decodeError(as: SnakeCaseErrorBody.self)
            #expect(body?.errorMessage == "not found")
        }
    }

    // MARK: - URLSession Conformance Tests

    @Test("URLSession conforms to Transport")
    func testURLSessionConformance() {
        let session = URLSession.shared
        let _: any Transport = session

        // Just verify it compiles, proving conformance
    }

    // MARK: - Integration with Interface Types

    @Test("Works with String response type")
    func testStringResponseType() async throws {
        struct StringInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/message"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .none
            }

            typealias Response = String

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = StringInterface.Parameters()

        let responseData = "Hello, World!".data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            StringInterface.self,
            params,
            context: context
        )

        #expect(result == "Hello, World!")
    }

    @Test("Works with Data response type")
    func testDataResponseType() async throws {
        struct DataInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/binary"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .none
            }

            typealias Response = Data

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = DataInterface.Parameters()

        let responseData = Data([0x00, 0x01, 0x02, 0x03])

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            DataInterface.self,
            params,
            context: context
        )

        #expect(result == responseData)
    }

    @Test("Works with complex nested response types")
    func testComplexNestedResponseType() async throws {
        struct ComplexResponse: Codable, Sendable, InterfaceResponse {
            struct User: Codable, Sendable {
                let id: Int
                let email: String
            }
            let user: User
            let token: String
        }

        struct ComplexInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .post
                let path = "/login"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .none
            }

            typealias Response = ComplexResponse

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
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

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            ComplexInterface.self,
            params,
            context: context
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
                let method: RequestMethod = .get
                let path = "/items"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .none
            }

            typealias Response = [Item]

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = ArrayInterface.Parameters()

        let responseData = """
        [
            {"id": 1, "name": "First"},
            {"id": 2, "name": "Second"},
            {"id": 3, "name": "Third"}
        ]
        """.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(
            ArrayInterface.self,
            params,
            context: context
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
            let queryItems: [URLQueryItem]? = [URLQueryItem(name: "page", value: "1")]
            let headers: [String: String]? = ["X-Custom": "value"]
            let body: BinaryBody
            let authentication: AuthenticationType = .bearer
        }

        struct CompleteInterface: Interface {
            typealias Parameters = CompleteParameters
            typealias Response = TestResponse

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(url: url),
            authToken: "auth-token"
        )
        let bodyData = "{\"test\":\"data\"}".data(using: .utf8)!
        let params = CompleteParameters(body: BinaryBody(data: bodyData, contentType: "application/octet-stream"))

        let responseData = """
        {"id": 1, "name": "Test"}
        """.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        _ = try await pipeline.send(
            CompleteInterface.self,
            params,
            context: context
        )

        let capturedRequest = await transport.capturedRequest

        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.path == "/api/resource")
        #expect(capturedRequest?.url?.query?.contains("page=1") == true)
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer auth-token")
        #expect(capturedRequest?.httpBody == bodyData)
    }

    @Test("Throws RequestError when the context has no token for an authenticated request")
    func testMissingToken() async throws {
        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url)) // No auth token

        struct AuthRequiredInterface: Interface {
            struct Parameters: RequestParameters {
                let method: RequestMethod = .get
                let path = "/secure"
                let queryItems: [URLQueryItem]? = nil
                let headers: [String: String]? = nil
                let body: EmptyBody = .init()
                let authentication: AuthenticationType = .bearer // Requires token
            }

            typealias Response = TestResponse

            static var responseCases: ResponseMap {
                [.code(200, .decode)]
            }
        }

        let params = AuthRequiredInterface.Parameters()
        let pipeline = RequestPipeline(transport: MockTransport())

        await #expect(throws: RequestError.self) {
            try await pipeline.send(
                AuthRequiredInterface.self,
                params,
                context: context
            )
        }
    }

    // MARK: - Sendable Conformance Tests

    @Test("Pipeline operations are Sendable-safe")
    func testSendableConformance() async throws {
        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(configuration: ServerConfiguration(url: url))
        let params = TestInterface.Parameters(path: "/test")

        let responseData = """
        {"id": 1, "name": "Test"}
        """.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        // This compiles and runs, proving Sendable safety
        async let result1 = pipeline.send(TestInterface.self, params, context: context)
        async let result2 = pipeline.send(TestInterface.self, params, context: context)

        let (r1, r2) = try await (result1, result2)

        #expect(r1.id == 1)
        #expect(r2.id == 1)
    }

    // MARK: - Configuration-owned Response Handler

    /// Tags every decoded response, standing in for a server-wide response concern.
    struct RewritingResponseHandler: ResponseHandler {
        func handle<T: Interface>(
            _ response: (data: Data, response: URLResponse),
            for interface: T.Type,
            responseDecoder: ResponseDecoder
        ) throws(ResponseError) -> T.Response {
            let rewritten = #"{"id": 99, "name": "from-configuration"}"#.data(using: .utf8)!

            return try DefaultResponseHandler().handle(
                (data: rewritten, response: response.response),
                for: interface,
                responseDecoder: responseDecoder
            )
        }
    }

    @Test("The pipeline uses the configuration's responseHandler for an Interface that declares none")
    func testPipelineUsesConfigurationResponseHandler() async throws {
        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                responseHandler: RewritingResponseHandler()
            )
        )
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = #"{"id": 1, "name": "John Doe"}"#.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        let result = try await pipeline.send(TestInterface.self, params, context: context)

        #expect(result.id == 99)
        #expect(result.name == "from-configuration")
    }

    @Test("The pipeline uses the configuration's builder without being handed one")
    func testPipelineUsesConfigurationBuilder() async throws {
        struct StampingBuilder: RequestBuilder {
            func applyHeaders(
                _ headers: [String: String],
                authentication: AuthenticationType,
                authToken: String?,
                to request: inout URLRequest
            ) throws(RequestError) {
                try URLRequestBuilder().applyHeaders(
                    headers,
                    authentication: authentication,
                    authToken: authToken,
                    to: &request
                )

                var current = request.allHTTPHeaderFields ?? [:]
                current["X-Stamp"] = "configuration"
                request.allHTTPHeaderFields = current
            }
        }

        let url = URL(string: "https://api.example.com")!
        let context = RequestContext(
            configuration: ServerConfiguration(
                url: url,
                builder: StampingBuilder()
            )
        )
        let params = TestInterface.Parameters(path: "/users/1")

        let responseData = #"{"id": 1, "name": "John Doe"}"#.data(using: .utf8)!

        let transport = MockTransport()
        await transport.setMockResponse(data: responseData, statusCode: 200, url: url)
        let pipeline = RequestPipeline(transport: transport)

        _ = try await pipeline.send(TestInterface.self, params, context: context)

        let capturedRequest = await transport.capturedRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Stamp") == "configuration")
    }

}
