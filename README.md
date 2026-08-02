# RagnarNetworking

A modern, type-safe Swift networking library for building API interfaces with compile-time safety and minimal boilerplate.

## Quick Example

Define a typed interface, then call it through `APIClient`:

```swift
struct User: Codable, InterfaceResponse {
    let id: Int
    let name: String
}

struct GetUserInterface: Interface {
    struct Parameters: RequestParameters {
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

    static let responseCases: ResponseMap = [
        .code(200, .decode),
        .code(404, .error(APIError.userNotFound)),
        .code(401, .error(APIError.unauthorized))
    ]
}

let client = APIClient(
    configuration: ServerConfiguration(url: URL(string: "https://api.example.com")!),
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
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
- `SocketIOClient` actor with typed event streams and automatic reconnection
- Testable request execution via `Transport` and socket transport via `SocketClient`
- Advanced request-construction extension API via `RequestBuilder`

## Documentation

- [Documentation Overview](Documentation/README.md)
- [APIClient](Documentation/api_client.md)
- [SocketIOClient](Documentation/socket_io_client.md)
- [RequestPipeline and Transport](Documentation/request_pipeline.md)
- [Server Configuration](Documentation/server_configuration.md)
- [Interfaces Overview](Documentation/Interfaces/README.md)
- [Request Parameters](Documentation/Interfaces/request_parameters.md)
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
