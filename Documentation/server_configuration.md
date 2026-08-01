# Server Configuration

`ServerConfiguration` is pure policy: where the server lives, how bodies are encoded and decoded, which headers every request carries, and how requests and responses are shaped. It is stable for a client's lifetime.

## Where a Knob Belongs

**`ServerConfiguration` describes the server. `RequestPipeline` supplies the machinery. `APIClient` owns credential lifecycle.**

Two things are deliberately not on the configuration:

- **Credentials.** A per-request token travels in `RequestContext`, so a configuration can be shared freely without carrying a volatile secret.
- **The `Transport`.** A transport answers "what process are we in?" - a live `URLSession`, a mock, a recorded fixture - rather than "which server is this?", so it belongs to `RequestPipeline` and stays available as the test seam.

Everything else that describes the server belongs here: `url`, `requestEncoder`, `responseDecoder`, `defaultHeaders`, `builder`, and `responseHandler`.

A per-request token travels in `RequestContext`, which pairs a configuration with the token to use for one request:

```swift
let config = ServerConfiguration(url: URL(string: "https://api.example.com")!)
let context = RequestContext(configuration: config, authToken: "token")
```

`APIClient` takes a `ServerConfiguration` and holds it for its lifetime, building a `RequestContext` with the current token on every request. Construct a `RequestContext` yourself only when calling `RequestPipeline` or `URLRequest`'s initializers without `APIClient`.

## Request Encoder

`RequestEncoder` is a factory that produces a configured `JSONEncoder` per request.

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

## Request Builder

`builder` constructs every `URLRequest` for this server. See [Request Builder](Interfaces/request_builder.md).

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    builder: ClientTaggingBuilder(clientID: "ios")
)
```

## Response Handler

`responseHandler` handles every response for this server, except for Interfaces that declare their own `Interface.responseHandler`. Set it for a concern that spans the whole API - unwrapping a `{ "data": ... }` envelope, reading a deprecation header, feeding a metrics sink - so it is written once instead of on every Interface.

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    responseHandler: EnvelopeUnwrappingHandler()
)
```

An Interface-level handler *replaces* this one rather than layering on top of it. See [Response Handling](Interfaces/response_handling.md).

## Request Context and Auth Token Behavior

`RequestContext` carries the credential and forwards the configuration's `url`, `requestEncoder`, `responseDecoder`, `builder`, `responseHandler`, and header resolution:

```swift
let context = RequestContext(configuration: config, authToken: "token")
context.url                          // config.url
context.responseDecoder              // config.responseDecoder
context.builder                      // config.builder
context.responseHandler              // config.responseHandler
context.resolvedHeaders(for: params) // defaultHeaders overlaid with the request's own
```

The token is applied based on the request's `AuthenticationType`:
- `.bearer` adds `Authorization: Bearer <token>` (can be overridden by a custom `Authorization` header)
- `.url` appends `?token=<token>` and removes any existing `token` query items (case-insensitive) from both the base URL and request parameters
- `.none` ignores the token

A context with no token (`RequestContext(configuration: config)`) fails `.bearer` and `.url` requests with `RequestError.authentication`.
