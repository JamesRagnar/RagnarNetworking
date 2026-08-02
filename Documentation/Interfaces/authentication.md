# Authentication Guide

Authentication is split across two owners:

| Axis | Owner | Type |
|---|---|---|
| Which scheme this endpoint uses | `RequestParameters` | `AuthenticationScheme` |
| How that scheme is applied | `ServerConfiguration` | `[AuthenticationScheme: any Authenticator]` |
| Whether a credential is carried at all | `RequestParameters` | `isAuthenticated` |
| What counts as a stale credential | `ServerConfiguration` | `AuthenticationChallengePolicy` |
| What the credential is | `RequestContext` | `credential` |

Placement is a property of the server. The choice of scheme is a property of the endpoint, because placement genuinely varies per endpoint on a single server: a URL handed to an image loader or `AVPlayer` cannot carry a header.

## Declaring a Scheme

```swift
struct Parameters: RequestParameters {
    let method: RequestMethod = .get
    let path: String = "/me"
    let queryItems: [URLQueryItem]? = nil
    let headers: [String: String]? = nil
    let body: EmptyBody = .init()
    let authentication: AuthenticationScheme? = .bearer
}
```

A request that carries no credential declares `nil`. There is no scheme meaning "no scheme", so there is nothing to register an authenticator against by mistake.

`AuthenticationScheme` is an open value, not a closed enum:

```swift
extension AuthenticationScheme {
    static let apiKey = AuthenticationScheme("apiKey")
}
```

Two schemes with the same name are the same scheme, so a project defining its own should pick a name unlikely to collide with another module's.

## The Default Registry

Out of the box, `ServerConfiguration` registers:

```swift
[
    .bearer: .bearer,   // Authorization: Bearer <credential>
    .url: .token        // ?token=<credential>
]
```

A request declaring no scheme never consults this.

## Changing Placement

A server using `?access_token=` instead of `?token=` is configuration, not a builder fork:

```swift
let configuration = ServerConfiguration(
    url: url,
    authenticators: [
        .bearer: .bearer,
        .url: .queryItem("access_token")
    ]
)
```

Basic auth over a pre-encoded credential:

```swift
authenticators: [.bearer: .basic]                 // Authorization: Basic <credential>
authenticators: [.apiKey: .header("X-API-Key")]  // X-API-Key: <credential>
```

## Writing an Authenticator

An authenticator returns the header fields and query items that carry a credential. It does not mutate the request; `URLRequestBuilder` applies what it returns.

```swift
struct APIKeyAuthenticator: Authenticator {
    let headerName: String

    func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String] {
        [headerName: credential]
    }
}
```

Both requirements have empty defaults, so implement only the one your scheme uses.

### Why returning values rather than mutating

The builder sees the names being written before they land, which is where three guarantees come from that an authenticator cannot be trusted to reproduce individually:

- **A collision fails the request.** If a returned name is already present, construction throws `RequestError.credentialCollision`.
- **Redaction cannot drift.** Every name returned from `queryItems(for:on:)` must be listed in `redactedQueryItemNames`, or construction throws `RequestError.undeclaredQueryItemName`.
- **A silent no-op fails the request.** An authenticator contributing neither a header nor a query item throws `RequestError.authenticatorAppliedNothing`, so a conformance that implements the wrong half cannot produce an unauthenticated request that looks fine.

The cost is that an authenticator cannot reach other parts of the request. In HTTP a credential is a header or a query item: cookies are the `Cookie` header, a password grant is a request *body* rather than an authenticator's business, and client certificates are `URLSession` configuration. The restriction is what buys the guarantees.

### Signing

Both requirements receive what has been built so far, so a scheme that signs can read it.

`headers(for:on:)` runs after the method, headers, and body are applied:

```swift
struct BodySigningAuthenticator: Authenticator {
    func headers(
        for credential: String,
        on request: URLRequest
    ) throws(RequestError) -> [String: String] {
        ["X-Signature": sign(request.httpBody ?? Data(), with: credential)]
    }
}
```

`queryItems(for:on:)` runs after the path and the endpoint's own query items are applied, for a presigned URL:

```swift
struct URLSigningAuthenticator: Authenticator {
    var redactedQueryItemNames: Set<String> { ["signature"] }

    func queryItems(
        for credential: String,
        on components: URLComponents
    ) throws(RequestError) -> [URLQueryItem] {
        [URLQueryItem(name: "signature", value: sign(components, with: credential))]
    }
}
```

### Collisions

Two sources claiming one slot is a contradiction in the configuration, not a preference to resolve. Both of these fail request construction:

