import Foundation
@testable import RagnarNetworking
import Testing

// MARK: - Fixtures

private let testServerURL = URL(string: "https://api.example.com")!

private func responseData(_ value: String = "ok") -> Data {
    try! JSONEncoder().encode(["value": value])
}

private struct ValueResponse: Codable, Sendable, Equatable, InterfaceResponse {
    let value: String
}

/// An endpoint whose scheme and 401 handling both vary per test.
private struct SchemeInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/resource"
        let queryItems: [URLQueryItem]?
        let headers: [String: String]?
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme?

        init(
            authentication: AuthenticationScheme?,
            queryItems: [URLQueryItem]? = nil,
            headers: [String: String]? = nil
        ) {
            self.authentication = authentication
            self.queryItems = queryItems
            self.headers = headers
        }
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

/// Declares no scheme but carries its credential by some route the package does not model, so
/// it opts back into challenge retry by hand.
private struct CookieAuthInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/cookie"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = nil

        var refreshesOnChallenge: Bool { true }
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

/// A token-refresh endpoint: sends a credential, but a challenge on it must surface rather
/// than recurse into another refresh.
private struct RefreshEndpointInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .post
        let path: String = "/oauth/refresh"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer

        var refreshesOnChallenge: Bool { false }
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

private struct UnauthenticatedInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/public"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = nil
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

private struct AuthFailure: Codable, Error, Sendable, Equatable {
    let reason: String
}

private enum FlatError: Error, Equatable {
    case unauthorized
}

/// Models 401 exactly, as a typed error body.
private struct Models401DecodedInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/models-401"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [
        .code(200, .decode),
        .code(401, .decodeError(AuthFailure.self))
    ]
}

/// Models 401 exactly, as a flat error.
private struct Models401FlatInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/models-401-flat"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [
        .code(200, .decode),
        .code(401, .error(FlatError.unauthorized))
    ]
}

/// Covers 401 only through a 4xx catch-all, which is not a statement about 401.
private struct Range4xxInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/range-4xx"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [
        .code(200, .decode),
        .clientError(.decodeError(AuthFailure.self))
    ]
}

/// Signals staleness with 419 rather than 401.
private struct Stale419Interface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String = "/stale"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

private actor RecordingTransport: Transport {
    private var queue: [(Data, Int)] = []
    private(set) var requests: [URLRequest] = []

    func enqueue(_ data: Data, _ statusCode: Int) {
        queue.append((data, statusCode))
    }

    var callCount: Int { requests.count }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !queue.isEmpty else { throw URLError(.badServerResponse) }
        let (data, statusCode) = queue.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? testServerURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor CallLog {
    private(set) var tokenCalls = 0
    private(set) var refreshCalls = 0

    func recordToken() { tokenCalls += 1 }
    func recordRefresh() { refreshCalls += 1 }
}

// MARK: - Custom Authenticators

/// Signs the request body, which is only possible if authentication runs on the request the
/// builder has already finished.
private struct BodySigningAuthenticator: Authenticator {
    func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String] {
        let body = request.httpBody ?? Data()
        let method = request.httpMethod ?? ""
        return ["X-Signature": "\(credential):\(method):\(body.count)"]
    }
}

/// Signs the path and query, which is only possible if the query-item side sees the built URL.
private struct URLSigningAuthenticator: Authenticator {
    var redactedQueryItemNames: Set<String> { ["signature"] }

    func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem] {
        [URLQueryItem(name: "signature", value: "\(credential):\(components.path)")]
    }
}

/// Contributes nothing, standing in for a conformance that implements the wrong half.
private struct InertAuthenticator: Authenticator {}

/// Writes a query item without declaring it for redaction.
private struct LeakyAuthenticator: Authenticator {
    func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem] {
        [URLQueryItem(name: "secret", value: credential)]
    }
}

private struct SignedBody: RequestBody, Encodable {
    let payload: String
}

