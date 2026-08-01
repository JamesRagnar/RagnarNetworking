# Response Handling

Interfaces map HTTP status codes to outcomes (decode success, throw a predefined error, or decode an error body). The default `handle(_:responseDecoder:)` path applies this mapping and decodes the response.

## Response Cases

```swift
static var responseCases: ResponseMap {
    [
        .code(200, .decode),
        .code(404, .error(APIError.userNotFound)),
        .clientError(.decodeError(APIErrorBody.self))
    ]
}
```

## Success Outcomes

Response cases can either decode a body or indicate a successful response with no body.

- `.decode` expects a response body that can be decoded as the Interface `Response`.
- `.noContent` marks a success with no body (e.g., 204/205/304).

When `handle(_:responseDecoder:)` encounters `.noContent`, the default handler treats it as a success
with an empty body. This succeeds for `Data`, `String`, or `EmptyResponse` responses.

```swift
struct DeleteUser: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .delete
        let path = "/users/123"
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationType = .bearer
    }

    typealias Response = EmptyResponse

    static var responseCases: ResponseMap {
        [.code(204, .noContent)]
    }
}
```
For custom no-content behavior, override the Interface `responseHandler`.

## Response Handlers

Response handling is set in two places, and the rule between them is simple:

- **`ServerConfiguration.responseHandler`** handles every response for that server. Use it for a
  concern that spans the API: unwrapping a `{ "data": ... }` envelope, reading a deprecation
  header, feeding a metrics sink. Defaults to `DefaultResponseHandler()`.
- **`Interface.responseHandler`** overrides it for one endpoint. Defaults to `nil`, meaning "use
  the configured one". Use it for the one-off endpoint whose response does not follow the rest of
  the API.

An Interface-level handler **replaces** the configured one rather than layering on top of it. An
endpoint that overrides in an API whose configuration unwraps an envelope has to unwrap that
envelope itself.

Handlers are values, so a handler can carry its own state.

```swift
public struct GetLibraryItemCover: Interface {
    public static var responseHandler: (any ResponseHandler)? {
        CoverResponseHandler()
    }
}

public struct CoverResponseHandler: ResponseHandler {
    public func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        responseDecoder: ResponseDecoder
    ) throws(ResponseError) -> T.Response {
        let body = ResponseBody(response.data, decoder: responseDecoder)
        let snapshot = HTTPResponseSnapshot(response: response.response)
        guard let statusCode = snapshot.statusCode else {
            throw ResponseError.unknownResponse(body, snapshot)
        }

        if statusCode == 204 {
            guard let empty = Data() as? T.Response else {
                throw ResponseError.decoding(
                    body,
                    snapshot,
                    .custom(message: "Expected Data response type for 204")
                )
            }
            return empty
        }

        return try DefaultResponseHandler().handle(response, for: interface, responseDecoder: responseDecoder)
    }
}
```

### Composing with DefaultResponseHandler

A custom `ResponseHandler` that only needs a targeted addition to the default behavior
(for example, inspecting a header before decoding) does not need to reimplement status-code
matching. `DefaultResponseHandler.handleOutcome(_:for:responseDecoder:)` performs the same matching `handle`
does, returning a `ResponseOutcomeResult` instead of deciding what to do with a `.noContent`
result. `DefaultResponseHandler.decode(_:as:responseDecoder:)` performs the same decoding `handle`
uses to finish a `.noContent` result: it asks `Response` to build itself via `InterfaceResponse`
and normalizes whatever it throws into an `InterfaceDecodingError`.

```swift
public struct LoggingResponseHandler: ResponseHandler {
    private let base = DefaultResponseHandler()

    public func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type,
        responseDecoder: ResponseDecoder
    ) throws(ResponseError) -> T.Response {
        switch try base.handleOutcome(response, for: interface, responseDecoder: responseDecoder) {
        case .decoded(let value):
            return value

        case .noContent:
            do {
                return try base.decode(Data(), as: interface, responseDecoder: responseDecoder)
            } catch {
                throw ResponseError.decoding(
                    ResponseBody(response.data, decoder: responseDecoder),
                    HTTPResponseSnapshot(response: response.response),
                    error
                )
            }
        }
    }
}
```

### Matching Priority

- Exact status codes match first.
- Range matches are evaluated in the order they are defined.
- Duplicate exact codes keep the first declaration. Later duplicates are ignored.
- In DEBUG builds, duplicate exact codes emit a developer diagnostic.

