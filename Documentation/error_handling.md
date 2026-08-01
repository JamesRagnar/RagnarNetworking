# Error Handling

## Error Origin

| Origin | Error type | Thrown by |
|---|---|---|
| Request construction | `RequestError` | `RequestBuilder.buildRequest` (via `RequestPipeline.send`) |
| Transport | `URLError` (unwrapped) | `Transport.data(for:)` (via `RequestPipeline.send`) |
| Response handling | `ResponseError` | `Interface.handle(_:responseDecoder:)` (via `RequestPipeline.send`) |
| `APIClient` lifecycle | `APIClientError` | `APIClient.send`, `APIClient.invalidate` |

`URLSession`'s default `Transport` conformance calls `URLSession.data(for:)` directly. When that call throws - offline, timeout, DNS failure, cancellation - the raw `URLError` propagates through `RequestPipeline.send` unchanged. It is not wrapped in `RequestError` or `ResponseError`. A custom `Transport` conformance may throw any `Error` from `data(for:)`; that error propagates the same way.

## RequestError Cases

- `.configuration` - the server configuration could not be parsed or is malformed.
- `.authentication` - the request requires authentication but no token was provided.
- `.componentsURL` - the URL components could not be assembled into a valid URL.
- `.encoding(underlying: ErrorSnapshot)` - the request body could not be encoded. `ErrorSnapshot` carries the failing error's type name and description as strings; the original `Error` value and its type are not preserved.
- `.invalidRequest(description: String)` - the request could not be constructed due to invalid parameters (for example, a `Content-Type` header that does not match the encoded body's media type).

## ResponseError Cases

- `.unknownResponse(ResponseBody, HTTPResponseSnapshot)` - the response could not be cast to `HTTPURLResponse`.
- `.unknownResponseCase(ResponseBody, HTTPResponseSnapshot)` - the HTTP status code has no matching entry in the Interface's `responseCases`.
- `.decoding(ResponseBody, HTTPResponseSnapshot, InterfaceDecodingError)` - the response body could not be decoded as the Interface's `Response` type.
- `.generic(ResponseBody, HTTPResponseSnapshot, any Error & Sendable)` - the predefined error configured via `.error(_:)` for the matched status code.
- `.decoded(ResponseBody, HTTPResponseSnapshot, any Error & Sendable)` - a structured error body decoded via `.decodeError(_:)` for the matched status code.

Every case carries a `ResponseBody` and an `HTTPResponseSnapshot`. `ResponseBody` pairs the raw response bytes with the `ResponseDecoder` the response was handled with, so `.decodeError(as:)` decodes an error body with the client's own rules and takes no decoder argument. `ResponseError.statusCode`, `.body`, `.responseData`, `.responseBodyString`, `.headers`, `.header(_:)`, `.isRetryable`, and `.decodeError(as:)` read these associated values without requiring a `switch`.

`ResponseError`'s `description` and `debugDescription` redact `Set-Cookie`, `Authorization`, and `Proxy-Authorization` header values. `HTTPResponseSnapshot.headers`, read directly, is not redacted.

## InterfaceDecodingError Cases

Only reachable inside `ResponseError.decoding`:

- `.missingString` - a `String` response body was not valid UTF-8.
- `.jsonDecoder(DecodingDiagnostics)` - the configured `ResponseDecoder` threw a `DecodingError`. `DecodingDiagnostics` carries a `Kind` (`.keyNotFound`, `.typeMismatch`, `.valueNotFound`, `.dataCorrupted`, `.other`), a `codingPath`, a `debugDescription`, and an optional `underlyingDescription` as strings - the original `DecodingError` is not preserved.
- `.custom(message: String)` - an `InterfaceResponse` conformance, or a custom `responseHandler`'s decode closure, threw an error that was neither a `DecodingError` nor an `InterfaceDecodingError`.

## APIClientError Cases

- `.invalidated` - the client has been permanently invalidated via `invalidate()`.

## Distinguishability

Programmatically distinguishable without inspecting string content:
- The four top-level error types (`RequestError`, `URLError`, `ResponseError`, `APIClientError`) via `catch` pattern matching on type.
- `ResponseError`'s five cases, `RequestError`'s five cases, `InterfaceDecodingError`'s three cases, and `DecodingDiagnostics.Kind`'s five cases, via `switch`/`if case`.
- `ResponseError.statusCode`, for any case, via the `statusCode` property.

Not programmatically distinguishable beyond a type name and description string:
- The underlying error boxed in `RequestError.encoding`'s `ErrorSnapshot`.
- The underlying `DecodingError` boxed in `InterfaceDecodingError.jsonDecoder`'s `DecodingDiagnostics`.
- Any error passed to `.error(_:)` and surfaced via `ResponseError.generic` is preserved as `any Error & Sendable` and can be cast back to its concrete type with `as?`; `ResponseError.decoded`'s value is likewise `any Error & Sendable` and can be cast, or retrieved without re-decoding via `decodeError(as:)` when the requested type matches the type it was originally decoded as.