private struct SignedInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .post
        let path: String = "/signed"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: SignedBody = SignedBody(payload: "hello")
        let authentication: AuthenticationScheme? = .signature
    }

    typealias Response = ValueResponse

    static let responseCases: ResponseMap = [.code(200, .decode)]
}

private extension AuthenticationScheme {
    static let signature = AuthenticationScheme("signature")
    static let apiKey = AuthenticationScheme("apiKey")
    static let urlSignature = AuthenticationScheme("urlSignature")
    static let inert = AuthenticationScheme("inert")
    static let leaky = AuthenticationScheme("leaky")
}

// MARK: - A. The retry trigger is the credential, not the placement

@Suite("Authentication: retry trigger", .timeLimit(.minutes(1)))
struct AuthenticationRetryTriggerTests {

    @Test("A schemeless request that opts in gets challenge retry and refresh")
    func noneSchemeWithOverrideParticipatesInRefresh() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 401)
        await transport.enqueue(responseData(), 200)

        let log = CallLog()
        let client = APIClient(
            configuration: ServerConfiguration(url: testServerURL),
            transport: transport,
            token: { await log.recordToken(); return "cookie-adjacent" },
            refresh: { await log.recordRefresh() }
        )

        let result = try await client.send(CookieAuthInterface.self, .init())

        #expect(result.value == "ok")
        #expect(await transport.callCount == 2)
        #expect(await log.refreshCalls == 1)
    }

    @Test("A genuinely unauthenticated request never invokes the token closure and is not retried")
    func unauthenticatedRequestSkipsTokenAndRetry() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 401)

        let log = CallLog()
        let client = APIClient(
            configuration: ServerConfiguration(url: testServerURL),
            transport: transport,
            token: { await log.recordToken(); return "unused" },
            refresh: { await log.recordRefresh() }
        )

        let failure = await apiFailure {
            _ = try await client.send(UnauthenticatedInterface.self, .init())
        }
        #expect(failure?.responseError != nil)

        #expect(await transport.callCount == 1)
        #expect(await log.tokenCalls == 0)
        #expect(await log.refreshCalls == 0)
    }

    @Test("A refresh endpoint opting out still applies its credential but never refreshes")
    func refreshEndpointAppliesCredentialWithoutRefreshing() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 401)

        let log = CallLog()
        let client = APIClient(
            configuration: ServerConfiguration(url: testServerURL),
            transport: transport,
            token: { await log.recordToken(); return "refresh-token" },
            refresh: { await log.recordRefresh() }
        )

        let failure = await apiFailure {
            _ = try await client.send(RefreshEndpointInterface.self, .init())
        }
        #expect(failure?.responseError != nil)

        // The credential is still applied, because that follows `authentication`.
        let sent = try #require(await transport.requests.first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer refresh-token")

        // But a 401 here surfaces rather than recursing into another refresh.
        #expect(await transport.callCount == 1)
        #expect(await log.refreshCalls == 0)
    }

    @Test("A refreshesOnChallenge override reaches APIClient through its generic constraint")
    func refreshesOnChallengeOverrideIsWitnessDispatched() async throws {
        // `APIClient.send` reads this on a generic `T.Parameters`. It is a protocol requirement
        // rather than an extension-only member so that these overrides dispatch through the
        // witness table; an extension-only member would resolve to the default here and both
        // overrides would silently do nothing.
        func read<T: Interface>(_ type: T.Type, _ params: T.Parameters) -> Bool {
            params.refreshesOnChallenge
        }

        #expect(read(CookieAuthInterface.self, .init()))
        #expect(!read(RefreshEndpointInterface.self, .init()))
    }

    @Test("refreshesOnChallenge derives from the scheme when a conformance does not declare it")
    func refreshesOnChallengeDerivesFromScheme() {
        #expect(SchemeInterface.Parameters(authentication: nil).refreshesOnChallenge == false)
        #expect(SchemeInterface.Parameters(authentication: .bearer).refreshesOnChallenge == true)
        #expect(SchemeInterface.Parameters(authentication: .url).refreshesOnChallenge == true)
        #expect(SchemeInterface.Parameters(authentication: .apiKey).refreshesOnChallenge == true)
    }

}

