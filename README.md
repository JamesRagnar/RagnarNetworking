# RagnarNetworking

A modern, type-safe Swift networking library for building API interfaces with compile-time safety and minimal boilerplate.

## Quick Example

Define a typed interface, then call it through `APIClient`:

```swift
struct GetUserInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [String: String?]? = nil
        let headers: [String: String]? = nil
        let body: EmptyBody? = nil
        let authentication: AuthenticationType = .bearer

        init(userId: Int) {
            self.path = "/users/\(userId)"
        }
    }

    typealias Response = User

    static var responseCases: ResponseMap {
        [
            .code(200, .decode),
            .code(404, .error(APIError.userNotFound)),
            .code(401, .error(APIError.unauthorized))
        ]
    }
}

let client = APIClient(
    baseURL: URL(string: "https://api.example.com")!,
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
- Built-in auth strategies (`.none`, `.bearer`, `.url`)
- Strict request bodies via `RequestBody` with intrinsic content types
- `APIClient` actor with automatic 401 retry and coalesced token refresh
- `SocketIOClient` actor with typed event streams and automatic reconnection
- Immutable per-instance logging configuration via `RagnarNetworkingLogging`
- Testable, protocol-based networking
- Advanced request-construction extension API via `InterfaceConstructor`

## Documentation

- [Documentation Overview](Documentation/README.md)
- [APIClient](Documentation/api_client.md)
- [SocketIOClient](Documentation/socket_io_client.md)
- [DataTaskProvider](Documentation/data_task_provider.md)
- [Server Configuration](Documentation/server_configuration.md)
- [Interfaces Overview](Documentation/Interfaces/README.md)
- [Request Parameters](Documentation/Interfaces/request_parameters.md)
- [Response Handling](Documentation/Interfaces/response_handling.md)
- [Interface Constructor](Documentation/Interfaces/interface_constructor.md)

## Requirements

- Swift 6.0+
- iOS 17.0+ / macOS 14.0+

## License

RagnarNetworking is released under the Apache 2.0 License. See [LICENSE](LICENSE.md) for details.
