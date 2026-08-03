# Authentication Guide

Authentication is split across request, server, and client scopes:

| Axis | Owner | Type |
|---|---|---|
| Which scheme this endpoint uses | `InterfaceRequest` | `AuthenticationScheme` |
| How that scheme is applied | `ServerConfiguration` | `[AuthenticationScheme: any Authenticator]` |
| Whether an endpoint allows challenge refresh | `InterfaceRequest` | `allowsRefreshOnChallenge` |
| What counts as a stale credential | `ServerConfiguration` | `AuthenticationChallengePolicy` |
| How the credential is read and whether it refreshes | `APIClient` | `CredentialSource` |
| What the credential is | `RequestContext` | `credential` |

Placement is a property of the server; the choice of scheme is a property of the endpoint. Placement varies per endpoint on a single server because a URL handed to an image loader or `AVPlayer` cannot carry a header.

## Credential Lifecycle

One `APIClient` coordinates one optional `CredentialSource`. Named construction makes its capability explicit:

```swift
let apiKey = CredentialSource.readOnly {
    configuration.apiKey
}

let accessToken = CredentialSource.refreshing(
    read: { try await keychain.accessToken() },
    refresh: { try await authenticationService.refresh() }
)
```

One source can serve multiple schemes because schemes describe placement, not credential identity. Bearer and URL authentication can therefore share one access-token refresh generation. Independent credentials use independent clients.

A read-only source resolves a credential once per authenticated request and never retries a challenged request. A refreshing source re-reads after refresh and retries once. A client with no source supports schemeless requests; a request declaring a registered scheme fails with `RequestError.missingCredential`.

## Declaring a Scheme

```swift
struct Request: InterfaceRequest {
    let method: RequestMethod = .get
    let path: String = "/me"
    let queryItems: [URLQueryItem]? = nil
    let headers: [String: String]? = nil
    let body: EmptyBody = .init()
    let authentication: AuthenticationScheme? = .bearer
}
```

A request carrying no credential declares `nil`.

`AuthenticationScheme` is an open value, not a closed enum:

```swift
extension AuthenticationScheme {
    static let apiKey = AuthenticationScheme("apiKey")
}
```

Two schemes with the same name are equal, so a project defining its own should pick a name unlikely to collide with another module's.

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

A server using `?access_token=` instead of `?token=`:

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

An authenticator returns the header fields and query items that carry a credential. `URLRequest.init(interfaceRequest:context:)` applies what it returns to the request the `RequestBuilder` has finished. See [Request Builder](request_builder.md).

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

Both requirements default to empty. Implement the one the scheme uses.

Returning values rather than mutating lets the package check names before they land. It rejects a name the request already carries, a query item outside `redactedQueryItemNames`, and an authenticator that returns nothing anywhere. A credential is therefore a header field or a query item and nothing else: a cookie is the `Cookie` header, a password grant is a `RequestBody`, and a client certificate is `URLSession` configuration.

### Signing

Both requirements receive the finished request, so either can sign what is actually sent.

`headers(for:on:)` runs last, with the method, headers, body, and final URL all in place:

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

`queryItems(for:on:)` runs first, receiving the built URL as components - base URL, path, and the endpoint's own query items all applied - for a presigned URL:

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

A credential that would overwrite a name the request already carries throws `RequestError.credentialCollision` rather than resolving by precedence. Two cases reach it:

- A caller-supplied `Authorization` header, or one in `defaultHeaders`, alongside a request declaring a header scheme.
- A base URL carrying the credential's query item.

To write a header by hand on one endpoint, declare no scheme for it.

### Redaction

An authenticator that writes to the URL declares the names it uses:

```swift
var redactedQueryItemNames: Set<String> { ["access_token"] }
```

`ServerConfiguration` unions these across its authenticators into `redactedQueryItemNames`, and `HTTPResponseSnapshot` strips them from the URL it captures, so a URL-carried credential does not reach a logged error. Returning a query item whose name is not declared here fails request construction.

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