// MARK: - B. The scheme is open

@Suite("Authentication: open scheme", .timeLimit(.minutes(1)))
struct AuthenticationSchemeTests {

    @Test("A project-defined scheme is a distinct value usable as a registry key")
    func projectDefinedSchemeIsExpressible() {
        #expect(AuthenticationScheme.apiKey.rawValue == "apiKey")
        #expect(AuthenticationScheme.apiKey != .bearer)
        #expect(AuthenticationScheme("apiKey") == .apiKey)

        let registry: [AuthenticationScheme: any Authenticator] = [.apiKey: .header("X-API-Key")]
        #expect(registry[.apiKey] != nil)
        #expect(registry[.bearer] == nil)
    }

    @Test("Built-in scheme names are stable")
    func builtInSchemeNames() {
        #expect(AuthenticationScheme.bearer.rawValue == "bearer")
        #expect(AuthenticationScheme.url.rawValue == "url")
    }

}

// MARK: - C. Placement lives on the configuration

@Suite("Authentication: authenticators", .timeLimit(.minutes(1)))
struct AuthenticatorTests {

    private func request(
        _ parameters: some RequestParameters,
        configuration: ServerConfiguration,
        credential: String? = "cred"
    ) throws -> URLRequest {
        try URLRequest(
            requestParameters: parameters,
            context: RequestContext(configuration: configuration, credential: credential)
        )
    }

    @Test("The default registry writes today's bearer header")
    func defaultBearerIsUnchanged() throws {
        let built = try request(
            SchemeInterface.Parameters(authentication: .bearer),
            configuration: ServerConfiguration(url: testServerURL),
            credential: "abc123"
        )

        #expect(built.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(built.url?.query == nil)
    }

    @Test("The default registry writes today's token query item")
    func defaultURLAuthIsUnchanged() throws {
        let built = try request(
            SchemeInterface.Parameters(authentication: .url),
            configuration: ServerConfiguration(url: testServerURL),
            credential: "abc123"
        )

        #expect(built.url?.query == "token=abc123")
        #expect(built.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A custom authenticator registered for .bearer replaces the built-in form")
    func customAuthenticatorForBearer() throws {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.bearer: .header("X-API-Key")]
        )

        let built = try request(
            SchemeInterface.Parameters(authentication: .bearer),
            configuration: configuration,
            credential: "key-1"
        )

