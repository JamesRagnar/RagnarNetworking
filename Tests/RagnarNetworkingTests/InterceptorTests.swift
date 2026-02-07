//
//  InterceptorTests.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2025-01-15.
//

import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Test Doubles

struct MockInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/test"
        let queryItems: [String: String?]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody? = nil
        let authentication: AuthenticationType = .bearer
    }

    struct Response: Codable, Sendable {
        let message: String
    }

    static var responseCases: ResponseMap {
        return [
            .code(200, .decode)
        ]
    }
}

enum TestError: Error {
    case unauthorized
    case serverError
    case networkError
}

actor MockDataTaskProvider: DataTaskProvider {
    var responses: [(Data, URLResponse)] = []
    var requestCount = 0
    var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        lastRequest = request

        if responses.isEmpty {
            throw TestError.networkError
        }

        return responses.removeFirst()
    }

    func setResponse(_ data: Data, statusCode: Int, url: URL) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        responses.append((data, response))
    }

    func reset() {
        responses = []
        requestCount = 0
        lastRequest = nil
    }
}

final class MockTokenProvider: TokenProvider, @unchecked Sendable {
    var refreshCallCount = 0
    var tokenToReturn = "new-token"
    var shouldThrowError = false

    func refreshToken() async throws -> String {
        refreshCallCount += 1
        if shouldThrowError {
            throw TestError.unauthorized
        }
        return tokenToReturn
    }

    func reset() {
        refreshCallCount = 0
        tokenToReturn = "new-token"
        shouldThrowError = false
    }
}

struct CountingInterceptor: RequestInterceptor {
    let counter: Counter

    actor Counter {
        var adaptCount = 0
        var retryCount = 0

        func incrementAdapt() {
            adaptCount += 1
        }

        func incrementRetry() {
            retryCount += 1
        }

        func reset() {
            adaptCount = 0
            retryCount = 0
        }
    }

    func adapt(_ request: URLRequest, for interface: any Interface.Type) async throws -> URLRequest {
        await counter.incrementAdapt()
        return request
    }

    func retry(_ request: URLRequest, for interface: any Interface.Type, dueTo error: Error, attemptNumber: Int) async throws -> RetryResult {
        await counter.incrementRetry()
        return .doNotRetry
    }
}

// MARK: - Tests

@Suite("Interceptor Tests")
struct InterceptorTests {

    @Test("Adapt is called for each interceptor")
    func testAdaptCalledForEachInterceptor() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        let counter1 = CountingInterceptor.Counter()
        let counter2 = CountingInterceptor.Counter()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                CountingInterceptor(counter: counter1),
                CountingInterceptor(counter: counter2)
            ]
        )

        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        _ = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        let adapt1 = await counter1.adaptCount
        let adapt2 = await counter2.adaptCount

        #expect(adapt1 == 1)
        #expect(adapt2 == 1)
    }

    @Test("Request succeeds without interceptors")
    func testRequestSucceedsWithoutInterceptors() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: []
        )

        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        let response = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        #expect(response.message == "success")
        let count = await provider.requestCount
        #expect(count == 1)
    }

    @Test("Uses custom InterfaceConstructor in InterceptableRequestService")
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
                current["X-Constructor"] = "used"
                request.allHTTPHeaderFields = current
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [],
            constructor: CustomConstructor.self
        )

        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        _ = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        let capturedRequest = await provider.lastRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Constructor") == "used")
    }

    @Test("Constructor overload preserves interceptors")
    func testConstructorOverloadPreservesInterceptors() async throws {
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
                current["X-Constructor"] = "used"
                request.allHTTPHeaderFields = current
            }
        }

        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()
        let counter = CountingInterceptor.Counter()

        let service: RequestService = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [CountingInterceptor(counter: counter)]
        )

        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        _ = try await service.dataTask(
            MockInterface.self,
            MockInterface.Parameters(),
            CustomConstructor.self
        )

        let capturedRequest = await provider.lastRequest
        #expect(capturedRequest?.value(forHTTPHeaderField: "X-Constructor") == "used")
        let adaptCount = await counter.adaptCount
        #expect(adaptCount == 1)
    }

}

@Suite("TokenRefreshInterceptor Tests")
struct TokenRefreshInterceptorTests {

