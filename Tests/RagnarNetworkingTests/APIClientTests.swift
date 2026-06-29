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
        let body: EmptyBody = .init()
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
    private var tokens: [String]
    private(set) var callCount = 0

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func next() -> String {
        callCount += 1
        guard !tokens.isEmpty else { return "" }
        return tokens.removeFirst()
    }
}

// MARK: - Counter

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
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

        let tokenCounter = Counter()
        let client = makeClient(mock: mock, token: {
            await tokenCounter.increment()
            return "should-not-be-called"
        })

        let params = TestInterface.Parameters(authentication: .none)
        _ = try await client.send(TestInterface.self, params)

        #expect(await tokenCounter.value == 0)
    }

    @Test("Unauthenticated convenience initializer supports .none requests")
    func unauthenticatedInitializerSupportsNoneAuth() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(value: "public"), statusCode: 200)

        let client = APIClient(
            baseURL: URL(string: "https://api.example.com")!,
            session: mock
        )

        let params = TestInterface.Parameters(authentication: .none)
        let result = try await client.send(TestInterface.self, params)

        #expect(result.value == "public")
        #expect(await mock.callCount == 1)
    }

    // MARK: 2. .bearer auth sets Authorization header

    @Test(".bearer auth calls token and sets Authorization: Bearer header")
    func bearerAuthSetsAuthorizationHeader() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let tokenCounter = Counter()
        let client = makeClient(mock: mock, token: {
            await tokenCounter.increment()
            return "my-bearer-token"
        })

        let params = TestInterface.Parameters(authentication: .bearer)
        _ = try await client.send(TestInterface.self, params)

        #expect(await tokenCounter.value == 1)
        let requests = await mock.capturedRequests
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer my-bearer-token")
    }

    // MARK: 3. .url auth appends token query param

    @Test(".url auth calls token and appends token= query parameter")
    func urlAuthAppendsTokenQueryParam() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let tokenCounter = Counter()
        let client = makeClient(mock: mock, token: {
            await tokenCounter.increment()
            return "my-url-token"
        })

        let params = TestInterface.Parameters(authentication: .url)
        _ = try await client.send(TestInterface.self, params)

        #expect(await tokenCounter.value == 1)
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
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: makeResponseData(value: "retried"), statusCode: 200)

        let tokenStore = TokenStore(tokens: ["token-1", "token-2"])
        let refreshCounter = Counter()

        let client = makeClient(
            mock: mock,
            token: { await tokenStore.next() },
            refresh: { await refreshCounter.increment() }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        let result = try await client.send(TestInterface.self, params)

        #expect(result.value == "retried")
        #expect(await tokenStore.callCount == 2)
        #expect(await refreshCounter.value == 1)
        #expect(await mock.callCount == 2)
    }

    // MARK: 6. Non-401 errors are not retried

    @Test("Non-401 errors are not retried and refresh is not called")
    func nonFourOhOneErrorIsNotRetried() async throws {
        let mock = MockDataTaskProvider()
        await mock.enqueue(data: Data(), statusCode: 500)

        let refreshCounter = Counter()
        let client = makeClient(
            mock: mock,
            token: { "tok" },
            refresh: { await refreshCounter.increment() }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        await #expect(throws: ResponseError.self) {
            try await client.send(TestInterface.self, params)
        }

        #expect(await refreshCounter.value == 0)
        #expect(await mock.callCount == 1)
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
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: makeResponseData(value: "a"), statusCode: 200)
        await mock.enqueue(data: makeResponseData(value: "b"), statusCode: 200)
        await mock.enqueue(data: makeResponseData(value: "c"), statusCode: 200)

        let refreshCounter = Counter()
        let store = TokenStore(tokens: [
            "tok1", "tok2", "tok3",
            "fresh1", "fresh2", "fresh3"
        ])

        let client = makeClient(
            mock: mock,
            token: { await store.next() },
            refresh: {
                await refreshCounter.increment()
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
        #expect(await refreshCounter.value == 1)
        #expect(await mock.callCount == 6)
    }
}
