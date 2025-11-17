# RagnarNetworking

A modern, type-safe Swift networking library that eliminates boilerplate and provides compile-time safety for your API interactions.

## Overview

RagnarNetworking transforms API endpoints into strongly-typed Swift interfaces, giving you automatic request construction, intelligent response handling, and rich error management—all with full compile-time guarantees.

### Key Features

- **Type-Safe Endpoints** - Define API endpoints as Swift types with compile-time guarantees
- **Automatic Request Construction** - Build URLRequests from simple, declarative parameters
- **Smart Response Handling** - Map HTTP status codes to success or error cases
- **Flexible Authentication** - Built-in support for Bearer tokens and URL-based auth
- **Powerful Error Inspection** - Rich error types with debugging helpers
- **Fully Testable** - Protocol-based design with comprehensive test coverage

---

## Installation

### Swift Package Manager

Add RagnarNetworking to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/JamesRagnar/RagnarNetworking.git", branch: "main")
]
```

---

## Quick Example

See the difference between traditional networking and RagnarNetworking:

### Traditional Approach

```swift
// Build URL manually
var components = URLComponents(string: "https://api.example.com")!
components.path = "/users/123"

var request = URLRequest(url: components.url!)
request.httpMethod = "GET"
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// Make request and handle response
let (data, response) = try await URLSession.shared.data(for: request)

// Cast and validate response
guard let httpResponse = response as? HTTPURLResponse else {
    throw NetworkError.invalidResponse
}

// Check status code manually
guard httpResponse.statusCode == 200 else {
    throw NetworkError.httpError(httpResponse.statusCode)
}

// Decode manually
let user = try JSONDecoder().decode(User.self, from: data)
```

### With RagnarNetworking

```swift
// 1. Define your endpoint once
struct GetUserInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [String: String]? = nil
        let headers: [String: String]? = nil
        let body: Data? = nil
        let authentication: AuthenticationType = .bearer

        init(userId: Int) {
            self.path = "/users/\(userId)"
        }
    }

    typealias Response = User

    static var responseCases: ResponseCases {
        [
            200: .success(User.self),
            404: .failure(APIError.userNotFound),
            401: .failure(APIError.unauthorized)
        ]
    }
}

// 2. Make type-safe requests
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: token
)

let user = try await URLSession.shared.dataTask(
    GetUserInterface.self,
    GetUserInterface.Parameters(userId: 123),
    config
)
```

**Benefits:**
- Automatic URL construction, authentication, and header management
- Type-safe response decoding
- Explicit status code handling with custom errors
- Reusable endpoint definitions
- No manual casting or validation needed

---

## Documentation

### Interfaces

**[Interface Guide](docs/interfaces/guide.md)** - Comprehensive guide to using the Interface system, including:
- Core concepts and protocols
- Usage examples (GET, POST, query parameters, different response types)
- Error handling and inspection
- Authentication strategies
- Testing with mock providers

### Sockets

**Socket Support** - *(Coming soon)* Built-in WebSocket support for real-time communication.

---

## Requirements

- Swift 5.9+
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+

---

## License

RagnarNetworking is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## Author

James Harquail
