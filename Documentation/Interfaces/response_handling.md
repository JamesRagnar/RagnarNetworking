# Response Handling

Interfaces declare which HTTP status codes produce their associated `Response` and which produce
failures. The configured `ResponseHandler` interprets that contract and builds the response.

## Response Contract

```swift
static let responses = ResponseContract<Response>(
    success: .exact(200),
    failures: [
        .code(404, .error(APIError.userNotFound)),
        .clientError(.decodeError(APIErrorBody.self))
    ]
)
```

`ResponseContract<Response>` is generic over the Interface's successful type. Its initializer
requires a first success matcher, so an Interface cannot declare a `Response` with no status path
capable of producing it. Failure cases accept only `FailureOutcome`, so a failure matcher cannot
be assigned successful decoding.

## Successful Responses

A successful match asks `Response` to build itself from whatever bytes arrived, which for a
204/205/304 is none. Multiple successful codes all build the same declared `Response` type:

```swift
static let responses = ResponseContract<Response>(
    success: .exact(200),
    additionalSuccesses: [.exact(201), .exact(202)]
)
```

A no-body success needs no separate outcome. `EmptyResponse`, `Data`, and `String` all build
themselves from an empty body, so `.exact(204)` is the successful matcher:

```swift
struct DeleteUser: Interface {
    struct Request: InterfaceRequest {
        let method: RequestMethod = .delete
        let path = "/users/123"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer
    }

    typealias Response = EmptyResponse

    static let responses = ResponseContract<Response>(success: .exact(204))
}
```

A `Response` that cannot be built from zero bytes, such as a JSON struct, fails with
`ResponseError.decoding` against the empty body. That is the same failure as any other body
mismatch, and the fix is the same: declare the `Response` the endpoint actually returns.

An Interface with no success matcher does not compile because `ResponseContract` has no empty or
failure-only initializer.

## Response Handlers

`ServerConfiguration.responseHandler` handles every response for that server. Use it for a
concern that spans the API: unwrapping a `{ "data": ... }` envelope, reading a deprecation
header, or feeding a metrics sink. It defaults to `DefaultResponseHandler()`.

Handlers are values, so a handler can carry its own state.

### Composing with DefaultResponseHandler

A custom `ResponseHandler` that only needs a targeted addition to the default behavior
(for example, inspecting a header before decoding) does not need to reimplement status-code
matching. `DefaultResponseHandler.handle(_:for:context:)` is public, so a custom handler can do
its own work and then delegate. `DefaultResponseHandler.decode(_:as:metadata:responseDecoder:)`
is public too, for a handler that drives its own status matching but still wants the default
type-driven decoding: it asks `Response` to build itself via `InterfaceResponse` and normalizes
whatever it throws into an `InterfaceDecodingError`.

```swift
public struct LoggingResponseHandler: ResponseHandler {
    private let base = DefaultResponseHandler()

    public func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        context: ResponseContext
    ) throws(ResponseError) -> T.Response {
        log(response.response)
        return try base.handle(response, for: interface, context: context)
    }
}
```

### Matching Priority

- Exact status codes match first.
- Success ranges are evaluated next, in declaration order.
- Failure ranges are evaluated last, in declaration order.
- Duplicate exact codes keep the first declaration. Later duplicates are ignored.
- Duplicate exact codes emit a developer diagnostic through `Logger`, in every build configuration.

This means an exact failure can override a broad success range:

```swift
static let responses = ResponseContract<Response>(
    success: .success,
    failures: [.code(202, .error(APIError.unexpectedAccepted))]
)
```

### Resolution Rules (Quick Reference)

Given a status code, `ResponseContract` resolves matches in this order:
1. Exact code lookup (O(1))
2. First matching success range
3. First matching failure range
4. No match -> `ResponseError.unknownResponseCase`

Examples:

```swift
// Exact failure beats success range
static let responses = ResponseContract<Response>(
    success: .success,
    failures: [.code(202, .error(APIError.unexpectedAccepted))]
)
```

```swift
// Failure range order matters
static let responses = ResponseContract<Response>(
    success: .exact(200),
    failures: [
        .range(400..<500, .error(APIError.client)),
        .range(400..<600, .error(APIError.clientOrServer))
        // 404 resolves to APIError.client
    ]
)
```

```swift
// Duplicate exact codes: first wins
static let responses = ResponseContract<Response>(
    success: .exact(200),
    failures: [
        .code(401, .error(APIError.unauthorized)),
        .code(401, .error(APIError.sessionExpired)) // ignored, logs a diagnostic
    ]
)
```

### decodeError Behavior

