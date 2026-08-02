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

Overriding a single `RequestBuilder` step and delegating to `URLRequestBuilder()` for the remaining steps limits the change to that step. See [Request Builder](Interfaces/request_builder.md) for invariants and override behavior.

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
