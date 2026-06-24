import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Test Interface

private struct TestInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/test"
        let queryItems: [String: String?]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody? = nil
        let authentication: AuthenticationType
    }

    struct Response: Codable, Sendable, Equatable {
        let value: String
    }

    static var responseCases: ResponseMap {
        [.code(200, .decode)]
    }
}

// MARK: - Token Store

private actor TokenStore {
    var tokens: [String]

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func next() -> String {
        guard !tokens.isEmpty else { return "" }
        return tokens.removeFirst()
    }
}

// MARK: - Mock Data Task Provider

private actor MockDataTaskProvider: DataTaskProvider {
    private var queue: [Result<(Data, URLResponse), Error>] = []
    private(set) var callCount: Int = 0
    private(set) var capturedRequests: [URLRequest] = []

    private let baseURL = URL(string: "https://api.example.com")!

    func enqueue(data: Data, statusCode: Int) {
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        queue.append(.success((data, response)))
    }

    func enqueueError(_ error: Error) {
        queue.append(.failure(error))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        capturedRequests.append(request)
        guard !queue.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let result = queue.removeFirst()
        switch result {
        case .success(let pair):
            return pair
        case .failure(let error):
            throw error
        }
    }
}

// MARK: - Helpers

private func makeResponseData(value: String = "ok") -> Data {
    try! JSONEncoder().encode(TestInterface.Response(value: value))
}

private func makeClient(
    mock: MockDataTaskProvider,
    token: @escaping @Sendable () async throws -> String?,
    refresh: @escaping @Sendable () async throws -> Void = {}
) -> APIClient {
    APIClient(
        baseURL: URL(string: "https://api.example.com")!,
        session: mock,
        token: token,
        refresh: refresh
    )
}

// MARK: - Suite

@Suite("APIClient Tests")
struct APIClientTests {

    // MARK: 1. .none auth never calls token

    @Test(".none auth never calls the token closure")
    func noneAuthDoesNotCallToken() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        var tokenCallCount = 0
        let client = makeClient(mock: mock, token: {
            tokenCallCount += 1
            return "should-not-be-called"
        })

        let params = TestInterface.Parameters(authentication: .none)
        _ = try await client.send(TestInterface.self, params)

