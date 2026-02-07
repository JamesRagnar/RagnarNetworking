# RagnarNetworking

A modern, type-safe Swift networking library for building API interfaces with compile-time safety and minimal boilerplate.

## Quick Example

Define a typed interface and call it with shorthand parameter initialization:

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

let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: token
)

let user = try await URLSession.shared.dataTask(
    GetUserInterface.self,
    .init(userId: 123),
    config
)
```

## Features

- Type-safe endpoints with explicit status code handling (exact codes + ranges)
- Automatic request construction from declarative parameters
- Built-in auth strategies (`.none`, `.bearer`, `.url`)
- Strict request bodies via `RequestBody` with intrinsic content types
- Testable, protocol-based networking
- Customizable request construction via `InterfaceConstructor`

## Documentation

- [Interfaces Overview](Documentation/Interfaces/README.md)
- [Request Parameters](Documentation/Interfaces/request_parameters.md)
- [Response Handling](Documentation/Interfaces/response_handling.md)
- [DataTaskProvider](Documentation/Interfaces/data_task_provider.md)
- [Server Configuration](Documentation/Interfaces/server_configuration.md)
- [Interface Constructor](Documentation/Interfaces/interface_constructor.md)

## Requirements

- Swift 6.2+
- iOS 13.0+ / macOS 11.0+

## License

RagnarNetworking is released under the Apache 2.0 License. See [LICENSE](LICENSE.md) for details.
