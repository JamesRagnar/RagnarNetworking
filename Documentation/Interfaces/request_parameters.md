# Request Parameters

`RequestParameters` defines everything needed to build a request.

This is the primary modeling API for the Interface layer.

```swift
public protocol RequestParameters: Sendable {
    associatedtype Body: RequestBody = EmptyBody

    var method: RequestMethod { get }
    var path: String { get }
    var queryItems: [URLQueryItem]? { get }
    var headers: [String: String]? { get }
    var body: Body { get }
    var authentication: AuthenticationType { get }
}
```

## Every Member Is Required, Deliberately

None of these members has a protocol-extension default, so a conformance restates all six even
when four of them are `nil` or empty. This is intentional and not an oversight.

Defaults here fail silently and late. A `queryItems` you meant to populate, or an `authentication`
you meant to set to `.bearer`, produces a wrong request at runtime with nothing to look at.

To be precise about what this buys: requiring the member does **not** move that error to compile
time. `let queryItems: [URLQueryItem]? = nil` still compiles, and an interpolated `path` that
forgets to use its parameter still compiles. What it does is force every part of the request to
appear in the declaration, so a wrong request is visible in the source and in the diff rather than
inferred from an absence. That is a review guarantee, not a compiler guarantee, and it is worth
the six lines.

`Interface.Response` requires an explicit `InterfaceResponse` conformance for the same reason.

## Query Items

`queryItems` is an ordered array of `URLQueryItem` values. A `nil` value creates a name-only query item (e.g. `?flag`). If you want to omit a key, leave it out of the array.

The array order is preserved during URL construction, and repeated names are supported when an endpoint requires duplicate query keys.

## Request Body

All bodies must conform to `RequestBody`, which couples the encoded data with its content type.

```swift
public protocol RequestBody: Sendable {
    func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody
}

public struct EncodedBody: Sendable {
    public let data: Data
    public let contentType: String?
}
```

`encodeBody` receives the configuration's `RequestEncoder`, not a concrete `JSONEncoder`. A JSON
body calls `encoder.makeJSONEncoder()` to pick up the client's configured strategies; a body in
another format ignores it. This mirrors `InterfaceResponse.decode` on the response side, and it
means a non-JSON body is not handed a `JSONEncoder` it has no use for.

### JSON Body (Default)

If your body is `Encodable`, you get a default `encodeBody(using:)` implementation that encodes JSON and sets `Content-Type: application/json`.

```swift
struct CreateUser: RequestBody, Encodable, Sendable {
    let name: String
    let email: String
}

struct Parameters: RequestParameters {
    typealias Body = CreateUser
    let body: CreateUser
}
```

### No Body

Use `EmptyBody()` for requests without a body.

```swift
struct Parameters: RequestParameters {
    let body: EmptyBody = .init()
}
```

### Binary Data

Use `BinaryBody` for raw data uploads.

```swift
let body = BinaryBody(data: imageData, contentType: "image/jpeg")
```

### Array Body

Use `ArrayBody` for top-level JSON arrays.

```swift
struct Parameters: RequestParameters {
    typealias Body = ArrayBody<Int>
    let body: ArrayBody<Int>
}

let params = Parameters(body: ArrayBody([1, 2, 3]))
// Encodes as: [1, 2, 3]
```

### Wrapping Existing Encodables

Use `EncodableBody` to wrap any existing `Encodable` type without adding `RequestBody` conformance.

```swift
struct LegacyPayload: Encodable, Sendable {
    let id: Int
}

struct Parameters: RequestParameters {
    typealias Body = EncodableBody<LegacyPayload>
    let body: EncodableBody<LegacyPayload>
}

let params = Parameters(body: EncodableBody(LegacyPayload(id: 1)))
```

### Custom Content-Type

Implement `encodeBody(using:)` for non-JSON payloads.

```swift
struct XmlBody: RequestBody, Sendable {
    let xml: String

    func encodeBody(using encoder: RequestEncoder) throws -> EncodedBody {
        EncodedBody(data: Data(xml.utf8), contentType: "application/xml")
    }
}
```

### Nullable Fields

Use `Nullable<T>` to encode an explicit JSON `null` (distinct from omitting the field). This is useful when an API distinguishes between "unset" and "set to null".

```swift
struct UpdateUser: RequestBody, Encodable, Sendable {
    let nickname: Nullable<String>?  // nil = omit, .null = explicit null, .value = set
}

UpdateUser(nickname: nil)
// Field omitted entirely

UpdateUser(nickname: .null)
// {"nickname": null}

UpdateUser(nickname: .value("Bob"))
// {"nickname": "Bob"}
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
- `.url` appends the auth token as a `token` query item and removes any existing `token` query item (case-insensitive) from both the base URL and `queryItems`.
- `.bearer` adds the `Authorization` header before merging custom headers, and a caller can still override it by setting `Authorization` (case-insensitive) in `headers`.

## Methods

`RequestMethod` includes standard HTTP verbs (`get`, `post`, `put`, `patch`, `delete`, `head`, `options`, `connect`, `trace`).
