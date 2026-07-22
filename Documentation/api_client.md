# APIClient

`APIClient` is the recommended entry point for making authenticated requests. It wraps `DataTaskProvider` with auth token management, automatic 401 retry, and terminal client invalidation.

## Setup

```swift
let client = APIClient(
    baseURL: URL(string: "https://api.example.com")!,
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
)
```

For unauthenticated-only flows, use the convenience initializer:

```swift
let client = APIClient(
    baseURL: URL(string: "https://api.example.com")!
)
```

- `baseURL` is fixed for the lifetime of the client. Recreate the client if the server URL changes.
- `token` is evaluated lazily before each authenticated request, so it always reflects the current token - including after a refresh.
- `refresh` must update whatever state `token` reads from. It is called at most once per 401 burst regardless of how many concurrent requests fail.
- The convenience initializer is intended for clients that only send `.none` requests.
- If a `.bearer` or `.url` request is sent through the convenience initializer, the request will fail with authentication-related errors.

## Sending Requests

```swift
let user = try await client.send(GetUserInterface.self, .init(userId: 123))
```

## Authentication Behavior

The request's `AuthenticationType` controls whether the token closure is invoked:

- `.none` - token closure is never called. Use for login, registration, and other unauthenticated endpoints.
- `.bearer` - token is fetched and sent as `Authorization: Bearer <token>`. On 401, refresh fires once, then the request is retried with a fresh token.
- `.url` - same retry behavior, token is sent as `?token=<token>`.

## Concurrent 401 Coalescing

If multiple requests fail with 401 simultaneously, only one `refresh` call is made. All waiting requests resume after the single refresh completes. If refresh throws, all waiters receive the error.

## Lifecycle and Invalidation

Call `invalidate()` when the client must no longer send requests, such as during logout or when replacing a connection generation:

```swift
await client.invalidate()
```

Invalidation is terminal and idempotent. After it is called:

- New `send` calls fail with `APIClientError.invalidated`, before token resolution or transport work begins.
- In-flight transport tasks are cancelled. If a custom `DataTaskProvider` does not honor cancellation, its result is still suppressed before it can complete through the client.
- A coalesced token refresh is cancelled, and no 401 retry is started.
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