        #expect(built.value(forHTTPHeaderField: "X-API-Key") == "key-1")
        #expect(built.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A server using ?access_token= needs only configuration")
    func renamedQueryParameterIsConfiguration() throws {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.url: .queryItem("access_token")]
        )

        let built = try request(
            SchemeInterface.Parameters(authentication: .url),
            configuration: configuration,
            credential: "abc123"
        )

        #expect(built.url?.query == "access_token=abc123")
    }

    @Test("A renamed query parameter is redacted from a captured response snapshot")
    func renamedQueryParameterIsRedacted() throws {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.url: .queryItem("access_token")]
        )

        #expect(configuration.redactedQueryItemNames == ["access_token"])

        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/resource?access_token=secret&keep=1")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let snapshot = HTTPResponseSnapshot(
            response: response,
            redactedQueryItemNames: configuration.redactedQueryItemNames
        )

        let captured = try #require(snapshot.url?.absoluteString)
        #expect(!captured.contains("secret"))
        #expect(captured.contains("keep=1"))
    }

    @Test("redactedQueryItemNames unions every registered authenticator")
    func redactedNamesAreUnioned() {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [
                .bearer: .bearer,
                .url: .token,
                .apiKey: .queryItem("access_token")
            ]
        )

        #expect(configuration.redactedQueryItemNames == ["token", "access_token"])
    }

    @Test("An unauthenticated and a bearer endpoint coexist on one configuration")
    func mixedSchemesOnOneConfiguration() throws {
        let configuration = ServerConfiguration(url: testServerURL)

        let authenticated = try request(
            SchemeInterface.Parameters(authentication: .bearer),
            configuration: configuration,
            credential: "abc123"
        )
        let anonymous = try request(
            SchemeInterface.Parameters(authentication: nil),
            configuration: configuration,
            credential: "abc123"
        )

        #expect(authenticated.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
        #expect(anonymous.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(anonymous.url?.query == nil)
    }

    @Test("A scheme with no registered authenticator fails with an error naming it")
    func unregisteredSchemeFails() {
        let configuration = ServerConfiguration(url: testServerURL)

        #expect {
            _ = try request(
                SchemeInterface.Parameters(authentication: .apiKey),
                configuration: configuration
            )
        } throws: { error in
            guard case .unregisteredScheme(let scheme) = error as? RequestError else {
                return false
            }
            return scheme == .apiKey
        }
    }

    @Test("A registered scheme with no credential still fails with .authentication")
    func missingCredentialFails() {
        let configuration = ServerConfiguration(url: testServerURL)

        for scheme in [AuthenticationScheme.bearer, .url] {
            #expect {
                _ = try request(
                    SchemeInterface.Parameters(authentication: scheme),
                    configuration: configuration,
                    credential: nil
                )
            } throws: { error in
                guard case .missingCredential(let failed) = error as? RequestError else {
                    return false
                }
                return failed == scheme
            }
        }
    }

    @Test("A schemeless request needs no credential")
    func noneSchemeNeedsNoCredential() throws {
        let built = try request(
            SchemeInterface.Parameters(authentication: nil),
            configuration: ServerConfiguration(url: testServerURL),
            credential: nil
        )

        #expect(built.url?.absoluteString == "https://api.example.com/resource")
    }

    @Test("An authenticator that applies nothing fails the request")
    func inertAuthenticatorFails() {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.inert: InertAuthenticator()]
        )

        #expect {
            _ = try request(
                SchemeInterface.Parameters(authentication: .inert),
                configuration: configuration
            )
        } throws: { error in
            guard case .authenticatorAppliedNothing(let scheme) = error as? RequestError else {
                return false
            }
            return scheme == .inert
        }
    }

    @Test("An authenticator writing an undeclared query item name fails the request")
    func undeclaredQueryItemNameFails() {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.leaky: LeakyAuthenticator()]
        )

        #expect {
            _ = try request(
                SchemeInterface.Parameters(authentication: .leaky),
                configuration: configuration
            )
        } throws: { error in
            guard case .undeclaredQueryItemName(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .leaky && name == "secret"
        }
    }

    @Test("A URL-signing authenticator sees the path and query it signs")
    func urlSigningAuthenticatorSeesComponents() throws {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.urlSignature: URLSigningAuthenticator()]
        )

        let built = try request(
            SchemeInterface.Parameters(authentication: .urlSignature),
            configuration: configuration,
            credential: "key"
        )

        #expect(built.url?.query == "signature=key:/resource")
    }

    @Test("A stale token query item in the base URL fails the request")
    func baseURLTokenCollides() {
        let configuration = ServerConfiguration(
            url: URL(string: "https://api.example.com?token=stale")!
        )

        #expect {
            _ = try request(
                SchemeInterface.Parameters(authentication: .url),
                configuration: configuration,
                credential: "fresh"
            )
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .url && name == "token"
        }
    }

    @Test("A token query item in the endpoint's own parameters fails the request")
    func endpointTokenCollides() {
        #expect {
            _ = try request(
                SchemeInterface.Parameters(
                    authentication: .url,
                    queryItems: [URLQueryItem(name: "Token", value: "stale")]
                ),
                configuration: ServerConfiguration(url: testServerURL),
                credential: "fresh"
            )
        } throws: { error in
            guard case .credentialCollision(let scheme, _) = error as? RequestError else {
                return false
            }
            return scheme == .url
        }
    }

    @Test("A caller-supplied Authorization header fails a request declaring a header scheme")
    func callerAuthorizationHeaderCollides() {
        #expect {
            _ = try request(
                SchemeInterface.Parameters(
                    authentication: .bearer,
                    headers: ["Authorization": "Custom caller-value"]
                ),
                configuration: ServerConfiguration(url: testServerURL),
                credential: "abc123"
            )
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .bearer && name == "Authorization"
        }
    }

    @Test("A caller-supplied Authorization header is fine when the request declares no scheme")
    func callerAuthorizationHeaderWithoutSchemeIsFine() throws {
        let built = try request(
            SchemeInterface.Parameters(
                authentication: nil,
                headers: ["Authorization": "Custom caller-value"]
            ),
            configuration: ServerConfiguration(url: testServerURL),
            credential: nil
        )

        #expect(built.value(forHTTPHeaderField: "Authorization") == "Custom caller-value")
    }

    @Test("A defaultHeaders Authorization collides with a header scheme")
    func defaultHeaderAuthorizationCollides() {
        let configuration = ServerConfiguration(
            url: testServerURL,
            defaultHeaders: ["Authorization": "Static"]
        )

        #expect {
            _ = try request(
                SchemeInterface.Parameters(authentication: .bearer),
                configuration: configuration,
                credential: "abc123"
            )
        } throws: { error in
            if case .credentialCollision = error as? RequestError { return true }
            return false
        }
    }

    @Test("Request-side authentication runs after the body, so a signature can cover it")
    func signingAuthenticatorSeesTheBody() throws {
        let configuration = ServerConfiguration(
            url: testServerURL,
            authenticators: [.signature: BodySigningAuthenticator()]
        )

        let built = try request(
            SignedInterface.Parameters(),
            configuration: configuration,
            credential: "key"
        )

        let expectedLength = try #require(built.httpBody?.count)
        #expect(expectedLength > 0)
        #expect(built.value(forHTTPHeaderField: "X-Signature") == "key:POST:\(expectedLength)")
    }

    @Test("A configured authenticator reaches requests sent through APIClient")
    func authenticatorAppliesThroughAPIClient() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(responseData(), 200)

        let client = APIClient(
            configuration: ServerConfiguration(
                url: testServerURL,
                authenticators: [.bearer: .header("X-API-Key")]
            ),
            transport: transport,
            token: { "key-1" },
            refresh: {}
        )

        _ = try await client.send(SchemeInterface.self, .init(authentication: .bearer))

        let sent = try #require(await transport.requests.first)
        #expect(sent.value(forHTTPHeaderField: "X-API-Key") == "key-1")
    }

}

