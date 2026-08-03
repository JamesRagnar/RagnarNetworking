# Error Handling

## APIFailure

`APIClient.send` and `RequestPipeline.send` both declare `throws(APIFailure)`. The caught error is an `APIFailure`, so a caller switches on it exhaustively, with no `default` and no cast:

```swift
do {
    let user = try await client.send(GetUser.self, .init(id: 1))
    show(user)
} catch {
    switch error {
    case .transport(let failure):
        show(failure.isOffline ? "You are offline." : failure.errorDescription)

    case .response(let error):
        show(error.errorDescription)

    case .request(let error):
        assertionFailure("Endpoint is misconfigured: \(error)")

    case .credential(let error):
        signOut(because: error)

    case .cancelled:
        break

    case .invalidated:
        replaceClient()

    case .noCredentialSource:
        assertionFailure("This client was created without token and refresh closures.")
    }
}
```

The exhaustiveness lives in the `switch`, not in the `catch` clauses. Swift treats a `do` as exhaustive only when it ends in an unconditional `catch`, so matching a case in the catch pattern still needs a catch-all after it. That form is the right one when only one case is interesting:

```swift
do {
    let user = try await client.send(GetUser.self, .init(id: 1))
    show(user)
} catch .invalidated {
    replaceClient()
} catch {
    show(error.errorDescription)
}
```

| Case | Payload | Meaning |
|---|---|---|
| `.request` | `RequestError` | The request could not be built, or a credential could not be applied to it. |
| `.transport` | `TransportError` | The bytes could not be moved. |
| `.response` | `ResponseError` | A response arrived but could not be interpreted as the Interface's `Response`. |
| `.credential` | `any Error` | The client's `token` or `refresh` closure threw. Carries that error unchanged. |
| `.cancelled` | - | The call was cancelled. |
| `.invalidated` | - | The client was invalidated via `invalidate()`. Terminal. |
| `.noCredentialSource` | - | A challenge arrived on a client created without credential closures. |

`RequestPipeline.send` produces `.request`, `.transport`, `.response`, and `.cancelled`. `APIClient.send` adds the other three.

### `.request` versus `.credential`

The split is *obtain* versus *apply*.

`.credential` means the credential could not be obtained: the consumer's `token` or `refresh` closure threw. That error is carried unchanged, so a `KeychainError` can be caught back out with `as?`.

`.request` means the request could not be built, which includes applying a credential the client did obtain. All of `RequestError`'s authentication cases - `.missingCredential`, `.unregisteredScheme`, `.credentialCollision`, `.undeclaredQueryItemName`, `.authenticatorAppliedNothing` - are `.request`.

### Cancellation

`.cancelled` covers cancellation from either source: a `CancellationError` raised inside the package, and a `URLError.cancelled` raised by the transport when `URLSession` observes the task being cancelled. The same user action produces the same case regardless of which one won the race.

Cancelling a `send` that is waiting on a coalesced token refresh throws `.cancelled` promptly without cancelling that refresh, which other calls may still be waiting on. See [concurrency.md](concurrency.md).

When a call is cancelled by `invalidate()` rather than by the caller, it surfaces as `.invalidated`, not `.cancelled`.

## Error Origin

| Origin | Case | Thrown by |
|---|---|---|
| Request construction and credential application | `.request(RequestError)` | `URLRequest.init(requestParameters:context:)` |
| Transport | `.transport(TransportError)` | `Transport.data(for:)`, classified by `RequestPipeline.send` |
| Response handling | `.response(ResponseError)` | `Interface.handle(_:context:defaultHandler:)` |
| Credential resolution | `.credential(any Error)` | `APIClient`'s `token` and `refresh` closures |
| Client lifecycle | `.invalidated`, `.noCredentialSource` | `APIClient.send` |

## TransportError Cases

`Transport.data(for:)` is untyped `throws`, so `RequestPipeline` classifies whatever it throws:

- `.offline(URLError)` - `notConnectedToInternet`, `networkConnectionLost`, `dataNotAllowed`, or `internationalRoamingOff`.
- `.timedOut(URLError)` - `timedOut`.
- `.url(URLError)` - any other `URLError`, such as `cannotFindHost` or `secureConnectionFailed`.
- `.other(any Error)` - a custom `Transport`'s own error type, carried unchanged.

`isOffline` and `isTimeout` cover the two branches most UIs distinguish. `urlError` returns the underlying `URLError` for the first three cases and `nil` for `.other`.

`URLError.cancelled` is not classified here; it is lifted to `APIFailure.cancelled`.

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

## Distinguishability

Programmatically distinguishable without inspecting string content:

- `APIFailure`'s seven cases, exhaustively, with no `default`.
- `TransportError`'s four cases, plus `isOffline` and `isTimeout`.
- `RequestError`'s nine cases, `ResponseError`'s five cases, `InterfaceDecodingError`'s three cases, and `DecodingDiagnostics.Kind`'s five cases, via `switch`/`if case`.
- `ResponseError.statusCode`, for any case, via the `statusCode` property.
- The error a `token` or `refresh` closure threw, via `as?` on `.credential`'s payload.
- A custom `Transport`'s own error type, via `as?` on `TransportError.other`'s payload.

Not programmatically distinguishable beyond a type name and description string:

- The underlying error boxed in `RequestError.encoding`'s `ErrorSnapshot`.
- The underlying `DecodingError` boxed in `InterfaceDecodingError.jsonDecoder`'s `DecodingDiagnostics`.

Any error passed to `.error(_:)` and surfaced via `ResponseError.generic` is preserved as `any Error & Sendable` and can be cast back to its concrete type with `as?`; `ResponseError.decoded`'s value is likewise `any Error & Sendable` and can be cast, or retrieved without re-decoding via `decodeError(as:)` when the requested type matches the type it was originally decoded as.
