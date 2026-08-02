import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Test Interface

private struct TestInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod
        let path: String
        let queryItems: [URLQueryItem]?
        let headers: [String: String]?
        let body: EmptyBody
        let authentication: AuthenticationScheme?

        init(
            method: RequestMethod = .get,
            path: String = "/test",
            queryItems: [URLQueryItem]? = nil,
            headers: [String: String]? = nil,
            body: EmptyBody = .init(),
            authentication: AuthenticationScheme?
        ) {
            self.method = method
            self.path = path
            self.queryItems = queryItems
            self.headers = headers
            self.body = body
            self.authentication = authentication
        }
    }

    struct Response: Codable, Sendable, Equatable, InterfaceResponse {
        let value: String
    }

    static var responseCases: ResponseMap {
        [.code(200, .decode)]
    }
}

// MARK: - Body Test Interface

private struct BodyTestInterface: Interface {
    struct Payload: Codable, Sendable {
        let userId: Int
    }

    struct Parameters: RequestParameters {
        let method: RequestMethod = .post
        let path: String = "/body-test"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EncodableBody<Payload>
        let authentication: AuthenticationScheme? = nil
    }

    struct Response: Codable, Sendable, Equatable, InterfaceResponse {
        let value: String
    }

    static var responseCases: ResponseMap {
        [.code(200, .decode)]
    }
}

// MARK: - Snake Case Response Interface

