# Response Handling

Interfaces map HTTP status codes to outcomes (decode success, throw a predefined error, or decode an error body). The `handle(_:)` method applies this mapping and decodes the response.

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

When `handle(_:)` encounters `.noContent`, the default handler treats it as a success
with an empty body. This succeeds for `Data`, `String`, or `EmptyResponse` responses.

```swift
struct DeleteUser: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .delete
        let path = "/users/123"
        let queryItems: [String: String?]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody? = nil
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

Interfaces can override response handling logic by providing a custom `responseHandler`.
This allows per-interface decoding rules while keeping a shared default path.

```swift
public struct GetLibraryItemCover: Interface {
    public static var responseHandler: ResponseHandler.Type {
        CoverResponseHandler.self
    }
}

public enum CoverResponseHandler: ResponseHandler {
    public static func handle<T: Interface>(
        _ response: (data: Data, response: URLResponse),
        for interface: T.Type
    ) throws -> T.Response {
        let snapshot = HTTPResponseSnapshot(response: response.response)
        guard let statusCode = snapshot.statusCode else {
            throw ResponseError.unknownResponse(response.data, snapshot)
        }

        if statusCode == 204 {
            guard let empty = Data() as? T.Response else {
                throw ResponseError.decoding(
                    response.data,
                    snapshot,
                    .custom(message: "Expected Data response type for 204")
                )
            }
            return empty
        }

        return try DefaultResponseHandler.handle(response, for: interface)
    }
}
```

### Matching Priority

- Exact status codes match first.
- Range matches are evaluated in the order they are defined.
- Duplicate exact codes keep the first declaration. Later duplicates are ignored.
- In DEBUG builds, duplicate exact codes emit a warning.

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
        .code(401, .error(APIError.sessionExpired)) // ignored, DEBUG warning
    ]
}
```

### decodeError Behavior

`.decodeError` attempts to decode the response body into a typed `Error`. The decoded error is stored in `ResponseError.decoded`, and `ResponseError.decodeError(as:)` will return it without re-decoding when the types match.

When decoding fails (empty body, non-JSON response, malformed JSON), the error is surfaced as:

- `ResponseError.decoding(_, _, .custom(message: ...))`

The raw response data is always preserved, so you can still inspect `responseBodyString`.

## Decoding Rules

`DefaultResponseHandler.decode(_:as:)` supports:
- `String` responses (UTF-8)
- `Data` responses (raw bytes)
- `Decodable` responses (via `JSONDecoder`)

## Response Errors

`ResponseError` captures failures with the raw response data and response metadata:
- `.unknownResponse`
- `.unknownResponseCase`
- `.decoding`
- `.generic`
- `.decoded`

`InterfaceDecodingError` indicates decoding specifics:
- `.missingString`
- `.missingData`
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
}
```
