# Response Handling

Interfaces map HTTP status codes to success or failure. The `handle(_:)` method applies this mapping and decodes the response.

## Response Cases

```swift
static var responseCases: ResponseCases {
    [
        200: .success(User.self),
        404: .failure(APIError.userNotFound)
    ]
}
```

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