private struct SnakeCaseResponseInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/snake-case"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = nil
    }

    struct Response: Codable, Sendable, Equatable, InterfaceResponse {
        let userId: Int
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

// MARK: - Mock Transport

private actor MockTransport: Transport {
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

// MARK: - Signal

/// A one-shot async signal used to await a point reached inside a closure.
private actor Signal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isFired = false

    func fire() {
        guard !isFired else { return }
        isFired = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        if isFired { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

// MARK: - Cancellation Latch

/// Suspends until the surrounding task is cancelled, then throws `CancellationError`.
///
/// Deterministic hold: the suspension ends exactly when cancellation propagates,
/// with no polling, timeout, or sleep. Used to keep an operation in flight until a
/// test cancels it.
private actor CancellationLatch {
    private var continuation: CheckedContinuation<Void, Error>?
    private var isCancelled = false

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(continuation)
            }
        } onCancel: {
            Task { await trigger() }
        }
    }

    private func register(_ continuation: CheckedContinuation<Void, Error>) {
        if isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            self.continuation = continuation
        }
    }

    private func trigger() {
        isCancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

// MARK: - Blocking Transport

/// A provider whose `data(for:)` blocks until the request is cancelled, letting a
/// test observe an in-flight transport request and then cancel it deterministically.
private actor BlockingTransport: Transport {
    private let started = Signal()
    private let latch = CancellationLatch()
    private(set) var completed = false

    private let responseData: Data
    private let statusCode: Int
    private let baseURL = URL(string: "https://api.example.com")!

    init(data: Data, statusCode: Int) {
        self.responseData = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await started.fire()
        // Suspends until the request is cancelled; only reached on natural completion.
        try await latch.wait()
        completed = true
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func waitUntilStarted() async {
        await started.wait()
    }
}

// MARK: - Barrier

/// Suspends each caller until exactly two callers have arrived, then releases both
/// together. Used to guarantee two requests have both read their token and reached
/// transport before either one's response is allowed to resolve.
private actor Barrier2 {
    private var arrivals = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func arrive() async {
        arrivals += 1
        if arrivals >= 2 {
            for continuation in continuations { continuation.resume() }
            continuations.removeAll()
        } else {
            await withCheckedContinuation { continuations.append($0) }
        }
    }
}

// MARK: - Switching Token Store

/// Returns a stale token until `advance()` is called, then returns a fresh token for
/// every subsequent call. Models a real token store where every reader sees the same
/// value until a refresh updates it, regardless of how many readers there are.
private actor SwitchingTokenStore {
    private var current = "stale"
    private(set) var callCount = 0

    func next() -> String {
        callCount += 1
        return current
    }

    func advance() {
        current = "fresh"
    }
}

// MARK: - Staggered Transport

/// A provider whose first two calls both fail with 401, but whose second call does not
/// return until `refreshCompleted` fires. Combined with `Barrier2`, this reproduces a
/// staggered 401 deterministically: both requests reach transport before either 401 is
/// observed by the client, and the second 401 is only observed after a refresh
/// triggered by the first has already completed.
private actor StaggeredTransport: Transport {
    private let baseURL = URL(string: "https://api.example.com")!
    private var callIndex = 0
    private(set) var callCount = 0
    private(set) var capturedRequests: [URLRequest] = []

    private let responses: [(data: Data, statusCode: Int)]
    private let bothStarted: Barrier2
    private let refreshCompleted: Signal

    init(
        responses: [(data: Data, statusCode: Int)],
        bothStarted: Barrier2,
        refreshCompleted: Signal
    ) {
        self.responses = responses
        self.bothStarted = bothStarted
        self.refreshCompleted = refreshCompleted
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let index = callIndex
        callIndex += 1
        callCount += 1
        capturedRequests.append(request)

        if index < 2 {
            await bothStarted.arrive()
        }
        if index == 1 {
            await refreshCompleted.wait()
        }

        let (data, statusCode) = responses[index]
        let response = HTTPURLResponse(
            url: baseURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Helpers

private func makeResponseData(value: String = "ok") -> Data {
    try! JSONEncoder().encode(TestInterface.Response(value: value))
}

private let testServerURL = URL(string: "https://api.example.com")!

private func makeClient(
    mock: any Transport,
    token: @escaping @Sendable () async throws -> String?,
    refresh: @escaping @Sendable () async throws -> Void = {}
) -> APIClient {
    APIClient(
        configuration: ServerConfiguration(url: testServerURL),
        transport: mock,
        token: token,
        refresh: refresh
    )
}

// MARK: - Suite

@Suite("APIClient Tests", .timeLimit(.minutes(1)))
struct APIClientTests {

    // MARK: 1. .none auth never calls token

    @Test(".none auth never calls the token closure")
    func noneAuthDoesNotCallToken() async throws {
        let mock = MockTransport()
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
        let mock = MockTransport()
        await mock.enqueue(data: makeResponseData(value: "public"), statusCode: 200)

        let client = APIClient(
            configuration: ServerConfiguration(url: testServerURL),
            transport: mock
        )

        let params = TestInterface.Parameters(authentication: .none)
        let result = try await client.send(TestInterface.self, params)

        #expect(result.value == "public")
        #expect(await mock.callCount == 1)
    }

    // MARK: 2. .bearer auth sets Authorization header

    @Test(".bearer auth calls token and sets Authorization: Bearer header")
    func bearerAuthSetsAuthorizationHeader() async throws {
        let mock = MockTransport()
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
        let mock = MockTransport()
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
        let mock = MockTransport()
        await mock.enqueue(data: makeResponseData(value: "hello"), statusCode: 200)

        let client = makeClient(mock: mock, token: { "tok" })

        let params = TestInterface.Parameters(authentication: .bearer)
        let result = try await client.send(TestInterface.self, params)

        #expect(result.value == "hello")
    }

    // MARK: 5. 401 triggers refresh then retries with fresh token

    @Test("401 triggers refresh then retries with a fresh token")
    func fourOhOneTriggerRefreshAndRetry() async throws {
        let mock = MockTransport()
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
        let mock = MockTransport()
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
        let mock = MockTransport()
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
        let mock = MockTransport()
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
        let mock = MockTransport()
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

    // MARK: 10. A 401 that arrives after an unrelated refresh has completed does not trigger a second refresh

    @Test("A 401 whose token predates a completed refresh retries directly instead of refreshing again")
    func staggered401DoesNotTriggerRedundantRefresh() async throws {
        let bothStarted = Barrier2()
        let refreshCompleted = Signal()

        // Call order: two initial sends both fail 401 using the stale token (the second
        // is held back until refreshCompleted fires), then two retries both succeed 200.
        let mock = StaggeredTransport(
            responses: [
                (Data(), 401),
                (Data(), 401),
                (makeResponseData(value: "a"), 200),
                (makeResponseData(value: "b"), 200)
            ],
            bothStarted: bothStarted,
            refreshCompleted: refreshCompleted
        )

        let refreshCounter = Counter()
        let store = SwitchingTokenStore()

        let client = makeClient(
            mock: mock,
            token: { await store.next() },
            refresh: {
                await refreshCounter.increment()
                await store.advance()
                await refreshCompleted.fire()
            }
        )

        let params = TestInterface.Parameters(authentication: .bearer)

        async let r1 = client.send(TestInterface.self, params)
        async let r2 = client.send(TestInterface.self, params)

        let (result1, result2) = try await (r1, r2)

        #expect(result1.value != "")
        #expect(result2.value != "")
        #expect(await refreshCounter.value == 1)
        #expect(await mock.callCount == 4)

        // The two retries (the last two transport calls) both used the post-refresh token.
        let requests = await mock.capturedRequests
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
        #expect(requests[3].value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
    }

    // MARK: 11. 401 followed by another 401 does not loop

    @Test("A second 401 after refresh and retry is not retried again")
    func secondConsecutive401IsNotRetriedAgain() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: Data(), statusCode: 401)
        await mock.enqueue(data: Data(), statusCode: 401)

        let refreshCounter = Counter()
        let client = makeClient(
            mock: mock,
            token: { "token" },
            refresh: { await refreshCounter.increment() }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        await #expect(throws: ResponseError.self) {
            try await client.send(TestInterface.self, params)
        }

        #expect(await refreshCounter.value == 1)
        #expect(await mock.callCount == 2)
    }

    // MARK: 12. Invalidating before send prevents token and transport work

    @Test("Invalidating before send prevents token and transport work")
    func invalidateBeforeSendPreventsWork() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let tokenCounter = Counter()
        let client = makeClient(mock: mock, token: {
            await tokenCounter.increment()
            return "tok"
        })

        await client.invalidate()

        let params = TestInterface.Parameters(authentication: .bearer)
        await #expect(throws: APIClientError.self) {
            try await client.send(TestInterface.self, params)
        }

        #expect(await tokenCounter.value == 0)
        #expect(await mock.callCount == 0)
    }

    // MARK: 13. Invalidating during transport suppresses completion

    @Test("Invalidating during transport cancels or suppresses completion")
    func invalidateDuringTransportSuppressesCompletion() async throws {
        let mock = BlockingTransport(data: makeResponseData(), statusCode: 200)
        let client = makeClient(mock: mock, token: { "tok" })

        let params = TestInterface.Parameters(authentication: .bearer)
        let sendTask = Task {
            try await client.send(TestInterface.self, params)
        }

        await mock.waitUntilStarted()
        await client.invalidate()

        await #expect(throws: APIClientError.self) {
            try await sendTask.value
        }
        #expect(await mock.completed == false)
    }

    // MARK: 14. Invalidating during refresh cancels refresh and prevents retry

    @Test("Invalidating during refresh cancels the refresh and prevents retry")
    func invalidateDuringRefreshPreventsRetry() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: Data(), statusCode: 401)
        // A retry, if it happened, would consume this success response.
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let refreshStarted = Signal()
        let refreshCounter = Counter()
        let refreshLatch = CancellationLatch()

        let client = makeClient(
            mock: mock,
            token: { "tok" },
            refresh: {
                await refreshCounter.increment()
                await refreshStarted.fire()
                // Suspends until the refresh is cancelled by invalidate().
                try await refreshLatch.wait()
            }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        let sendTask = Task {
            try await client.send(TestInterface.self, params)
        }

        await refreshStarted.wait()
        await client.invalidate()

        await #expect(throws: APIClientError.self) {
            try await sendTask.value
        }
        #expect(await refreshCounter.value == 1)
        // Only the initial 401 request was sent - no retry.
        #expect(await mock.callCount == 1)
    }

    // MARK: 15. Repeated invalidation is idempotent

    @Test("Repeated invalidation is idempotent")
    func repeatedInvalidationIsIdempotent() async throws {
        let mock = MockTransport()
        let client = makeClient(mock: mock, token: { "tok" })

        await client.invalidate()
        await client.invalidate()
        await client.invalidate()

        let params = TestInterface.Parameters(authentication: .bearer)
        await #expect(throws: APIClientError.self) {
            try await client.send(TestInterface.self, params)
        }
        #expect(await mock.callCount == 0)
    }

    // MARK: 16. A separately created replacement client is unaffected

    @Test("A separately created replacement client is unaffected")
    func replacementClientIsUnaffected() async throws {
        let mockA = MockTransport()
        let clientA = makeClient(mock: mockA, token: { "a" })
        await clientA.invalidate()

        let mockB = MockTransport()
        await mockB.enqueue(data: makeResponseData(value: "b"), statusCode: 200)
        let clientB = makeClient(mock: mockB, token: { "b" })

        let params = TestInterface.Parameters(authentication: .bearer)
        let result = try await clientB.send(TestInterface.self, params)

        #expect(result.value == "b")
        #expect(await mockB.callCount == 1)
    }

    // MARK: 17. Cancelling the caller's task during transport throws promptly

    @Test("Cancelling during transport throws CancellationError and does not complete the request")
    func cancelDuringTransportThrowsCancellationError() async throws {
        let mock = BlockingTransport(data: makeResponseData(), statusCode: 200)
        let client = makeClient(mock: mock, token: { "token" })

        let params = TestInterface.Parameters(authentication: .none)
        let task = Task { try await client.send(TestInterface.self, params) }

        await mock.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await mock.completed == false)
    }

    // MARK: 18. Cancelling the caller's task during refresh throws promptly and does not retry

    @Test("Cancelling during refresh throws CancellationError without cancelling the refresh or retrying")
    func cancelDuringRefreshThrowsCancellationErrorWithoutRetrying() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: Data(), statusCode: 401)

        let refreshStarted = Signal()
        let allowRefreshToFinish = Signal()
        let refreshFinished = Signal()

        let client = makeClient(
            mock: mock,
            token: { "token" },
            refresh: {
                await refreshStarted.fire()
                await allowRefreshToFinish.wait()
                await refreshFinished.fire()
            }
        )

        let params = TestInterface.Parameters(authentication: .bearer)
        let task = Task { try await client.send(TestInterface.self, params) }

        await refreshStarted.wait()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        // No retry was issued while the refresh was still in flight.
        #expect(await mock.callCount == 1)

        // The refresh itself was not cancelled by the caller giving up on it.
        await allowRefreshToFinish.fire()
        await refreshFinished.wait()
    }

    // MARK: 19. A configured RequestEncoder reaches request bodies

    @Test("APIClient configured with a RequestEncoder applies it to request bodies")
    func requestEncoderIsAppliedToRequestBodies() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let client = APIClient(
            configuration: ServerConfiguration(
                url: testServerURL,
                requestEncoder: RequestEncoder(keyEncodingStrategy: .convertToSnakeCase)
            ),
            transport: mock
        )

        let params = BodyTestInterface.Parameters(body: .init(BodyTestInterface.Payload(userId: 42)))
        _ = try await client.send(BodyTestInterface.self, params)

        let requests = await mock.capturedRequests
        let body = try #require(requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["user_id"] as? Int == 42)
        #expect(json["userId"] == nil)
    }

    // MARK: 20. A configured RequestBuilder is used instead of the default

    @Test("APIClient configured with a custom RequestBuilder uses it rather than URLRequestBuilder")
    func customBuilderIsUsedByAPIClient() async throws {
        struct TaggingBuilder: RequestBuilder {
            let tag: String

            func buildRequest<Parameters: RequestParameters>(
                _ requestParameters: Parameters,
                context: RequestContext
            ) throws(RequestError) -> URLRequest {
                var request = try URLRequestBuilder().buildRequest(
                    requestParameters,
                    context: context
                )
                var current = request.allHTTPHeaderFields ?? [:]
                current["X-Custom-Builder"] = tag
                request.allHTTPHeaderFields = current
                return request
            }
        }

        let mock = MockTransport()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let client = APIClient(
            configuration: ServerConfiguration(
                url: testServerURL,
                builder: TaggingBuilder(tag: "tagged")
            ),
            transport: mock
        )

        let params = TestInterface.Parameters(authentication: .none)
        _ = try await client.send(TestInterface.self, params)

        let requests = await mock.capturedRequests
        #expect(requests.first?.value(forHTTPHeaderField: "X-Custom-Builder") == "tagged")
    }

    // MARK: 21. Default headers are applied, with per-request headers taking precedence

    @Test("APIClient configured with defaultHeaders applies them, with per-request headers taking precedence")
    func defaultHeadersAreAppliedAndOverridableByRequestHeaders() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: makeResponseData(), statusCode: 200)
        await mock.enqueue(data: makeResponseData(), statusCode: 200)

        let client = APIClient(
            configuration: ServerConfiguration(
                url: testServerURL,
                defaultHeaders: ["X-App-Version": "1.0", "Accept-Language": "en-US"]
            ),
            transport: mock
        )

        let params = TestInterface.Parameters(authentication: .none)
        _ = try await client.send(TestInterface.self, params)

        let overriding = TestInterface.Parameters(
            headers: ["Accept-Language": "fr-FR"],
            authentication: .none
        )
        _ = try await client.send(TestInterface.self, overriding)

        let requests = await mock.capturedRequests
        #expect(requests[0].value(forHTTPHeaderField: "X-App-Version") == "1.0")
        #expect(requests[0].value(forHTTPHeaderField: "Accept-Language") == "en-US")
        #expect(requests[1].value(forHTTPHeaderField: "X-App-Version") == "1.0")
        #expect(requests[1].value(forHTTPHeaderField: "Accept-Language") == "fr-FR")
    }

    // MARK: 22. A configured ResponseDecoder reaches response decoding

    @Test("APIClient configured with a ResponseDecoder applies it to response bodies")
    func responseDecoderIsAppliedToResponseBodies() async throws {
        let mock = MockTransport()
        await mock.enqueue(data: #"{"user_id": 55}"#.data(using: .utf8)!, statusCode: 200)

        let client = APIClient(
            configuration: ServerConfiguration(
                url: testServerURL,
                responseDecoder: ResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
            ),
            transport: mock
        )

        let params = SnakeCaseResponseInterface.Parameters()
        let result = try await client.send(SnakeCaseResponseInterface.self, params)

        #expect(result.userId == 55)
    }
}