`.decodeError` attempts to decode the response body into a typed `Error`. The decoded error is stored in `ResponseError.decoded`, and `ResponseError.decodeError(as:)` will return it without re-decoding when the types match.

When decoding fails (empty body, non-JSON response, malformed JSON), the error is surfaced as:

- `ResponseError.decoding(_, _, .jsonDecoder(...))` - for `DecodingError` failures (invalid JSON, missing keys, type mismatches)
- `ResponseError.decoding(_, _, .custom(message: ...))` - for other errors thrown by the decode closure

The raw response data is always preserved, so you can still inspect `responseBodyString`.

Error bodies decode with the same `ResponseDecoder` as success bodies. `responses` is static and
has no access to a live `ServerConfiguration`, so the decoder is handed to the
outcome at handling time rather than captured at declaration time: `.decodeError(body:)` receives
`(Data, ResponseDecoder)`, and `.decodeError(_:)` uses that decoder for you.

```swift
static let responses = ResponseContract<Response>(
    success: .exact(200),
    failures: [
        .code(400, .decodeError(APIErrorBody.self)),
        .code(418, .decodeError(body: { data, decoder in
            try decoder.makeJSONDecoder().decode(TeapotError.self, from: data)
        }))
    ]
)
```

`ResponseError` carries its body as a `ResponseBody` - the raw bytes plus the decoder the
response was handled with - so `decodeError(as:)` at a catch site needs no decoder argument and
cannot silently fall back to a plain `JSONDecoder`.

## Response Decoder

`handle(_:responseDecoder:)` decodes bodies using a `ResponseDecoder`, mirroring how requests
are encoded via `RequestEncoder`. The decoder is a required argument rather than a defaulted one,
so a caller cannot silently fall back to a plain `JSONDecoder` and lose the client's rules. Going
through `APIClient` or `RequestPipeline`, it is always `ServerConfiguration.responseDecoder`.