// MARK: - D. The challenge is a policy

@Suite("Authentication: challenge policy", .timeLimit(.minutes(1)))
struct AuthenticationChallengePolicyTests {

    private func client(
        _ transport: RecordingTransport,
        _ log: CallLog,
        policy: AuthenticationChallengePolicy = .unmodelled401
    ) -> APIClient {
        APIClient(
            configuration: ServerConfiguration(
                url: testServerURL,
                challengePolicy: policy
            ),
            transport: transport,
            token: { await log.recordToken(); return "token" },
            refresh: { await log.recordRefresh() }
        )
    }

    @Test("An unmodelled 401 still refreshes and retries")
    func unmodelled401Refreshes() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 401)
        await transport.enqueue(responseData(), 200)
        let log = CallLog()

        let result = try await client(transport, log)
            .send(SchemeInterface.self, .init(authentication: .bearer))

        #expect(result.value == "ok")
        #expect(await log.refreshCalls == 1)
        #expect(await transport.callCount == 2)
    }

    @Test("A 401 modelled as a typed error body surfaces without a refresh")
    func modelled401DecodedSurfacesDirectly() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(try JSONEncoder().encode(AuthFailure(reason: "bad password")), 401)
        let log = CallLog()

        let failure = await apiFailure {
            _ = try await self.client(transport, log).send(Models401DecodedInterface.self, .init())
        }
        #expect(failure?.responseError != nil)

        #expect(await log.refreshCalls == 0)
        #expect(await transport.callCount == 1)
    }

    @Test("A 401 modelled as a flat error surfaces without a refresh")
    func modelled401FlatSurfacesDirectly() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 401)
        let log = CallLog()

        let failure = await apiFailure {
            _ = try await self.client(transport, log).send(Models401FlatInterface.self, .init())
        }
        #expect(failure?.responseError != nil)

        #expect(await log.refreshCalls == 0)
        #expect(await transport.callCount == 1)
    }

    @Test("A 4xx range case is not a statement about 401, so refresh still fires")
    func rangeCoveringUnauthorizedStillRefreshes() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(try JSONEncoder().encode(AuthFailure(reason: "stale")), 401)
        await transport.enqueue(responseData(), 200)
        let log = CallLog()

        let result = try await client(transport, log).send(Range4xxInterface.self, .init())

        #expect(result.value == "ok")
        #expect(await log.refreshCalls == 1)
        #expect(await transport.callCount == 2)
    }

    @Test("A custom policy triggers refresh on a non-401 status")
    func customPolicyOnNon401() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 419)
        await transport.enqueue(responseData(), 200)
        let log = CallLog()

        let policy = AuthenticationChallengePolicy { error, _ in error.statusCode == 419 }
        let result = try await client(transport, log, policy: policy)
            .send(Stale419Interface.self, .init())

        #expect(result.value == "ok")
        #expect(await log.refreshCalls == 1)
        #expect(await transport.callCount == 2)
    }

    @Test(".any401 restores refresh for a modelled 401")
    func any401RestoresOldBehavior() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(try JSONEncoder().encode(AuthFailure(reason: "stale")), 401)
        await transport.enqueue(responseData(), 200)
        let log = CallLog()

        let result = try await client(transport, log, policy: .any401)
            .send(Models401DecodedInterface.self, .init())

        #expect(result.value == "ok")
        #expect(await log.refreshCalls == 1)
        #expect(await transport.callCount == 2)
    }

    @Test("A policy that never fires leaves the error untouched")
    func policyThatNeverFires() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(Data(), 401)
        let log = CallLog()

        let policy = AuthenticationChallengePolicy { _, _ in false }

        let failure = await apiFailure {
            _ = try await self.client(transport, log, policy: policy)
                .send(SchemeInterface.self, .init(authentication: .bearer))
        }
        #expect(failure?.responseError != nil)

        #expect(await log.refreshCalls == 0)
        #expect(await transport.callCount == 1)
    }

    @Test("A modelled 401 that refresh would have masked reaches the caller intact")
    func modelled401IsNotMaskedByAFailingRefresh() async throws {
        let transport = RecordingTransport()
        await transport.enqueue(try JSONEncoder().encode(AuthFailure(reason: "bad password")), 401)

        let client = APIClient(
            configuration: ServerConfiguration(url: testServerURL),
            transport: transport,
            token: { "token" },
            refresh: { throw FlatError.unauthorized }
        )

        do {
            _ = try await client.send(Models401DecodedInterface.self, .init())
            Issue.record("Expected the modelled 401 to surface")
        } catch .response(let error) {
            #expect(error.decodeError(as: AuthFailure.self) == AuthFailure(reason: "bad password"))
        } catch {
            Issue.record("Expected .response, got \(error)")
        }
    }

    @Test("unmodelled401 asks the response map rather than the thrown error case")
    func unmodelled401ConsultsTheMap() {
        let snapshot = HTTPResponseSnapshot(
            response: HTTPURLResponse(
                url: testServerURL,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
        )
        // A handler that reports every failure as `.generic` rather than `.unknownResponseCase`.
        let error = ResponseError.generic(
            ResponseBody(Data(), decoder: ResponseDecoder()),
            snapshot,
            FlatError.unauthorized
        )

        #expect(AuthenticationChallengePolicy.unmodelled401.isChallenge(error, [.code(200, .decode)]))
        #expect(!AuthenticationChallengePolicy.unmodelled401.isChallenge(
            error,
            [.code(401, .error(FlatError.unauthorized))]
        ))
        #expect(AuthenticationChallengePolicy.any401.isChallenge(
            error,
            [.code(401, .error(FlatError.unauthorized))]
        ))
    }

}