    @Test("Refreshes token on 401 error")
    func testRefreshesTokenOn401() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "old-token")
        let provider = MockDataTaskProvider()
        let tokenProvider = MockTokenProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                TokenRefreshInterceptor(tokenProvider: tokenProvider)
            ]
        )

        // First response: 401 unauthorized
        let errorData = Data()
        await provider.setResponse(errorData, statusCode: 401, url: url)

        // Second response: 200 success with new token
        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        let response = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        #expect(response.message == "success")
        #expect(tokenProvider.refreshCallCount == 1)
        let requestCount = await provider.requestCount
        #expect(requestCount == 2)
    }

    @Test("Does not retry on non-401 errors")
    func testDoesNotRetryOnNon401Errors() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()
        let tokenProvider = MockTokenProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                TokenRefreshInterceptor(tokenProvider: tokenProvider)
            ]
        )

        // 500 server error
        let errorData = Data()
        await provider.setResponse(errorData, statusCode: 500, url: url)

        await #expect(throws: Error.self) {
            try await service.dataTask(MockInterface.self, MockInterface.Parameters())
        }

        #expect(tokenProvider.refreshCallCount == 0)
        let requestCount = await provider.requestCount
        #expect(requestCount == 1)
    }

    @Test("Respects max retries")
    func testRespectsMaxRetries() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()
        let tokenProvider = MockTokenProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                TokenRefreshInterceptor(tokenProvider: tokenProvider, maxRetries: 2)
            ]
        )

        // All responses return 401
        await provider.setResponse(Data(), statusCode: 401, url: url)
        await provider.setResponse(Data(), statusCode: 401, url: url)
        await provider.setResponse(Data(), statusCode: 401, url: url)

        await #expect(throws: Error.self) {
            try await service.dataTask(MockInterface.self, MockInterface.Parameters())
        }

        // Should refresh twice (once per retry)
        #expect(tokenProvider.refreshCallCount == 2)
        let requestCount = await provider.requestCount
        #expect(requestCount == 3)
    }

    @Test("Token provider is only called once per refresh attempt")
    func testTokenProviderCalledOnce() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "old-token")
        let provider = MockDataTaskProvider()
        let tokenProvider = MockTokenProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                TokenRefreshInterceptor(tokenProvider: tokenProvider)
            ]
        )

        // 401 error, then success
        await provider.setResponse(Data(), statusCode: 401, url: url)
        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        let response = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        #expect(response.message == "success")
        // Token refresh should be called exactly once
        #expect(tokenProvider.refreshCallCount == 1)
    }

}

@Suite("ExponentialBackoffInterceptor Tests")
struct ExponentialBackoffInterceptorTests {

    @Test("Retries with exponential backoff on server errors")
    func testRetriesWithExponentialBackoff() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                ExponentialBackoffInterceptor(maxRetries: 2, baseDelay: 0.01)
            ]
        )

        // First two attempts fail with 500
        await provider.setResponse(Data(), statusCode: 500, url: url)
        await provider.setResponse(Data(), statusCode: 500, url: url)

        // Third attempt succeeds
        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        let response = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        #expect(response.message == "success")
        let requestCount = await provider.requestCount
        #expect(requestCount == 3)
    }

    @Test("Does not retry on client errors")
    func testDoesNotRetryOnClientErrors() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                ExponentialBackoffInterceptor(maxRetries: 3)
            ]
        )

        // 404 not found (client error)
        await provider.setResponse(Data(), statusCode: 404, url: url)

        await #expect(throws: Error.self) {
            try await service.dataTask(MockInterface.self, MockInterface.Parameters())
        }

        let requestCount = await provider.requestCount
        #expect(requestCount == 1)
    }

    @Test("Respects max retries limit")
    func testRespectsMaxRetriesLimit() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [
                ExponentialBackoffInterceptor(maxRetries: 2, baseDelay: 0.01)
            ]
        )

        // All requests fail with 500
        await provider.setResponse(Data(), statusCode: 500, url: url)
        await provider.setResponse(Data(), statusCode: 500, url: url)
        await provider.setResponse(Data(), statusCode: 500, url: url)

        await #expect(throws: Error.self) {
            try await service.dataTask(MockInterface.self, MockInterface.Parameters())
        }

        let requestCount = await provider.requestCount
        // Initial + 2 retries = 3 total
        #expect(requestCount == 3)
    }

    @Test("Custom retry condition works correctly")
    func testCustomRetryCondition() async throws {
        let url = URL(string: "https://api.example.com")!
        let config = ServerConfiguration(url: url, authToken: "test-token")
        let provider = MockDataTaskProvider()

        // Custom condition: retry on 503 only
        let interceptor = ExponentialBackoffInterceptor(
            maxRetries: 2,
            baseDelay: 0.01,
            retryCondition: .httpStatusCodes([503])
        )

        let service = InterceptableRequestService(
            dataTaskProvider: provider,
            configurationProvider: { config },
            interceptors: [interceptor]
        )

        // 503 should retry
        await provider.setResponse(Data(), statusCode: 503, url: url)
        let responseData = try! JSONEncoder().encode(MockInterface.Response(message: "success"))
        await provider.setResponse(responseData, statusCode: 200, url: url)

        let response = try await service.dataTask(MockInterface.self, MockInterface.Parameters())

        #expect(response.message == "success")
        let requestCount = await provider.requestCount
        #expect(requestCount == 2)
    }

}
