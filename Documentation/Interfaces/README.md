# Interfaces

This directory documents the Interface modeling layer: how requests are defined, constructed, and decoded.

## Overview

An `Interface` pairs request parameters with response handling. Most usage follows this flow:
1. Define `Interface` and nested `Parameters`.
2. Execute via `APIClient` or directly via `RequestPipeline`.

## Example

```swift
struct GetUserInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationType = .bearer

        init(userId: Int) {
            self.path = "/users/\(userId)"
        }
    }

    typealias Response = User

    static var responseCases: ResponseMap {
        [
            .code(200, .decode),
            .code(404, .error(APIError.userNotFound))
        ]
    }
}

let user = try await URLSession.shared.dataTask(
    GetUserInterface.self,
    .init(userId: 123),
    config
)
```

`config` comes from:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: token
)
```

## Response Cases Notes

- Use `.code` for exact status codes.
- Use `.range` or `.success`/`.clientError`/`.serverError` for ranges.
- Matching resolution is deterministic:
  - Exact code matches are checked first.
  - Then ranges are checked in declaration order.
  - Duplicate exact codes keep the first declaration.
  - In DEBUG builds, duplicate exact codes emit a developer diagnostic.
- `.decodeError(MyError.self)` decodes structured error bodies and throws `ResponseError.decoded`.
- Use `.noContent` for no-body success (204/205/304). `EmptyResponse` is the `Response` type for that case.
- Override `responseHandler` when an Interface needs custom response handling logic.

Example:

```swift
static var responseCases: ResponseMap {
    [
        .success(.error(APIError.fallbackSuccess)),
        .code(200, .decode), // exact overrides success range
        .code(200, .error(APIError.duplicate)) // ignored, DEBUG developer diagnostic
    ]
}
```

## Response Type Expectations

- `String`: expects UTF-8 response bodies.
- `Data`: returns raw bytes (for downloads/streams or no-body fallbacks).
- `Decodable`: decoded from the response body using the configured `ResponseDecoder` (defaults to a plain `JSONDecoder`). See [Response Handling](response_handling.md#response-decoder).
- `EmptyResponse`: represents a successful response with no body.
- `.noContent`: use when the server returns no body (204/205/304).

## Status Code Mapping Examples

- `200 OK`: `.code(200, .decode)` decodes the response body as `Response`.
- `201 Created`: `.code(201, .decode)` decodes the response body when the server returns the created resource.
- `202 Accepted`: `.code(202, .noContent)` treats the response as success with no body; a custom `Response` type maps status info if the server returns it instead.
- `204 No Content`: `.code(204, .noContent)` treats the response as success with no body.
- `205 Reset Content`: `.code(205, .noContent)` treats the response as success with no body.
- `206 Partial Content`: `.code(206, .decode)` with `Response = Data` decodes the raw response bytes.
- `304 Not Modified`: `.code(304, .noContent)` treats the response as success with no body, for Interfaces that send conditional requests.

## Interface Genericity

`Interface` has two associated types (`Parameters` and `Response`), and `APIClient.send`/`RequestPipeline.send` return `T.Response`. `any Interface` cannot be used as a dispatch type - a heterogeneous collection of Interfaces (for example `[any Interface]`, for a request queue) does not type-check, because the associated types make the protocol non-existential for that purpose.

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

- [Request Parameters](request_parameters.md)
- [Response Handling](response_handling.md)
- [Request Builder](request_builder.md)
