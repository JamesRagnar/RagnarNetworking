# Error Handling

## Error Origin

| Origin | Error type | Thrown by |
|---|---|---|
| Request construction | `RequestError` | `InterfaceConstructor.buildRequest` (via `dataTask`) |
| Transport | `URLError` (unwrapped) | `DataTaskProvider.data(for:)` / `dataTask(_:_:_:)` |
| Response handling | `ResponseError` | `Interface.handle(_:)` (via `dataTask`) |
| `APIClient` lifecycle | `APIClientError` | `APIClient.send`, `APIClient.invalidate` |

`URLSession`'s default `DataTaskProvider` conformance calls `URLSession.data(for:)` directly. When that call throws - offline, timeout, DNS failure, cancellation - the raw `URLError` propagates through `dataTask` unchanged. It is not wrapped in `RequestError` or `ResponseError`. A custom `DataTaskProvider` conformance may throw any `Error` from `data(for:)`; that error propagates the same way.

## RequestError Cases

- `.configuration` - the server configuration could not be parsed or is malformed.
- `.authentication` - the request requires authentication but no token was provided.
- `.componentsURL` - the URL components could not be assembled into a valid URL.
- `.encoding(underlying: ErrorSnapshot)` - the request body could not be encoded. `ErrorSnapshot` carries the failing error's type name and description as strings; the original `Error` value and its type are not preserved.
- `.invalidRequest(description: String)` - the request could not be constructed due to invalid parameters (for example, a `Content-Type` header that does not match the encoded body's media type).

## ResponseError Cases

- `.unknownResponse(Data, HTTPResponseSnapshot)` - the response could not be cast to `HTTPURLResponse`.
- `.unknownResponseCase(Data, HTTPResponseSnapshot)` - the HTTP status code has no matching entry in the Interface's `responseCases`.
- `.decoding(Data, HTTPResponseSnapshot, InterfaceDecodingError)` - the response body could not be decoded as the Interface's `Response` type.
- `.generic(Data, HTTPResponseSnapshot, any Error & Sendable)` - the predefined error configured via `.error(_:)` for the matched status code.
- `.decoded(Data, HTTPResponseSnapshot, any Error & Sendable)` - a structured error body decoded via `.decodeError(_:)` for the matched status code.

Every case carries the raw response `Data` and an `HTTPResponseSnapshot`. `ResponseError.statusCode`, `.responseBodyString`, `.headers`, `.header(_:)`, `.isRetryable`, and `.decodeError(as:)` read these associated values without requiring a `switch`.

`ResponseError`'s `description` and `debugDescription` redact `Set-Cookie`, `Authorization`, and `Proxy-Authorization` header values. `HTTPResponseSnapshot.headers`, read directly, is not redacted.

## InterfaceDecodingError Cases

Only reachable inside `ResponseError.decoding`:

- `.missingString` - the `Response` type expected a UTF-8 string but decoding failed.
- `.missingData` - the `Response` type expected raw `Data` but the cast failed.
- `.jsonDecoder(DecodingDiagnostics)` - `JSONDecoder` threw a `DecodingError`. `DecodingDiagnostics` carries a `Kind` (`.keyNotFound`, `.typeMismatch`, `.valueNotFound`, `.dataCorrupted`, `.other`), a `codingPath`, a `debugDescription`, and an optional `underlyingDescription` as strings - the original `DecodingError` is not preserved.
- `.custom(message: String)` - a custom `responseHandler`'s decode closure threw an error other than a caught `DecodingError`.

## APIClientError Cases

- `.invalidated` - the client has been permanently invalidated via `invalidate()`.

## Distinguishability

Programmatically distinguishable without inspecting string content:
- The four top-level error types (`RequestError`, `URLError`, `ResponseError`, `APIClientError`) via `catch` pattern matching on type.
- `ResponseError`'s five cases, `RequestError`'s five cases, `InterfaceDecodingError`'s four cases, and `DecodingDiagnostics.Kind`'s five cases, via `switch`/`if case`.
- `ResponseError.statusCode`, for any case, via the `statusCode` property.

Not programmatically distinguishable beyond a type name and description string:
- The underlying error boxed in `RequestError.encoding`'s `ErrorSnapshot`.
- The underlying `DecodingError` boxed in `InterfaceDecodingError.jsonDecoder`'s `DecodingDiagnostics`.
- Any error passed to `.error(_:)` and surfaced via `ResponseError.generic` is preserved as `any Error & Sendable` and can be cast back to its concrete type with `as?`; `ResponseError.decoded`'s value is likewise `any Error & Sendable` and can be cast, or retrieved without re-decoding via `decodeError(as:)` when the requested type matches the type it was originally decoded as.