This means you can declare a fallback range and still override specific status codes later:

```swift
static var responseCases: ResponseMap {
    [
        .clientError(.error(APIError.genericClientError)),
        .code(401, .error(APIError.unauthorized))
    ]
}
```

### Resolution Rules (Quick Reference)

Given a status code, `ResponseMap` resolves outcomes in this order:
1. Exact code lookup (O(1))
2. First matching range (in declaration order)
3. No match -> `ResponseError.unknownResponseCase`

Examples:

```swift
// Exact beats range
static var responseCases: ResponseMap {
    [
        .success(.error(APIError.genericSuccess)),
        .code(200, .decode) // wins for 200
    ]
}
```

```swift
// Range order matters
static var responseCases: ResponseMap {
    [
        .range(400..<500, .error(APIError.client)),
        .range(400..<600, .error(APIError.clientOrServer))
        // 404 resolves to APIError.client (first matching range)
    ]
}
```

```swift
// Duplicate exact codes: first wins
static var responseCases: ResponseMap {
    [
        .code(401, .error(APIError.unauthorized)),
        .code(401, .error(APIError.sessionExpired)) // ignored, DEBUG developer diagnostic
    ]
}
```

### decodeError Behavior

`.decodeError` attempts to decode the response body into a typed `Error`. The decoded error is stored in `ResponseError.decoded`, and `ResponseError.decodeError(as:)` will return it without re-decoding when the types match.

When decoding fails (empty body, non-JSON response, malformed JSON), the error is surfaced as:

- `ResponseError.decoding(_, _, .jsonDecoder(...))` - for `DecodingError` failures (invalid JSON, missing keys, type mismatches)
- `ResponseError.decoding(_, _, .custom(message: ...))` - for other errors thrown by the decode closure

The raw response data is always preserved, so you can still inspect `responseBodyString`.

Error bodies decode with the same `ResponseDecoder` as success bodies. `responseCases` is a
`static var` with no access to a live `ServerConfiguration`, so the decoder is handed to the
outcome at handling time rather than captured at declaration time: `.decodeError(body:)` receives
`(Data, ResponseDecoder)`, and `.decodeError(_:)` uses that decoder for you.

```swift
static var responseCases: ResponseMap {
    [
        .code(400, .decodeError(APIErrorBody.self)),
        .code(418, .decodeError(body: { data, decoder in
            try decoder.makeJSONDecoder().decode(TeapotError.self, from: data)
        }))
    ]
}
```

`ResponseError` carries its body as a `ResponseBody` - the raw bytes plus the decoder the
response was handled with - so `decodeError(as:)` at a catch site needs no decoder argument and
cannot silently fall back to a plain `JSONDecoder`.

## Response Decoder

`handle(_:responseDecoder:)` decodes bodies using a `ResponseDecoder`, mirroring how requests
are encoded via `RequestEncoder`. The decoder is a required argument rather than a defaulted one,
so a caller cannot silently fall back to a plain `JSONDecoder` and lose the client's rules. Going
through `APIClient` or `RequestPipeline`, it is always `ServerConfiguration.responseDecoder`.

There is no per-Interface decoder override. When one endpoint's field names or date format differ
from the rest of the API, express that on the `Response` type itself with `CodingKeys` or a custom
`init(from:)`; reach for `responseHandler` when the *interpretation* of the response differs, not
just its field names. See [Server Configuration](../server_configuration.md#response-decoder).

## Decoding Rules

An `Interface.Response` conforms to `InterfaceResponse`, which owns how the type is built from
response bytes. This mirrors `RequestBody` on the request side: the type that knows the format
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
- `Array` and `Dictionary` of `Decodable` elements (top-level JSON collections)

The explicit conformance is deliberate, for the same reason `RequestParameters` has no defaulted
members: an omission should fail at compile time rather than at the first real request.

### Non-JSON Responses

Conform directly when a response is not JSON. Nothing in the package needs to change:

```swift
struct CSVRows: InterfaceResponse, Sendable {
    let rows: [[String]]

    static func decode(from data: Data, using decoder: ResponseDecoder) throws -> CSVRows {
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

- **Note:** `InterfaceResponse` does not itself refine `Sendable`; `Interface.Response` requires
  `InterfaceResponse & Sendable`. Swift forbids a conditional conformance from depending on a
  marker protocol, so refining `Sendable` would make the `Array` and `Dictionary` conformances
  inexpressible. The guarantee is unchanged at the only place it matters.

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
