# Interfaces

This directory documents the Interface modeling layer: how requests are defined, constructed, and decoded.

## Overview

An `Interface` pairs a request with response handling. Most usage follows this flow:
1. Define `Interface` and nested `Request`.
2. Execute via `APIClient` or directly via `RequestPipeline`.

## Example

```swift
struct User: Codable, InterfaceResponse {
    let id: Int
    let name: String
}

struct GetUserInterface: Interface {
    struct Request: InterfaceRequest {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer

        init(userId: Int) {
            self.path = "/users/\(userId)"
        }
    }

    typealias Response = User

    static let responses = ResponseContract<Response>(
        success: .exact(200),
        failures: [.code(404, .error(APIError.userNotFound))]
    )
}

let user = try await client.send(
    GetUserInterface.self,
    .init(userId: 123)
)
```

`client` comes from:

```swift
let client = APIClient(
    configuration: ServerConfiguration(
        url: URL(string: "https://api.example.com")!
    ),
    credentialSource: .refreshing(
        read: { try await keychain.accessToken() },
        refresh: { try await authService.refresh() }
    )
)
```

To send without an `APIClient` managing credentials, use `RequestPipeline` directly with a
`RequestContext` carrying the token for that request:

```swift
let pipeline = RequestPipeline()
let context = RequestContext(configuration: configuration, credential: token)
let user = try await pipeline.send(GetUserInterface.self, .init(userId: 123), context: context)
```

## Response Contract Notes

- Every `ResponseContract<Response>` requires at least one successful status matcher.
- Successful matches always build the Interface's declared `Response`.
- Failure cases cannot select successful decoding.
- Use `.exact` or `.range` for successful status matchers.
- Use `.code`, `.range`, or category helpers for failure cases.
- Matching resolution is deterministic:
  - Exact code matches are checked first.
  - Then success ranges are checked in declaration order.
  - Then failure ranges are checked in declaration order.
  - Duplicate exact codes keep the first declaration.
  - Duplicate exact codes emit a developer diagnostic through `Logger`, in every build configuration.
- `.decodeError(MyError.self)` decodes structured error bodies and throws `ResponseError.decoded`.
- A no-body success (204/205/304) builds `Response` against zero bytes. `EmptyResponse` is the usual `Response` type for that case; `Data` and `String` also build themselves from an empty body.
- Set `ServerConfiguration.responseHandler` for a concern that spans the whole API.

Example:

```swift
static let responses = ResponseContract<Response>(
    success: .success,
    failures: [
        .code(202, .error(APIError.unexpectedAccepted)), // exact overrides success range
        .code(202, .error(APIError.duplicate)) // ignored, logs a developer diagnostic
    ]
)
```

## Response Type Expectations

An `Interface.Response` conforms to `InterfaceResponse`, which owns how the type is built from a response. A `Decodable` type conforms without implementing anything:

```swift
struct User: Codable, InterfaceResponse {
    let id: Int
    let name: String
}
```

Built-in conformances:

- `Decodable`: decoded from the response body using the configured `ResponseDecoder` (defaults to a plain `JSONDecoder`). See [Response Handling](response_handling.md#response-decoder).
- `String`: expects UTF-8 response bodies.
- `Data`: returns raw bytes (for downloads/streams or no-body fallbacks).
- `Int`, `Int64`, `Double`, `Bool`: top-level JSON scalars.
- `Optional`: a top-level `null` decodes as `nil`.
- `Array`: top-level JSON array.
- `Dictionary`: behavior depends on the key type, see [Dictionary Key Types](response_handling.md#dictionary-key-types).
- `EmptyResponse`: represents a successful response with no body, and succeeds for any bytes.

Conform directly for a response that is not JSON, or one whose value depends on a header. See [Response Handling](response_handling.md#non-json-responses) and [Responses That Depend on Headers](response_handling.md#responses-that-depend-on-headers).

## Status Code Mapping Examples

- `200 OK`: `success: .exact(200)` builds the response body as `Response`.
- `201 Created`: `success: .exact(201)` builds the created resource.
- `202 Accepted`: `success: .exact(202)` with `Response = EmptyResponse` treats the response as success with no body; a custom `Response` type maps status info if the server returns it instead.
- `204 No Content`: `success: .exact(204)` with `Response = EmptyResponse` treats the response as success with no body.
- `205 Reset Content`: `success: .exact(205)` with `Response = EmptyResponse` treats the response as success with no body.
- `206 Partial Content`: `success: .exact(206)` with `Response = Data` returns the raw response bytes.
- `304 Not Modified`: `success: .exact(304)` with `Response = EmptyResponse` treats the response as success with no body, for Interfaces that send conditional requests.

## Interface Genericity

`Interface` has two associated types (`Request` and `Response`), and `APIClient.send`/`RequestPipeline.send` return `T.Response`. `any Interface` cannot be used as a dispatch type - a heterogeneous collection of Interfaces (for example `[any Interface]`, for a request queue) does not type-check, because the associated types make the protocol non-existential for that purpose.

To hold heterogeneous Interfaces, erase the call site behind a closure instead of the Interface type itself:

```swift
struct QueuedRequest {
    let send: (APIClient) async throws -> Void
}

let queued = QueuedRequest { client in
    _ = try await client.send(GetUserInterface.self, .init(userId: 123))
}
```

## Guides

- [Interface Request](interface_request.md)
- [Response Handling](response_handling.md)
- [Request Builder](request_builder.md)
- [Authentication](authentication.md)