Every case carries the scheme that failed.

## Retry and Refresh

`APIClient` refreshes and retries a request whose `allowsRefreshOnChallenge` is `true` when `ServerConfiguration.challengePolicy` recognizes the failure as a challenge and the client has a refreshing source. No status code is hardcoded in the client.

`allowsRefreshOnChallenge` is independent of whether a credential is applied, which follows `authentication` alone. Both overrides are meaningful. The name describes endpoint permission rather than promising that every client has refresh capability.

### Credentials the Package Does Not Model

A request whose credential arrives through a cookie jar, a signing `Transport`, or a proxy has no scheme to declare. It declares `nil` and opts back in:

```swift
struct Request: InterfaceRequest {
    // ...
    let authentication: AuthenticationScheme? = nil
    var allowsRefreshOnChallenge: Bool { true }
}
```

Without the override, such a request gets no challenge retry and no coalesced refresh. With the override but no credential source, a recognized challenge throws `APIClientError.noCredentialSource`.

### The Refresh Endpoint

A token-refresh endpoint sends a credential of its own. A challenge on it has to surface rather than recurse into another refresh:

```swift
struct Request: InterfaceRequest {
    // ...
    let authentication: AuthenticationScheme? = .bearer
    var allowsRefreshOnChallenge: Bool { false }
}
```

The credential is still applied, because that follows `authentication`.

### Read-Only Challenges

A recognized challenge against a read-only source surfaces the original `ResponseError`. The source is not read again and the request is not retried. This supports static API keys, long-lived tokens, session-bound credentials, and one-time reads without requiring a meaningless refresh closure.

### The Challenge Policy

```swift
public struct AuthenticationChallengePolicy: Sendable {
    public let isChallenge: @Sendable (ResponseError, ResponseStatusContract) -> Bool

    public static let unmodelled401: AuthenticationChallengePolicy  // the default
    public static let any401: AuthenticationChallengePolicy
}
```

A server that signals staleness some other way:

```swift
let configuration = ServerConfiguration(
    url: url,
    challengePolicy: AuthenticationChallengePolicy { error, _ in
        error.statusCode == 419 || error.header("WWW-Authenticate") != nil
    }
)
```

The policy receives the Interface's output-erased response statuses so it can ask what the endpoint declared. Inferring that from the thrown `ResponseError` case instead would tie the policy to `DefaultResponseHandler`'s error mapping, which a custom `ResponseHandler` may change.

### `.unmodelled401`

The default refreshes on 401 unless the Interface declared an exact `.code(401, ...)` case.

An endpoint that models 401 surfaces its own error rather than refreshing, which also stops a throwing `refresh` from replacing that error at the catch site.

A range match does not count as modelling 401:

```swift
static let responses = ResponseContract<Response>(
    success: .exact(200),
    failures: [.clientError(.decodeError(APIErrorBody.self))] // still refreshes on 401
)

static let responses = ResponseContract<Response>(
    success: .exact(200),
    failures: [.code(401, .decodeError(LoginError.self))] // does not refresh
)
```

`.clientError` is a catch-all for status codes the endpoint did not consider, 401 included.

When an endpoint both models 401 exactly and relies on refresh firing, `.any401` applies across the configuration:

```swift
ServerConfiguration(url: url, challengePolicy: .any401)
```

### Refresh Generations

Refresh coalescing is scoped to the client and its monotonic lifecycle generation. The generation advances after every successful refresh, including one that leaves the credential string unchanged.

The client does not compare credential strings before refresh. Equality is not a general definition of credential identity, and an extra read can consume or rotate a source. More importantly, replaying a request merely because the source changed could execute it under another account. Invalidate the old client and create a new one at account boundaries.

Cross-client refresh coalescing is intentionally unsupported.

## Not Supported

- **Multiple credential lifecycles per client.** Use separate clients when credentials refresh independently.
- **Socket authentication.** `SocketIOClient` has no credential lifecycle integration.
