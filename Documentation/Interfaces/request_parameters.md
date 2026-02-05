# Request Parameters

`RequestParameters` defines everything needed to build a request.

```swift
public protocol RequestParameters: Sendable {
    associatedtype Body: RequestBody = EmptyBody

    var method: RequestMethod { get }
    var path: String { get }
    var queryItems: [String: String?]? { get }
    var headers: [String: String]? { get }
    var body: Body? { get }
    var authentication: AuthenticationType { get }
}
```

## Query Items

`queryItems` is a dictionary of names to optional values. A `nil` value creates a name-only query item (e.g. `?flag`). If you want to omit a key, remove it from the dictionary instead of setting it to `nil`.

## Request Body

All bodies must conform to `RequestBody`, which couples the encoded data with its content type.

```swift
public protocol RequestBody: Sendable {
    func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody
}

public struct EncodedBody: Sendable {
    public let data: Data
    public let contentType: String?
}
```

### JSON Body (Default)

If your body is `Encodable`, you get a default `encodeBody(using:)` implementation that encodes JSON and sets `Content-Type: application/json`.

```swift
struct CreateUser: RequestBody, Encodable {
    let name: String
    let email: String
}

struct Parameters: RequestParameters {
    typealias Body = CreateUser
    let body: CreateUser?
}
```

### No Body

Use `EmptyBody` for requests without a body (body must be `nil`). `EmptyBody` is a type marker and cannot be instantiated.

```swift
struct Parameters: RequestParameters {
    let body: EmptyBody? = nil
}
```

### Binary Data

Use `BinaryBody` for raw data uploads.

```swift
let body = BinaryBody(data: imageData, contentType: "image/jpeg")
```

### Custom Content-Type

Implement `encodeBody(using:)` for non-JSON payloads.

```swift
struct XmlBody: RequestBody {
    let xml: String

    func encodeBody(using encoder: JSONEncoder) throws -> EncodedBody {
        EncodedBody(data: Data(xml.utf8), contentType: "application/xml")
    }
}
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