        #expect(tokenCallCount == 0)
    }

    // MARK: 2. .bearer auth sets Authorization header

    @Test(".bearer auth calls token and sets Authorization: Bearer header")
    func bearerAuthSetsAuthorizationHeader() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        var tokenCallCount = 0
        let client = makeClient(mock: mock, token: {
            tokenCallCount += 1
            return "my-bearer-token"
        })

        let params = TestInterface.Parameters(authentication: .bearer)
        _ = try await client.send(TestInterface.self, params)

        #expect(tokenCallCount == 1)
        let requests = await mock.capturedRequests
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer my-bearer-token")
    }

    // MARK: 3. .url auth appends token query param

    @Test(".url auth calls token and appends token= query parameter")
    func urlAuthAppendsTokenQueryParam() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        var tokenCallCount = 0
        let client = makeClient(mock: mock, token: {
            tokenCallCount += 1
            return "my-url-token"
        })

        let params = TestInterface.Parameters(authentication: .url)
        _ = try await client.send(TestInterface.self, params)

        #expect(tokenCallCount == 1)
        let requests = await mock.capturedRequests
        #expect(requests.count == 1)
        let url = try #require(requests[0].url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let tokenItem = components.queryItems?.first(where: { $0.name == "token" })
        #expect(tokenItem?.value == "my-url-token")
    }

    // MARK: 4. Successful request decodes response

    @Test("Successful request decodes the response body")
    func successfulRequestDecodesResponse() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(value: "hello"), statusCode: 200)

        let client = makeClient(mock: mock, token: { "tok" })

        let params = TestInterface.Parameters(authentication: .bearer)
        let result = try await client.send(TestInterface.self, params)

        #expect(result.value == "hello")
    }

    // MARK: 5. 401 triggers refresh then retries with fresh token

    @Test("401 triggers refresh then retries with a fresh token")
    func fourOhOneTriggerRefreshAndRetry() async throws {
        let mock = MockDataTaskProvider()
        // First call returns 401; retry gets 200
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: makeResponseData(value: "retried"), statusCode: 200)

        var tokenCallCount = 0
        var refreshCallCount = 0

        let client = makeClient(
            mock: mock,
            token: {
                tokenCallCount += 1
                return "token-\(tokenCallCount)"
            },
            refresh: {
                refreshCallCount += 1
            }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        let result = try await client.send(TestInterface.self, params)

        #expect(result.value == "retried")
        #expect(tokenCallCount == 2)
        #expect(refreshCallCount == 1)
        let callCount = await mock.callCount
        #expect(callCount == 2)
    }

    // MARK: 6. Non-401 errors are not retried

    @Test("Non-401 errors are not retried and refresh is not called")
    func nonFourOhOneErrorIsNotRetried() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: Data(), statusCode: 500)

        var refreshCallCount = 0
        let client = makeClient(
            mock: mock,
            token: { "tok" },
            refresh: { refreshCallCount += 1 }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        await #expect(throws: ResponseError.self) {
            try await client.send(TestInterface.self, params)
        }

        #expect(refreshCallCount == 0)
        let callCount = await mock.callCount
        #expect(callCount == 1)
    }

    // MARK: 7. Refresh failure propagates to caller

    @Test("Refresh failure propagates to the caller")
    func refreshFailurePropagates() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: Data(), statusCode: 401)

        struct RefreshError: Error, Equatable {}

        let client = makeClient(
            mock: mock,
            token: { "tok" },
            refresh: { throw RefreshError() }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        await #expect(throws: RefreshError.self) {
            try await client.send(TestInterface.self, params)
        }
    }

    // MARK: 8. After refresh, retry uses the new token value

    @Test("After a successful refresh the retry uses the new token value")
    func retryUsesNewTokenAfterRefresh() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let store = TokenStore(tokens: ["old-token", "new-token"])

        let client = makeClient(
            mock: mock,
            token: { await store.next() },
            refresh: {}
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        _ = try await client.send(TestInterface.self, params)

        let requests = await mock.capturedRequests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer old-token")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer new-token")
    }

    // MARK: 9. Concurrent 401s coalesce into a single refresh call

    @Test("Concurrent 401s coalesce into a single refresh call")
    func concurrent401sCoalesceRefresh() async throws {
        let mock = MockDataTaskProvider()
        // Three concurrent requests each get a 401 first, then a 200 on retry
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: makeResponseData(value: "a"), statusCode: 200)
        await mock.enqueue(data: makeResponseData(value: "b"), statusCode: 200)
        await mock.enqueue(data: makeResponseData(value: "c"), statusCode: 200)

        var refreshCallCount = 0

        // TokenStore with enough tokens: 3 initial + 3 post-refresh
        let store = TokenStore(tokens: [
            "tok1", "tok2", "tok3",
            "fresh1", "fresh2", "fresh3"
        ])

        let client = makeClient(
            mock: mock,
            token: { await store.next() },
            refresh: {
                refreshCallCount += 1
                // Sleep long enough that all three 401s arrive before refresh completes
                try await Task.sleep(for: .milliseconds(50))
            }
        )

        let params = TestInterface.Parameters(authentication: .bearer)

        async let r1 = client.send(TestInterface.self, params)
        async let r2 = client.send(TestInterface.self, params)
        async let r3 = client.send(TestInterface.self, params)

        let (result1, result2, result3) = try await (r1, r2, r3)

        #expect(result1.value != "")
        #expect(result2.value != "")
        #expect(result3.value != "")
        #expect(refreshCallCount == 1)
        let callCount = await mock.callCount
        #expect(callCount == 6)
    }
}