// MARK: - E. The builder cannot drop the credential

/// Builds a request from scratch and never mentions authentication, standing in for a builder
/// whose author did not know a credential was expected of it.
private struct CredentialObliviousBuilder: RequestBuilder {
    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        let base = URLRequestBuilder()

        var components = try base.makeComponents(context: context)
        base.applyPath(requestParameters.path, to: &components)
        base.applyQueryItems(requestParameters.queryItems, to: &components)

        return try base.finishRequest(
            requestParameters,
            components: components,
            context: context
        )
    }
}

/// Bakes in the header the bearer authenticator writes, so the collision check must still fire
/// on a request the default pipeline never saw.
private struct CollidingBuilder: RequestBuilder {
    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        var request = try URLRequestBuilder().buildRequest(requestParameters, context: context)
        request.setValue("Bearer baked-in", forHTTPHeaderField: "Authorization")
        return request
    }
}

@Suite("Authentication: builders cannot drop the credential", .timeLimit(.minutes(1)))
struct BuilderCredentialTests {

    private func request(
        _ parameters: some RequestParameters,
        builder: any RequestBuilder,
        authenticators: [AuthenticationScheme: any Authenticator]? = nil,
        credential: String? = "cred"
    ) throws -> URLRequest {
        let configuration =
            if let authenticators {
                ServerConfiguration(
                    url: testServerURL,
                    builder: builder,
                    authenticators: authenticators
                )
            } else {
                ServerConfiguration(url: testServerURL, builder: builder)
            }

        return try URLRequest(
            requestParameters: parameters,
            context: RequestContext(configuration: configuration, credential: credential)
        )
    }

