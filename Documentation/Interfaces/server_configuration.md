# Server Configuration

`ServerConfiguration` defines the base URL and optional auth token used to build requests.

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: "token"
)
```

## Auth Token Behavior

The token is applied based on the request’s `AuthenticationType`:
- `.bearer` adds `Authorization: Bearer <token>`
- `.url` appends `?token=<token>`
- `.none` ignores the token
