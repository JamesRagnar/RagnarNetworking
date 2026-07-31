# RequestPipeline and Transport

Running an Interface request is three jobs, and each has its own owner:

- `RequestBuilder` turns typed parameters into a `URLRequest`.
- `Transport` executes that `URLRequest` and returns bytes.
- `ResponseHandler` turns the bytes back into the Interface's `Response`.

`RequestPipeline` composes the three. `APIClient` layers credentials, 401 retry, and invalidation on top of it.

## Transport

`Transport` has exactly one requirement, so a conformer cannot accidentally bypass request construction or response handling:

```swift
public protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

`URLSession` conforms by default.

## Default Usage

Most consumers should use `APIClient`. Use `RequestPipeline` directly when you manage the token yourself:

```swift
let pipeline = RequestPipeline(transport: URLSession.shared)
let context = RequestContext(configuration: config, authToken: token)

let user = try await pipeline.send(
    GetUserInterface.self,
    .init(userId: 123),
    context: context
)
```

The context's `responseDecoder` is threaded into response handling, so success bodies and typed error bodies decode with the same configured rules.

## Custom Request Construction

Inject a custom `RequestBuilder` to override how requests are built. Builders are values, so a builder can carry its own state:

```swift
struct ClientTaggingBuilder: RequestBuilder {
    let clientID: String

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
        current["X-Client"] = clientID
        request.allHTTPHeaderFields = current
    }
}

let pipeline = RequestPipeline(
    transport: URLSession.shared,
    builder: ClientTaggingBuilder(clientID: "ios")
)
```

Prefer overriding a single `RequestBuilder` step and delegating to `URLRequestBuilder()` for the default behavior. See [Request Builder](Interfaces/request_builder.md) for invariants and override guidance.

## Testing

Implement `Transport` in a mock to control responses without making real network calls. Because the mock only supplies bytes, tests still exercise the real request-construction and response-handling paths:

```swift
actor MockTransport: Transport {
    var response: (Data, URLResponse)

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        response
    }
}
```