    @Test("A builder that never mentions authentication still sends the bearer credential")
    func obliviousBuilderStillAuthenticates() throws {
        let built = try request(
            SchemeInterface.Parameters(authentication: .bearer),
            builder: CredentialObliviousBuilder(),
            credential: "abc123"
        )

        #expect(built.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test("A builder that never mentions authentication still carries a URL credential")
    func obliviousBuilderStillCarriesURLCredential() throws {
        let built = try request(
            SchemeInterface.Parameters(
                authentication: .url,
                queryItems: [URLQueryItem(name: "sort", value: "name")]
            ),
            builder: CredentialObliviousBuilder(),
            credential: "abc123"
        )

        #expect(built.url?.query == "sort=name&token=abc123")
    }

    @Test("A credential the builder baked in is still a collision")
    func bakedInCredentialCollides() throws {
        #expect {
            try request(
                SchemeInterface.Parameters(authentication: .bearer),
                builder: CollidingBuilder()
            )
        } throws: { error in
            guard case .credentialCollision(let scheme, let name) = error as? RequestError else {
                return false
            }
            return scheme == .bearer && name == "Authorization"
        }
    }

    @Test("A missing credential fails construction regardless of the builder")
    func missingCredentialSurvivesACustomBuilder() throws {
        #expect {
            try request(
                SchemeInterface.Parameters(authentication: .bearer),
                builder: CredentialObliviousBuilder(),
                credential: nil
            )
        } throws: { error in
            guard case .missingCredential(let scheme) = error as? RequestError else {
                return false
            }
            return scheme == .bearer
        }
    }

    @Test("A signing authenticator reads the body a custom builder produced")
    func signingAuthenticatorSeesACustomBuilderSBody() throws {
        let built = try request(
            SignedInterface.Parameters(),
            builder: CredentialObliviousBuilder(),
            authenticators: [.signature: BodySigningAuthenticator()],
            credential: "key"
        )

        let bodyCount = try #require(built.httpBody?.count)
        #expect(built.value(forHTTPHeaderField: "X-Signature") == "key:POST:\(bodyCount)")
    }

    @Test("A request declaring no scheme is untouched by a custom builder's authentication pass")
    func noSchemeNeedsNoCredential() throws {
        let built = try request(
            UnauthenticatedInterface.Parameters(),
            builder: CredentialObliviousBuilder(),
            credential: nil
        )

        #expect(built.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(built.url?.query == nil)
    }

}
