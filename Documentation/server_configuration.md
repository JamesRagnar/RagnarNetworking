# Server Configuration

`ServerConfiguration` is pure policy: where the server lives, how bodies are encoded and decoded, and which headers every request carries. It is stable for a client's lifetime.

Credentials are deliberately not part of it. A per-request token travels in `RequestContext`, which pairs a configuration with the token to use for one request:

```swift
let config = ServerConfiguration(url: URL(string: "https://api.example.com")!)
let context = RequestContext(configuration: config, authToken: "token")
```

`APIClient` takes a `ServerConfiguration` and holds it for its lifetime, building a `RequestContext` with the current token on every request. Construct a `RequestContext` yourself only when calling `RequestPipeline` or `URLRequest`'s initializers without `APIClient`.

## Request Encoder

Request bodies are encoded using a `RequestEncoder` factory to keep Swift 6 Sendable conformance (JSONEncoder is not Sendable).

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    requestEncoder: RequestEncoder(
        keyEncodingStrategy: .convertToSnakeCase,
        dateEncodingStrategy: .iso8601
    )
)
```

You can also provide a custom factory for full control:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    requestEncoder: RequestEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
)
```

## Response Decoder

Response bodies are decoded using a `ResponseDecoder` factory, mirroring `RequestEncoder`.

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    responseDecoder: ResponseDecoder(
        keyDecodingStrategy: .convertFromSnakeCase,
        dateDecodingStrategy: .iso8601
    )
)
```

You can also provide a custom factory for full control:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    responseDecoder: ResponseDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
)
```

The configured decoder reaches every body the client reads: success bodies, typed error bodies declared with `ResponseOutcome.decodeError`, and `ResponseError.decodeError(as:)` at a catch site. See [Response Handling](Interfaces/response_handling.md#response-decoder).

## Default Headers

`defaultHeaders` are applied to every request built from the configuration. A header with the same name in a request's own `headers` takes precedence, matched case-insensitively per HTTP semantics, so a default `content-type` and a request `Content-Type` resolve to a single header rather than two entries whose winner is unspecified.

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    defaultHeaders: ["Accept-Language": "en-US"]
)
```

Resolution lives on `ServerConfiguration` rather than inside the request-building pipeline:

```swift
let headers = config.resolvedHeaders(for: parameters)
```

`RequestBuilder.buildRequest` receives headers already resolved, so no custom builder can drop `defaultHeaders` by overriding a pipeline step.

## Request Context and Auth Token Behavior

`RequestContext` carries the credential and forwards the configuration's `url`, `requestEncoder`, `responseDecoder`, and header resolution:

```swift
let context = RequestContext(configuration: config, authToken: "token")
context.url                          // config.url
context.responseDecoder              // config.responseDecoder
context.resolvedHeaders(for: params) // defaultHeaders overlaid with the request's own
```

The token is applied based on the request's `AuthenticationType`:
- `.bearer` adds `Authorization: Bearer <token>` (can be overridden by a custom `Authorization` header)
- `.url` appends `?token=<token>` and removes any existing `token` query items (case-insensitive) from both the base URL and request parameters
- `.none` ignores the token

A context with no token (`RequestContext(configuration: config)`) fails `.bearer` and `.url` requests with `RequestError.authentication`.
