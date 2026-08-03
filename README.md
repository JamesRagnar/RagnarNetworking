# RagnarNetworking

A Swift package containing independent HTTP, WebSocket, and Socket.IO networking products.

## Products

- `RagnarNetworking` provides typed HTTP interfaces, request construction, response contracts, and `APIClient`.
- `RagnarWebSocket` provides a thin actor facade over `URLSessionWebSocketTask`.
- `RagnarSocketIO` provides the documented Engine.IO 4 and Socket.IO protocol 5 subset over `RagnarWebSocket`.

`RagnarSocketIO` depends on `RagnarWebSocket`. Neither socket product depends on `RagnarNetworking`, so HTTP-only
consumers do not build or link socket code.

## Quick Example

Define a typed interface, then call it through `APIClient`:

```swift
struct User: Codable, InterfaceResponse {
    let id: Int
    let name: String
}

struct GetUserInterface: Interface {
    struct Request: InterfaceRequest {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [URLQueryItem]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody = .init()
        let authentication: AuthenticationScheme? = .bearer

        init(userId: Int) {
            self.path = "/users/\(userId)"
        }
    }

    typealias Response = User

    static let responses = ResponseContract<Response>(
        success: .exact(200),
        failures: [
            .code(404, .error(APIError.userNotFound)),
            .code(401, .error(APIError.unauthorized))
        ]
    )
}

let client = APIClient(
    configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!),
    credentialSource: .refreshing(
        read: { try await keychain.accessToken() },
        refresh: { try await authService.refresh() }
    )
)

let user = try await client.send(
    GetUserInterface.self,
    .init(userId: 123)
)
```

## Features

- Type-safe endpoints with explicit status code handling (exact codes + ranges)
- Automatic request construction from declarative parameters
- Pluggable authentication: open schemes, per-server `Authenticator` registry, configurable challenge policy
- Strict request bodies via `RequestBody` and response types via `InterfaceResponse`, both open to
  non-JSON formats without changing the package
- `APIClient` actor with automatic challenge retry, coalesced credential refresh, and terminal invalidation
- Independent `RagnarSocketIO` product with typed event streams, bounded buffering, and automatic transport reconnection
- Testable request execution via `Transport` and WebSocket execution via `WebSocketClient`
- Advanced request-construction extension API via `RequestBuilder`

## Documentation

- [Documentation Overview](Documentation/README.md)
- [APIClient](Documentation/api_client.md)
- [WebSocket Transport](Documentation/WebSocket.md)
- [Socket.IO Client](Documentation/SocketIO.md)
- [RequestPipeline and Transport](Documentation/request_pipeline.md)
- [Server Configuration](Documentation/server_configuration.md)
- [Interfaces Overview](Documentation/Interfaces/README.md)
- [Interface Request](Documentation/Interfaces/interface_request.md)
- [Response Handling](Documentation/Interfaces/response_handling.md)
- [Request Builder](Documentation/Interfaces/request_builder.md)
- [Error Handling](Documentation/error_handling.md)
- [Concurrency](Documentation/concurrency.md)

## Requirements

- Swift Package Manager tools 6.0+
- iOS 16.0+
- macOS 13.0+
- tvOS 16.0+
- watchOS 9.0+
- visionOS 1.0+

## License

RagnarNetworking is released under the Apache 2.0 License. See [LICENSE](LICENSE.md) for details.