- A caller-supplied `Authorization` header, or one in `defaultHeaders`, alongside a request declaring a header scheme.
- A base URL with the credential's query item already baked in.

There is no precedence rule to learn, and no per-channel asymmetry, because nothing silently wins. A caller who wants to write an `Authorization` header by hand on one endpoint declares no scheme for it.

### Redaction

An authenticator that writes to the URL declares the names it uses:

```swift
var redactedQueryItemNames: Set<String> { ["access_token"] }
```

`ServerConfiguration` unions these across its registered authenticators into `redactedQueryItemNames`, and `HTTPResponseSnapshot` strips them from the URL it captures, so a credential carried in a URL does not survive into an error a consumer logs or attaches to a bug report.

Returning a query item whose name is not declared here fails request construction, so the two cannot fall out of step.

Header redaction is separate and static: `ResponseError`'s `description` and `debugDescription` always exclude `Set-Cookie`, `Authorization`, and `Proxy-Authorization`.

## Failure Modes

| Situation | Result |
|---|---|
| No scheme declared | No lookup, no credential required |
| Scheme with no registered authenticator | `RequestError.unregisteredScheme(_:)` |
| Registered scheme, `nil` credential | `RequestError.missingCredential(_:)` |
| Credential would overwrite an existing name | `RequestError.credentialCollision(scheme:name:)` |
| Query item name not declared for redaction | `RequestError.undeclaredQueryItemName(scheme:name:)` |
| Authenticator contributed nothing | `RequestError.authenticatorAppliedNothing(_:)` |

Every one carries the scheme that failed, so a diagnostic never has to be reconstructed from a string.

## Retry and Refresh

`APIClient` refreshes and retries a request whose `isAuthenticated` is `true` when `ServerConfiguration.challengePolicy` recognizes the failure as a challenge. No status code is hardcoded in the client.

### Credentials the Package Does Not Model

A request whose credential arrives through a cookie jar, a signing `Transport`, or a proxy has no scheme to declare. It declares `nil` and opts back in:

```swift
struct Parameters: RequestParameters {
    // ...
    let authentication: AuthenticationScheme? = nil
    var isAuthenticated: Bool { true }
}
```

Without the override, such a request silently gets no challenge retry and no coalesced refresh, and nothing warns about it.

### The Challenge Policy

```swift
public struct AuthenticationChallengePolicy: Sendable {
    public let isChallenge: @Sendable (ResponseError, ResponseMap) -> Bool

    public static let unmodelled401: AuthenticationChallengePolicy  // the default
    public static let any401: AuthenticationChallengePolicy
}
```

A server that signals staleness some other way needs configuration rather than a fork:

```swift
let configuration = ServerConfiguration(
    url: url,
    challengePolicy: AuthenticationChallengePolicy { error, _ in
        error.statusCode == 419 || error.header("WWW-Authenticate") != nil
    }
)
```

The policy receives the Interface's `responseCases` alongside the error so it can ask what the endpoint declared, rather than inferring it from which `ResponseError` case was thrown. Inferring would tie the policy to `DefaultResponseHandler`'s error mapping, which a custom `ResponseHandler` is free to change.

### `.unmodelled401`

The default refreshes on 401 **unless the Interface declared an exact `.code(401, ...)` case**.

An endpoint that deliberately models 401 - a login route returning typed validation errors, say - surfaces its own error to the caller instead of triggering a refresh it did not ask for. That matters beyond a wasted round trip: a refresh that throws replaces the modelled error at the catch site, so an endpoint's ordinary 401 could otherwise sign a user out.

A *range* match does not count as modelling 401:

```swift
static let responseCases: ResponseMap = [
    .code(200, .decode),
    .clientError(.decodeError(APIErrorBody.self))   // still refreshes on 401
]

static let responseCases: ResponseMap = [
    .code(200, .decode),
    .code(401, .decodeError(LoginError.self))       // does not refresh
]
```

`.clientError` is a catch-all for everything the endpoint did not think about, 401 included. Only `.code(401, ...)` is a statement about 401 specifically.

If an endpoint both models 401 exactly and relies on refresh firing, `.any401` restores the older behavior across the configuration:

```swift
ServerConfiguration(url: url, challengePolicy: .any401)
```

## Not Yet Supported

- **Multiple credentials per client.** `RequestContext.credential` is a single `String?`. A refresh endpoint that itself uses basic auth would want a per-scheme lookup; that overload will be added when something needs it.
- **Socket authentication.** `SocketIOClient` has no credential handling. `Authenticator` is designed against `URLComponents` and `URLRequest` so it should fit a handshake URL, but that has not been verified.
