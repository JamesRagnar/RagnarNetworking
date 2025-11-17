# Interface Guide

A comprehensive guide to using RagnarNetworking's Interface system for type-safe networking.

## Table of Contents

- [Core Concepts](#core-concepts)
- [Usage Examples](#usage-examples)
- [Error Handling](#error-handling)
- [Authentication](#authentication)
- [Testing](#testing)

---

## Core Concepts

### Interfaces

The `Interface` protocol is the heart of RagnarNetworking. It connects your request parameters with expected response types and defines how different HTTP status codes should be handled.

```swift
public protocol Interface: Sendable {
    associatedtype Parameters: RequestParameters
    associatedtype Response: Decodable, Sendable

    static var responseCases: [Int: Result<Response.Type, Error>] { get }
}
```

Each Interface defines:
- **Parameters** - How to construct the request (path, method, headers, body, auth)
- **Response** - The expected success response type
- **Response Cases** - Mapping of HTTP status codes to outcomes

### Request Parameters

The `RequestParameters` protocol defines all components needed to build an HTTP request:

```swift
public protocol RequestParameters: Sendable {
    var method: RequestMethod { get }           // GET, POST, PUT, etc.
    var path: String { get }                    // "/api/users/123"
    var queryItems: [String: String]? { get }   // URL query parameters
    var headers: [String: String]? { get }      // HTTP headers
    var body: Data? { get }                     // Request body
    var authentication: AuthenticationType { get } // .none, .bearer, .url
}
```

### Server Configuration

Server configuration provides the base URL and optional authentication token:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: "your-auth-token"
)
```

The authentication token is automatically applied based on the `AuthenticationType` specified in your request parameters.

---

## Usage Examples

### Basic GET Request

```swift
// 1. Define your response type
struct User: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

// 2. Create an Interface
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

// 3. Make the request
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: "your-token"
)

do {
    let user = try await URLSession.shared.dataTask(
        GetUserInterface.self,
        GetUserInterface.Parameters(userId: 123),
        config
    )
    print("User: \(user.name)")
} catch {
    print("Error: \(error)")
}
```

### POST Request with Body

```swift
struct CreateUserInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .post
        let path = "/users"
        let queryItems: [String: String]? = nil
        let headers: [String: String]? = nil
        let body: Data?
        let authentication: AuthenticationType = .bearer

        init(name: String, email: String) throws {
            let payload = ["name": name, "email": email]
            self.body = try JSONEncoder().encode(payload)
        }
    }

    typealias Response = User

    static var responseCases: ResponseCases {
        [
            201: .success(User.self),
            400: .failure(APIError.invalidInput),
            401: .failure(APIError.unauthorized)
        ]
    }
}

// Usage
let params = try CreateUserInterface.Parameters(
    name: "John Doe",
    email: "john@example.com"
)

let newUser = try await URLSession.shared.dataTask(
    CreateUserInterface.self,
    params,
    config
)
```

### Unauthenticated Request with Query Parameters

```swift
struct SearchInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path = "/search"
        let queryItems: [String: String]?
        let headers: [String: String]? = nil
        let body: Data? = nil
        let authentication: AuthenticationType = .none

        init(query: String, limit: Int = 10) {
            self.queryItems = [
                "q": query,
                "limit": String(limit)
            ]
        }
    }

    struct Response: Codable, Sendable {
        let results: [SearchResult]
        let totalCount: Int
    }

    static var responseCases: ResponseCases {
        [
            200: .success(Response.self)
        ]
    }
}
```

### Working with Different Response Types

```swift
// String response
struct GetMessageInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path = "/message"
        let queryItems: [String: String]? = nil
        let headers: [String: String]? = nil
        let body: Data? = nil
        let authentication: AuthenticationType = .none
    }

    typealias Response = String

    static var responseCases: ResponseCases {
        [200: .success(String.self)]
    }
}

// Binary data response
struct DownloadImageInterface: Interface {
    struct Parameters: RequestParameters {
        let method: RequestMethod = .get
        let path: String
        let queryItems: [String: String]? = nil
        let headers: [String: String]? = nil
        let body: Data? = nil
        let authentication: AuthenticationType = .none
    }

    typealias Response = Data

    static var responseCases: ResponseCases {
        [200: .success(Data.self)]
    }
}
```

---

## Error Handling

RagnarNetworking provides rich error types with helper methods for inspection and debugging.

### Response Errors

```swift
do {
    let user = try await session.dataTask(GetUserInterface.self, params, config)
} catch let error as ResponseError {
    // Access status code
    if let statusCode = error.statusCode {
        print("HTTP Status: \(statusCode)")
    }

    // Get response body as string
    if let body = error.responseBodyString {
        print("Response: \(body)")
    }

    // Decode structured error response
    struct APIError: Codable {
        let message: String
        let errorCode: Int
    }
    if let apiError = error.decodeError(as: APIError.self) {
        print("API Error: \(apiError.message)")
    }

    // Check if retryable (5xx, 429)
    if error.isRetryable {
        print("This request can be retried")
    }

    // Get specific headers
    if let requestId = error.header("X-Request-ID") {
        print("Request ID: \(requestId)")
    }

    // Debug description with all details
    print(error.debugDescription)
}
```

### Error Cases

**ResponseError** - Errors during response processing:
- `.unknownResponse` - Response is not HTTPURLResponse
- `.unknownResponseCase` - Status code not defined in Interface
- `.decoding` - Failed to decode response to expected type
- `.generic` - Predefined error for the status code

**RequestError** - Errors during request construction:
- `.configuration` - Invalid server configuration
- `.authentication` - Required auth token is missing
- `.componentsURL` - Failed to build URL

**InterfaceDecodingError** - Specific decoding failures:
- `.missingString` - Expected String but UTF-8 decoding failed
- `.missingData` - Expected Data but type cast failed
- `.jsonDecoder` - JSON decoding failed

---

## Authentication

RagnarNetworking supports multiple authentication strategies:

### Bearer Token Authentication

```swift
struct Parameters: RequestParameters {
    // ...
    let authentication: AuthenticationType = .bearer
}

let config = ServerConfiguration(
    url: apiURL,
    authToken: "your-bearer-token"
)
// Automatically adds: Authorization: Bearer your-bearer-token
```

### URL Token Authentication

```swift
struct Parameters: RequestParameters {
    // ...
    let authentication: AuthenticationType = .url
}

let config = ServerConfiguration(
    url: apiURL,
    authToken: "your-url-token"
)
// Automatically adds: ?token=your-url-token
```

### No Authentication

```swift
struct Parameters: RequestParameters {
    // ...
    let authentication: AuthenticationType = .none
}
// No token added to request
```

---

## Testing

RagnarNetworking is designed for testability. Use the `DataTaskProvider` protocol to inject mock implementations:

```swift
actor MockDataTaskProvider: DataTaskProvider {
    var mockResponse: (Data, URLResponse)?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let response = mockResponse else {
            throw TestError.noMockSet
        }
        return response
    }
}

// In your tests
let mockProvider = MockDataTaskProvider()
await mockProvider.setMockResponse(
    data: jsonData,
    statusCode: 200,
    url: testURL
)

let result = try await mockProvider.dataTask(
    MyInterface.self,
    params,
    config
)
```
