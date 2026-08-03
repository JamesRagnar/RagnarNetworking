# Error Handling

## Error Origin

| Origin | Error type | Thrown by |
|---|---|---|
| Request construction | `RequestError` | `RequestBuilder.buildRequest` (via `RequestPipeline.send`) |
| Transport | `TransportError` | `Transport.data(for:)`, classified by `RequestPipeline.send` |
| Response handling | `ResponseError` | `ResponseHandler.handle(_:for:context:)` (via `RequestPipeline.send`) |
| `APIClient` lifecycle | `APIClientError` | `APIClient.send`, `APIClient.invalidate` |

`Transport.data(for:)` is untyped `throws`, so `RequestPipeline.send` classifies whatever it throws into a `TransportError` rather than letting a raw `URLError` escape. A custom `Transport` conformance may throw any `Error`; it arrives as `TransportError.other` with the value unchanged.

Cancellation is the exception, and is not a `TransportError`. It stays `CancellationError` whether the package raised it or `URLSession` reported `URLError.cancelled`, so `catch is CancellationError` is the single check for it.

## TransportError Cases

- `.offline(URLError)` - `notConnectedToInternet`, `networkConnectionLost`, `dataNotAllowed`, or `internationalRoamingOff`.
- `.timedOut(URLError)` - `timedOut`.
- `.url(URLError)` - any other `URLError`, such as `cannotFindHost` or `secureConnectionFailed`.
- `.other(any Error)` - a custom `Transport`'s own error type, carried unchanged.

`isOffline` and `isTimeout` cover the two branches most UIs distinguish, so a caller does not need to know to match on `URLError.Code`. `urlError` returns the underlying `URLError` for the first three cases and `nil` for `.other`.

```swift
do {
    let user = try await client.send(GetUser.self, .init(id: 1))
    show(user)
} catch let failure as TransportError {
    show(failure.isOffline ? "You are offline." : failure.errorDescription)
} catch let error as ResponseError {
    show(error.errorDescription)
} catch is CancellationError {
    // The caller's own Task was cancelled.
} catch APIClientError.invalidated {
    replaceClient()
} catch {
    report(error)
}
```

## RequestError Cases

- `.configuration` - the server configuration could not be parsed or is malformed.
- `.componentsURL` - the URL components could not be assembled into a valid URL.
- `.encoding(underlying: ErrorSnapshot)` - the request body could not be encoded. `ErrorSnapshot` carries the failing error's type name and description as strings; the original `Error` value and its type are not preserved.
- `.invalidRequest(description: String)` - the request could not be constructed due to invalid parameters (for example, a `Content-Type` header that does not match the encoded body's media type).
- `.unregisteredScheme(AuthenticationScheme)` - the request declared a scheme with no authenticator registered for it on the configuration.
- `.missingCredential(AuthenticationScheme)` - the request declared a scheme with a registered authenticator, but no credential was available.
- `.credentialCollision(scheme:name:)` - the credential would have overwritten a header field or query item the request already carried.
- `.undeclaredQueryItemName(scheme:name:)` - the authenticator returned a query item outside its own `redactedQueryItemNames`, which would leak the credential into a captured `HTTPResponseSnapshot`.
- `.authenticatorAppliedNothing(AuthenticationScheme)` - the registered authenticator returned neither a header field nor a query item, so the request would have been sent unauthenticated.

## ResponseError Cases

- `.unknownResponse(ResponseBody, HTTPResponseSnapshot)` - the response could not be cast to `HTTPURLResponse`.
- `.unknownResponseCase(ResponseBody, HTTPResponseSnapshot)` - the HTTP status code has no matching entry in the Interface's `responses` contract.
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
- The top-level error types (`RequestError`, `TransportError`, `ResponseError`, `APIClientError`, `CancellationError`) via `catch` pattern matching on type.
- `ResponseError`'s five cases, `RequestError`'s nine cases, `TransportError`'s four cases, `InterfaceDecodingError`'s three cases, and `DecodingDiagnostics.Kind`'s five cases, via `switch`/`if case`.
- Offline versus timeout, via `TransportError.isOffline` and `.isTimeout`.
- A custom `Transport`'s own error type, via `as?` on `TransportError.other`'s payload.
- `ResponseError.statusCode`, for any case, via the `statusCode` property.

Not programmatically distinguishable beyond a type name and description string:
- The underlying error boxed in `RequestError.encoding`'s `ErrorSnapshot`.
- The underlying `DecodingError` boxed in `InterfaceDecodingError.jsonDecoder`'s `DecodingDiagnostics`.
- Any error passed to `.error(_:)` and surfaced via `ResponseError.generic` is preserved as `any Error & Sendable` and can be cast back to its concrete type with `as?`; `ResponseError.decoded`'s value is likewise `any Error & Sendable` and can be cast, or retrieved without re-decoding via `decodeError(as:)` when the requested type matches the type it was originally decoded as.
