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

Use `handleOutcome(_:)` when you need to differentiate:

```swift
switch try InterfaceType.handleOutcome(response) {
case .decoded(let value):
    // handle decoded response
case .noContent:
    // handle no-body success
}
```

`handle(_:)` remains available for legacy call sites. If you map a status to `.noContent`,
`handle(_:)` will attempt to decode an empty body, which will only succeed for `Data` or `String`
responses.

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

- `ResponseError.decoding(_, _, .jsonDecoder(underlying))`

The raw response data is always preserved, so you can still inspect `responseBodyString`.

## Decoding Rules

`Interface.decode(response:)` supports:
- `String` responses (UTF-8)
- `Data` responses (raw bytes)
- `Decodable` responses (via `JSONDecoder`)

## Response Errors

`ResponseError` captures failures with the raw response data:
- `.unknownResponse`
- `.unknownResponseCase`
- `.decoding`
- `.generic`
- `.decoded`

`InterfaceDecodingError` indicates decoding specifics:
- `.missingString`
- `.missingData`
- `.jsonDecoder`

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
