# APIClient

`APIClient` is the recommended entry point for making authenticated requests. It wraps `DataTaskProvider` with auth token management and automatic 401 retry.

## Setup

```swift
let client = APIClient(
    baseURL: URL(string: "https://api.example.com")!,
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
)
```

- `baseURL` is fixed for the lifetime of the client. Recreate the client if the server URL changes.
- `token` is evaluated lazily before each authenticated request, so it always reflects the current token — including after a refresh.
- `refresh` must update whatever state `token` reads from. It is called at most once per 401 burst regardless of how many concurrent requests fail.

## Sending Requests

```swift
let user = try await client.send(GetUserInterface.self, .init(userId: 123))
```

## Authentication Behavior

The request's `AuthenticationType` controls whether the token closure is invoked:

- `.none` — token closure is never called. Use for login, registration, and other unauthenticated endpoints.
- `.bearer` — token is fetched and sent as `Authorization: Bearer <token>`. On 401, refresh fires once, then the request is retried with a fresh token.
- `.url` — same retry behavior, token is sent as `?token=<token>`.

## Concurrent 401 Coalescing

If multiple requests fail with 401 simultaneously, only one `refresh` call is made. All waiting requests resume after the single refresh completes. If refresh throws, all waiters receive the error.
