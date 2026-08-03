# APIClient

`APIClient` is the recommended entry point for sending requests. It wraps `RequestPipeline` with one optional credential lifecycle, bounded challenge recovery, and terminal client invalidation.

## Setup

A refreshing access token uses a refreshing `CredentialSource`:

```swift
let client = APIClient(
    configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!),
    credentialSource: .refreshing(
        read: { try await keychain.accessToken() },
        refresh: { try await authService.refresh() }
    )
)
```

A static API key or long-lived token uses a read-only source:

```swift
let apiKey = AuthenticationScheme("apiKey")

let client = APIClient(
    configuration: ServerConfiguration(
        url: URL(string: "https://api.example.com")!,
        authenticators: [apiKey: .header("X-API-Key")]
    ),
    credentialSource: .readOnly { configuration.apiKey }
)
```

For unauthenticated-only flows, omit the source:

```swift
let client = APIClient(
    configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!)
)
```

## One Client, One Lifecycle

One `APIClient` coordinates at most one credential lifecycle. `AuthenticationScheme` does not identify credential state. It identifies how the current credential is applied through `ServerConfiguration.authenticators`.

This means `.bearer` and `.url` requests on one client can share the same access token and refresh generation while placing it differently. If an application genuinely has independent bearer-token and API-key lifecycles, use separate clients. There is no per-scheme credential registry and no cross-client refresh coalescing.

The source is evaluated lazily:

- A request declaring no authentication scheme does not read it.
- An authenticated request reads it once before each request attempt.
- A read-only source never refreshes, never performs a comparison read, and never causes an automatic retry.
- A refreshing source is read again after a successful refresh to build the single retry.
- A `nil` credential fails request construction with `RequestError.missingCredential`.

`refresh` must finish only after the state observed by `read` reflects the completed lifecycle transition. It may leave the credential string unchanged when it renews server-side validity without rotating the value.

## Source Changes Outside the Client

Refresh coordination uses a client-owned monotonic generation, not credential string comparison. The client deliberately does not perform an extra read before refresh:

- Credential values are opaque to the package. String equality does not prove lifecycle identity.
- A successful refresh may preserve the same string while renewing server-side validity.
- An additional read is observable for one-time, rotating, or consuming sources.
- Replaying an in-flight request merely because the source changed could execute it under a different signed-in identity.

Changes made outside the client are observed on the next normal credential read, but do not replace the refresh path for a request already challenged. Account changes and other identity boundaries should call `invalidate()` and create a new client.

## Customizing Requests and Responses

Everything about the server lives on `configuration`: `requestEncoder`, `defaultHeaders`, `responseDecoder`, `builder`, and `responseHandler` all reach every request and response handled by the client. The initializer additionally accepts a `transport`, which describes the request process rather than the server:

```swift
let client = APIClient(
    configuration: ServerConfiguration(
        url: URL(string: "https://api.example.com")!,
        requestEncoder: RequestEncoder(
            keyEncodingStrategy: .convertToSnakeCase,
            dateEncodingStrategy: .iso8601
        ),
        defaultHeaders: ["Accept-Language": "en-US"],
        responseDecoder: ResponseDecoder(
            keyDecodingStrategy: .convertFromSnakeCase,
            dateDecodingStrategy: .iso8601
        ),
        builder: ClientTaggingBuilder(clientID: "ios"),
        responseHandler: EnvelopeUnwrappingHandler()
    ),
    transport: URLSession.shared,
    credentialSource: .refreshing(
        read: { try await keychain.accessToken() },
        refresh: { try await authService.refresh() }
    )
)
```

See [Server Configuration](server_configuration.md), [Request Builder](Interfaces/request_builder.md), and [RequestPipeline](request_pipeline.md).

## Sending Requests

```swift
let user = try await client.send(GetUserInterface.self, .init(userId: 123))
```

## Authentication Behavior

Two independent `InterfaceRequest` members control authentication participation.

`authentication` decides whether the source is read and which configured `Authenticator` applies the credential. A request declaring no scheme never reads the source.

`allowsRefreshOnChallenge` decides whether the endpoint permits a refreshing source to recover after `ServerConfiguration.challengePolicy` recognizes a challenge. It defaults to `authentication != nil`.

- Override it to `true` with no scheme for externally applied authentication, such as a cookie jar or signing `Transport`.
- Override it to `false` with a scheme for a token-refresh endpoint that must surface its own challenge rather than recurse.
- A read-only source always surfaces the original `ResponseError`, regardless of the default `true` value on an authenticated request.
- A client with no source reports `APIClientError.noCredentialSource` only when a schemeless request explicitly allows refresh and then receives a recognized challenge. A request declaring a registered scheme fails earlier with `RequestError.missingCredential`.

See [Authentication](Interfaces/authentication.md).

## What Counts as a Challenge

`ServerConfiguration.challengePolicy` decides. No status code is hardcoded in `APIClient`.

The default, `.unmodelled401`, challenges on 401 unless the Interface declared an exact `.code(401, ...)` case. An endpoint that models 401 surfaces its own error rather than allowing refresh. A 4xx range case does not count as modelling 401.

`.any401` challenges on every 401.

```swift
ServerConfiguration(
    url: url,
    challengePolicy: AuthenticationChallengePolicy { error, _ in
        error.statusCode == 419
    }
)
```

The policy is server-wide because challenge recognition is part of the server contract. Endpoint participation remains request-specific through `allowsRefreshOnChallenge` and exact response declarations.

## Concurrent Challenge Coalescing

If multiple requests are challenged in one credential generation, only one refresh runs regardless of whether the failures arrive simultaneously or are staggered. All requests resume after that refresh completes and re-read the source for their retry. If refresh throws, every request that joined it receives the error.

Each original request can be retried at most once. A second challenge surfaces without another refresh.

The generation advances after every successful refresh, even if the credential string is unchanged. A staggered challenge from an older generation retries with the current credential rather than starting another refresh.

## Lifecycle and Invalidation

Call `invalidate()` when the client must no longer send requests, such as during logout or when replacing an account or connection generation:

```swift
await client.invalidate()
```

Invalidation is terminal and idempotent. After it is called:

- New `send` calls fail with `APIClientError.invalidated`, before credential resolution or transport work begins.
- In-flight transport tasks are cancelled. If a custom `Transport` does not honor cancellation, its result is still suppressed before it can complete through the client.
- A coalesced refresh is cancelled, and no challenge retry is started.
- The client never becomes valid again. Create a new `APIClient` for a new identity, server URL, or connection generation.

Handle invalidation separately from request, transport, and response errors when a caller needs to replace the client:

```swift
do {
    let user = try await client.send(
        GetUserInterface.self,
        .init(userId: 123)
    )
    print(user)
} catch APIClientError.invalidated {
    // Obtain and use a replacement APIClient.
}
```
