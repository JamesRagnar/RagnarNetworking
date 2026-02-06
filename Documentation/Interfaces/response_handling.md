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

When `handle(_:)` encounters `.noContent`, the default handler decodes an empty body.
This succeeds for `Data` or `String` responses. For custom no-content behavior, override
the Interface `responseHandler`.

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
            return Data() as! T.Response
        }

        return try DefaultResponseHandler.handle(response, for: interface)
    }
}
```

### Matching Priority

- Exact status codes match first.
- Range matches are evaluated in the order they are defined.

This means you can declare a fallback range and still override specific status codes later:

```swift
static var responseCases: ResponseMap {
    [
        .clientError(.error(APIError.genericClientError)),
        .code(401, .error(APIError.unauthorized))
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
