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
let context = RequestContext(configuration: config, credential: "token")
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

### Overriding One Strategy

Both `RequestEncoder` and `ResponseDecoder` have a `modified(_:)` that returns a copy with one
strategy changed and the rest of the configuration intact:

```swift
encoder.modified { $0.dateEncodingStrategy = .secondsSince1970 }
decoder.modified { $0.dateDecodingStrategy = .secondsSince1970 }
```

This is what a `RequestBody` or `InterfaceResponse` conformance uses when one type's wire format
differs from the rest of the API. Constructing a bare `JSONEncoder()` or `JSONDecoder()` there
instead discards the configuration silently. See
[Deriving an Encoder](Interfaces/request_parameters.md#deriving-an-encoder) and
[Deriving a Decoder](Interfaces/response_handling.md#deriving-a-decoder).

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

`RequestBuilder.buildRequest` receives headers already resolved, so no custom builder can drop `defaultHeaders`.

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
let context = RequestContext(configuration: config, credential: "token")
context.url                          // config.url
context.responseDecoder              // config.responseDecoder
context.builder                      // config.builder
context.responseHandler              // config.responseHandler
context.resolvedHeaders(for: params) // defaultHeaders overlaid with the request's own
```

The credential is applied by the `Authenticator` registered for the request's `AuthenticationScheme`:

- A request declaring no scheme ignores the credential entirely, with no authenticator lookup.
- `.bearer` adds `Authorization: Bearer <credential>` by default. A caller-supplied `Authorization` header is a collision and fails the request.
- `.url` appends `?token=<credential>` by default. An existing `token` query item in the base URL or the request parameters is a collision and fails the request.

A context with no credential (`RequestContext(configuration: config)`) fails any request declaring a scheme with `RequestError.missingCredential`.

## Authenticators

`authenticators` gives each `AuthenticationScheme` its meaning for this server, defaulting to `[.bearer: .bearer, .url: .token]`.

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authenticators: [
        .bearer: .bearer,
        .url: .queryItem("access_token")
    ]
)
```

`redactedQueryItemNames` is computed at init as the union of the registered authenticators' own names, and strips those query items from the URL captured in `HTTPResponseSnapshot`. Request construction rejects an authenticator that writes a name outside its own declaration, so redaction cannot drift out of step with what is written.

## Challenge Policy

`challengePolicy` decides which failures mean the credential is stale, defaulting to `.unmodelled401`. See [Authentication](Interfaces/authentication.md).

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    challengePolicy: .any401
)
```
