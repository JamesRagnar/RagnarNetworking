# Server Configuration

`ServerConfiguration` defines the base URL, optional auth token, and request encoding configuration used to build requests.

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: "token"
)
```

## Request Encoder

Request bodies are encoded using a `RequestEncoder` factory to keep Swift 6 Sendable conformance (JSONEncoder is not Sendable).

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    requestEncoder: RequestEncoder(
        keyEncodingStrategy: .convertToSnakeCase,
        dateEncodingStrategy: .iso8601
    )
)
```

You can also provide a custom factory for full control:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    requestEncoder: RequestEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
)
```

## Auth Token Behavior

The token is applied based on the request's `AuthenticationType`:
- `.bearer` adds `Authorization: Bearer <token>` (can be overridden by custom `Authorization` header)
- `.url` appends `?token=<token>` and removes any existing `token` query items (case-insensitive) from both the base URL and request parameters
- `.none` ignores the token
