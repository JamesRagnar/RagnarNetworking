# APIClient

`APIClient` is the recommended entry point for making authenticated requests. It wraps `RequestPipeline` with credential management, automatic challenge retry, and terminal client invalidation.

## Setup

```swift
let client = APIClient(
    configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!),
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
)
```

For unauthenticated-only flows, use the convenience initializer:

```swift
let client = APIClient(
    configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!)
)
```

- `configuration.url` is fixed for the lifetime of the client. Recreate the client if the server URL changes.
- `ServerConfiguration` holds no credential. The client pairs it with the current token in a `RequestContext` on every request, so token management goes through `token`/`refresh` exclusively.
- `token` is evaluated lazily before each authenticated request, so it always reflects the current token - including after a refresh.
- `refresh` must update whatever state `token` reads from. It is called at most once per challenge burst regardless of how many concurrent requests fail.
- The convenience initializer is intended for clients that only send `.none` requests.
- If a `.bearer` or `.url` request is sent through the convenience initializer, the request will fail with authentication-related errors.

## Customizing Request Construction and Response Decoding

Everything about the server lives on `configuration`: `requestEncoder`, `defaultHeaders`,
`responseDecoder`, `builder`, and `responseHandler` all reach every request and response handled
by the client. Both initializers additionally accept a `transport`, which is the one piece that
describes the process rather than the server:

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
        )
    ),
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
)
```

```swift
let client = APIClient(
    configuration: ServerConfiguration(
        url: URL(string: "https://api.example.com")!,
        builder: ClientTaggingBuilder(clientID: "ios"),
        responseHandler: EnvelopeUnwrappingHandler()
    ),
    transport: URLSession.shared,
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
)
```

See [Server Configuration](server_configuration.md) for details on `RequestEncoder`,
`defaultHeaders` precedence, `ResponseDecoder`, and where a given knob belongs;
[Request Builder](Interfaces/request_builder.md) for building custom request builders; and
[RequestPipeline](request_pipeline.md) for using the pipeline without `APIClient`.

## Sending Requests

```swift
let user = try await client.send(GetUserInterface.self, .init(userId: 123))
```

## Authentication Behavior

`RequestParameters.isAuthenticated` controls whether the token closure is invoked and whether the request participates in challenge retry. It defaults to `authentication != .none`.

- A request with `isAuthenticated == false` never calls the token closure and is never retried. Use for login, registration, and other unauthenticated endpoints.
- A request with `isAuthenticated == true` resolves a credential, applies the `Authenticator` registered for its scheme, and on a challenge refreshes once and retries with a fresh credential.

A request that declares `.none` but carries its credential some other way - a cookie jar, a signing `Transport` - overrides `isAuthenticated` to `true` to opt back into retry and refresh. See [Authentication](Interfaces/authentication.md).

## What Counts as a Challenge

`ServerConfiguration.challengePolicy` decides. No status code is hardcoded in `APIClient`.

The default, `.unmodelled401`, challenges on 401 unless the Interface declared an exact `.code(401, ...)` case. An endpoint that deliberately models 401 surfaces its own error rather than triggering a refresh it did not ask for, which also stops a failing refresh from masking that error. A 4xx *range* case does not count as modelling 401.

`.any401` challenges on every 401, matching the behavior before challenge policies existed.

```swift
ServerConfiguration(
    url: url,
    challengePolicy: AuthenticationChallengePolicy { error, _ in
        error.statusCode == 419
    }
)
```

## Concurrent Challenge Coalescing

If multiple requests are challenged while using the same token, only one `refresh` call is made regardless of whether the failures arrive simultaneously or are staggered over time. All requests resume after that single refresh completes, using the fresh token. If refresh throws, all requests that joined it receive the error.

A request challenged after a refresh has already produced a newer token does not trigger a second refresh - it retries directly with the token now in effect.

## Lifecycle and Invalidation

Call `invalidate()` when the client must no longer send requests, such as during logout or when replacing a connection generation:

```swift
await client.invalidate()
```

Invalidation is terminal and idempotent. After it is called:

- New `send` calls fail with `APIClientError.invalidated`, before token resolution or transport work begins.
- In-flight transport tasks are cancelled. If a custom `Transport` does not honor cancellation, its result is still suppressed before it can complete through the client.
- A coalesced token refresh is cancelled, and no challenge retry is started.
- The client never becomes valid again. Create a new `APIClient` for a new server URL or connection generation.

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
