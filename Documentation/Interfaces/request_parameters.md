# Request Parameters

`RequestParameters` defines everything needed to build a request.

```swift
public protocol RequestParameters: Sendable {
    var method: RequestMethod { get }
    var path: String { get }
    var queryItems: [String: String?]? { get }
    var headers: [String: String]? { get }
    var body: RequestBody? { get }
    var authentication: AuthenticationType { get }
}
```

## Query Items

`queryItems` is a dictionary of names to optional values. A `nil` value creates a name-only query item (e.g. `?flag`). If you want to omit a key, remove it from the dictionary instead of setting it to `nil`.

## Request Body

`RequestBody` provides explicit body types with built-in encoding (UTF-8 for text) and inferred `Content-Type` when a body exists and the header is not already set.

```swift
public enum RequestBody: Sendable {
    case json(any Encodable & Sendable)
    case data(Data)
    case text(String)
}
```

Examples:

```swift
body = .json(["name": "Ragnar"])
body = .data(rawData)
body = .text("hello")
```

## Authentication

`AuthenticationType` controls how the `ServerConfiguration.authToken` is applied:

```swift
public enum AuthenticationType: Sendable {
    case none
    case bearer  // Authorization: Bearer <token>
    case url     // ?token=<token>
}
```

Behavior notes:
- `.url` appends the auth token as a `token` query item and removes any existing `token` query item provided in `queryItems`.
- `.bearer` adds the `Authorization` header before merging custom headers, and a caller can still override it by setting `Authorization` (case-insensitive) in `headers`.

## Methods

`RequestMethod` includes standard HTTP verbs (`get`, `post`, `put`, `patch`, `delete`, `head`, `options`, `connect`, `trace`).