There is no per-Interface decoder or handler override. When one endpoint's field names, date
format, or successful wire shape differs from the rest of the API, express that on the `Response`
type itself with `CodingKeys`, a custom `init(from:)`, or `InterfaceResponse.decode`.
See [Server Configuration](../server_configuration.md#response-decoder).

## Decoding Rules

An `Interface.Response` conforms to `InterfaceResponse`, which owns how the type is built from a
response. This mirrors `RequestBody` on the request side: the type that knows the format
implements the conversion, rather than the handler comparing `Response.self` against a fixed list
of known types.

A `Decodable` type conforms without implementing anything and decodes as JSON with the configured
`ResponseDecoder`:

```swift
struct User: Codable, InterfaceResponse {
    let id: Int
    let name: String
}
```

The package ships conformances for:
- `String` (UTF-8)
- `Data` (raw bytes)
- `EmptyResponse` (no body; succeeds for any bytes, including none)
- `Int`, `Int64`, `Double`, `Bool` (top-level JSON scalars)
- `Optional` of a `Decodable` wrapped type (a top-level `null` decodes as `nil`)
- `Array` of `Decodable` elements (top-level JSON array)
- `Dictionary` of `Decodable` keys and values, with the caveat below

The explicit conformance is deliberate, for the same reason `InterfaceRequest` has no defaulted
members: it keeps the response contract stated rather than inferred.

### Dictionary Key Types

The `Dictionary` conformance inherits the standard library's `Dictionary: Decodable` behavior
verbatim, and that behavior depends on the key type:

| `Response` | `{"a": 1}` | `["a", 1]` |
|---|---|---|
| `[String: Int]` | decodes | throws |
| `[Int: String]` (against `{"1": "x"}`) | decodes | throws |
| `[MyEnum: Int]` | **throws** | decodes |
| `[MyEnum: Int]` where `MyEnum: CodingKeyRepresentable` | decodes | throws |

A key type that is neither `String`, nor `Int`, nor `CodingKeyRepresentable` decodes from an
**alternating unkeyed array**, not from an object. Conform the key type to
`CodingKeyRepresentable` when the server sends an object.

### Where a Coding Difference Belongs

"One endpoint decodes differently" can describe several separate problems with different homes.

| Difference | Home |
|---|---|
| One field's format | `CodingKeys`, a custom `init(from:)`, or a property wrapper on the `Response` type |
| A type's coding strategy | `InterfaceResponse.decode` plus `ResponseDecoder.modified` |
| A type's whole wire format (CSV, protobuf) | `InterfaceResponse.decode`, ignoring the decoder |
| API-wide response interpretation | `ServerConfiguration.responseHandler` |

Format is a property of the type, not the endpoint. A type returned by four endpoints declares
its quirk once and no endpoint can forget it.

### Deriving a Decoder

`ResponseDecoder.modified(_:)` returns a copy with one strategy changed and everything else
intact. Use it rather than building a `JSONDecoder()`, which silently discards the client's
configuration:

```swift
struct LegacyOrder: Decodable, InterfaceResponse {
    let orderId: Int
    let placedAt: Date

    static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> LegacyOrder {
        try decoder
            .modified { $0.dateDecodingStrategy = .secondsSince1970 }
            .decode(LegacyOrder.self, from: data)
    }
}
```

Against a client configured with `.convertFromSnakeCase` and `.iso8601`, this decodes
`{"order_id": 7, "placed_at": 1700000000}`: the key strategy still applies, only the date
strategy is replaced. `modified` composes, and the last applied strategy wins.

`RequestEncoder.modified(_:)` is the request-side equivalent. See
[Request Request](request_parameters.md#deriving-an-encoder).

### Non-JSON Responses

Conform directly when a response is not JSON. Nothing in the package needs to change:

```swift
struct CSVRows: InterfaceResponse, Sendable {
    let rows: [[String]]

    static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> CSVRows {
        guard let text = String(data: data, encoding: .utf8) else {
            throw InterfaceDecodingError.missingString
        }

        return CSVRows(
            rows: text.split(separator: "\n").map { $0.split(separator: ",").map(String.init) }
        )
    }
}
```

A conformance may throw any error type. `DefaultResponseHandler` normalizes what it throws into
`InterfaceDecodingError`: a `DecodingError` becomes `.jsonDecoder` with structured diagnostics, an
`InterfaceDecodingError` passes through, and anything else becomes `.custom`.

`ResponseDecoder` still wraps a `JSONDecoder` factory rather than an open codec abstraction, so
the *default* path is JSON-only by design. `InterfaceResponse` is the extension point for
everything else, and it is per-type rather than per-client.

### Responses That Depend on Headers

`decode` receives an `HTTPResponseSnapshot` alongside the bytes, so a response whose value depends
on the status code or a header can be built here rather than requiring a whole `ResponseHandler`:

```swift
struct PagedNames: InterfaceResponse, Sendable {
    let names: [String]
    let totalCount: Int?

    static func decode(
        from data: Data,
        metadata: HTTPResponseSnapshot,
        using decoder: ResponseDecoder
    ) throws -> PagedNames {
        PagedNames(
            names: try decoder.makeJSONDecoder().decode([String].self, from: data),
            totalCount: metadata.headers
                .first { $0.key.caseInsensitiveCompare("X-Total-Count") == .orderedSame }
                .flatMap { Int($0.value) }
        )
    }
}
```

This covers `ETag`, `Link` pagination, `X-Total-Count`, and `Content-Range`. The snapshot is the
same redacted value `ResponseError` carries, and it is available for a no-body success too.

### Why InterfaceResponse Does Not Refine Sendable

`Interface.Response` requires `InterfaceResponse & Sendable` rather than `InterfaceResponse`
refining `Sendable` directly. The refinement **compiles**, but it is unsound.

A conditional conformance cannot depend on a marker protocol, so the `Array` conformance has to be
written `where Element: Decodable`, without `Sendable`. If `InterfaceResponse` refined `Sendable`,
`[T]` would then satisfy `Sendable` through that conformance without `Array`'s own conditional
`Sendable` ever being checked. A non-`Sendable` element type would cross a concurrency boundary
with no diagnostic:

```swift
final class Box: Decodable { var v = 0 }   // not Sendable

// With `protocol InterfaceResponse: Sendable`, this compiles clean:
func ship<T: InterfaceResponse>(_ value: T, to sink: Sink) async {
    await sink.take(value)                  // T: Sendable "for free"
}
```

Requiring `Sendable` at the use site forces the real `Array<Box>: Sendable` check, which fails as
it should. The guarantee is **stronger** this way, not merely preserved.

## Response Errors

`ResponseError` captures failures with the response body (bytes plus the decoder that was
configured to read them) and response metadata:
- `.unknownResponse`
- `.unknownResponseCase`
- `.decoding`
- `.generic`
- `.decoded`

`InterfaceDecodingError` indicates decoding specifics:
- `.missingString`
- `.jsonDecoder(DecodingDiagnostics)`
- `.custom(message:)`

## Error Helpers

`ResponseError` provides helpers for inspection:

```swift
catch let error as ResponseError {
    let statusCode = error.statusCode
    let body = error.responseBodyString
    let retryable = error.isRetryable
    let requestId = error.header("X-Request-ID")
    let apiError = error.decodeError(as: APIErrorBody.self)
}
```

`error.body` exposes the `ResponseBody` directly (`body.data`, `body.decoder`, `body.stringValue`,
`body.decode(as:)`) when you need more than the helpers above.
