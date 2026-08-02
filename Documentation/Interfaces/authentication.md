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
    let authentication: AuthenticationScheme = .bearer
}
```

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
    .bearer: BearerAuthenticator(),          // Authorization: Bearer <credential>
    .url: QueryTokenAuthenticator()          // ?token=<credential>
]
```

`.none` short-circuits before any lookup: no authenticator is consulted and no credential is required. Registering an authenticator under `.none` has no effect and logs a diagnostic.

## Changing Placement

A server using `?access_token=` instead of `?token=` is configuration, not a builder fork:

```swift
let configuration = ServerConfiguration(
    url: url,
    authenticators: [
        .bearer: BearerAuthenticator(),
        .url: QueryTokenAuthenticator(name: "access_token")
    ]
)
```

Basic auth over a pre-encoded credential:

```swift
authenticators: [.bearer: BearerAuthenticator(headerScheme: "Basic")]
```

## Writing an Authenticator

```swift
struct APIKeyAuthenticator: Authenticator {
    let headerName: String

    func apply(_ credential: String, to components: inout URLComponents) throws(RequestError) {}

    func apply(_ credential: String, to request: inout URLRequest) throws(RequestError) {
        request.setValue(credential, forHTTPHeaderField: headerName)
    }
}
```

Both `apply` methods are required. A credential lands either in the URL, before it is formed, or on the request, after it is fully built, and the pipeline never holds a live `URLComponents` and `URLRequest` at the same time. Implement the one your scheme uses and leave the other empty; neither has a default so that an author reads both signatures and picks deliberately.

The request-side variant runs after the method, headers, and body are applied, so a scheme that signs the request can see everything it signs:

```swift
struct SigningAuthenticator: Authenticator {
    func apply(_ credential: String, to components: inout URLComponents) throws(RequestError) {}

    func apply(_ credential: String, to request: inout URLRequest) throws(RequestError) {
        let signature = sign(request.httpBody ?? Data(), with: credential)
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
    }
}
```

### Collision Handling

An authenticator owns what happens when the caller already wrote its header or query name, because only it knows those names. The built-in authenticators follow the package's established precedence:

- **Headers: the caller wins.** `BearerAuthenticator` finds an existing `Authorization`, logs a diagnostic, and leaves it alone.
- **Query items: the authenticator wins.** `QueryTokenAuthenticator` strips matching items from the base URL and from the endpoint's own `queryItems`, logs a diagnostic for each, then appends the credential.

The asymmetry is deliberate. A stale `?token=` baked into a base URL must not beat the live credential, while a caller who explicitly writes an `Authorization` header is overriding on purpose.

### Redaction

An authenticator that writes to the URL declares the names it uses:

```swift
var redactedQueryItemNames: Set<String> { ["access_token"] }
```

`ServerConfiguration` unions these across its registered authenticators into `redactedQueryItemNames`, and `HTTPResponseSnapshot` strips them from the URL it captures, so a credential carried in a URL does not survive into an error a consumer logs or attaches to a bug report. The names originate from the authenticators that write them, so redaction cannot drift out of step with the actual parameter name.

Defaults to empty, which is correct for any authenticator that does not touch the URL.

Header redaction is separate and static: `ResponseError`'s `description` and `debugDescription` always exclude `Set-Cookie`, `Authorization`, and `Proxy-Authorization`.

## Failure Modes

| Situation | Result |
|---|---|
| `.none` | No lookup, no credential required |
| Scheme with no registered authenticator | `RequestError.invalidRequest(description:)` naming the scheme |
| Registered scheme, `nil` credential | `RequestError.authentication` |

An unregistered scheme is a client misconfiguration rather than something a caller branches on, which is why it reuses `invalidRequest` rather than adding a case.

## Retry and Refresh

`APIClient` refreshes and retries a request whose `isAuthenticated` is `true` when `ServerConfiguration.challengePolicy` recognizes the failure as a challenge. No status code is hardcoded in the client.

### Credentials the Package Does Not Model

A request whose credential arrives through a cookie jar, a signing `Transport`, or a proxy has no scheme to declare. It declares `.none` and opts back in:

```swift
struct Parameters: RequestParameters {
    // ...
    let authentication: AuthenticationScheme = .none
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
