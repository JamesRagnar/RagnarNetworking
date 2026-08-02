# RequestPipeline and Transport

Running an Interface request is three jobs, and each has its own owner:

- `RequestBuilder` turns typed parameters into a `URLRequest`.
- `Transport` executes that `URLRequest` and returns bytes.
- `ResponseHandler` turns the bytes back into the Interface's `Response`.

`RequestPipeline` composes the three. `APIClient` layers credentials, challenge retry, and invalidation on top of it.

## Transport

`Transport` has exactly one requirement, so a conformer cannot accidentally bypass request construction or response handling:

```swift
public protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

`URLSession` conforms by default.

## Transport Decoration

A `Transport` that holds another `Transport`, acts, and calls `next` is this package's middleware seam. It covers retry, backoff, logging with timing, correlation IDs, user-agent stamping, request signing, and cache short-circuiting.

```swift
struct SigningTransport: Transport {
    let next: any Transport
    let sign: @Sendable (URLRequest) -> String

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var signed = request
        signed.setValue(sign(request), forHTTPHeaderField: "X-Signature")
        return try await next.data(for: signed)
    }
}
```

Decorators compose as an ordered chain. The outermost runs first on the way out and last on the way back:

```swift
let pipeline = RequestPipeline(
    transport: SigningTransport(
        next: RetryingTransport(next: URLSession.shared),
        sign: sign
    )
)
```

A decorator receives the finished, authenticated request: the builder has run and the credential is applied.

Choose a decorator over a `RequestBuilder` when the concern is the exchange rather than the endpoint. A builder sees typed parameters and runs once per request; a decorator sees a `URLRequest` and may run zero times on a cache hit or many times on retry.

The request carries no operation identity, so per-endpoint metrics cannot name the endpoint. Carry a correlation header to associate them.

## Default Usage

Most consumers should use `APIClient`. Use `RequestPipeline` directly when you manage the token yourself:

```swift
let pipeline = RequestPipeline(transport: URLSession.shared)
let context = RequestContext(configuration: config, credential: token)

let user = try await pipeline.send(
    GetUserInterface.self,
    .init(userId: 123),
    context: context
)
```

The context's `responseDecoder` is threaded into response handling, so success bodies and typed error bodies decode with the same configured rules.

`RequestPipeline` owns the algorithm and the `Transport`, and nothing else. Everything that describes the server - builder, coding, headers, default response handler - arrives on the `RequestContext`, so there is one source of truth for it and no precedence rule to remember.

## Custom Request Construction

Set a custom `RequestBuilder` on the configuration to override how requests are built. Builders are values, so a builder can carry its own state:

```swift
struct ClientTaggingBuilder: RequestBuilder {
    let clientID: String

    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        var request = try URLRequestBuilder().buildRequest(requestParameters, context: context)

        var current = request.allHTTPHeaderFields ?? [:]
        current["X-Client"] = clientID
        request.allHTTPHeaderFields = current

        return request
    }
}

let context = RequestContext(
    configuration: ServerConfiguration(
        url: serverURL,
        builder: ClientTaggingBuilder(clientID: "ios")
    ),
    credential: token
)

let pipeline = RequestPipeline(transport: URLSession.shared)
```

Delegating to `URLRequestBuilder()`'s public steps for everything a builder does not change limits the change to that step. See [Request Builder](Interfaces/request_builder.md) for invariants and composition.

A builder does not apply credentials. `URLRequest.init(requestParameters:context:)` runs the builder and then the registered `Authenticator`.

## Testing

A mock `Transport` terminates the chain instead of extending it. Because it only supplies bytes, tests still exercise the real request-construction and response-handling paths:

```swift
actor MockTransport: Transport {
    var response: (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        response
    }
}
```
