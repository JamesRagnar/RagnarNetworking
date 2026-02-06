# Interfaces

This directory documents the Interfaces system: how requests are defined, constructed, executed, and decoded.

## Overview

An `Interface` pairs request parameters with response handling. Most usage follows this flow:
1. Define `Interface` and nested `Parameters`.
2. Create a `ServerConfiguration`.
3. Execute via `DataTaskProvider` or `RequestService`.

## Example

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
            .code(404, .error(APIError.userNotFound))
        ]
    }
}

let user = try await URLSession.shared.dataTask(
    GetUserInterface.self,
    .init(userId: 123),
    config
)
```

`config` comes from:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    authToken: token
)
```

## Response Cases Notes

- Use `.code` for exact status codes.
- Use `.range` or `.success`/`.clientError`/`.serverError` for ranges.
- `.decodeError(MyError.self)` decodes structured error bodies and throws `ResponseError.decoded`.
- Use `.noContent` for no-body success (204/205/304), and prefer `handleOutcome(_:)` when you need to distinguish it from decoded responses.

## Status Code Guidelines

Recommended defaults for Interface definitions:

- `200 OK`: `.code(200, .decode)`
- `201 Created`: `.code(201, .decode)` when the server returns the created resource
- `202 Accepted`: use `.code(202, .noContent)` or map to a custom response type if the server returns status info
- `204 No Content`: `.code(204, .noContent)`
- `205 Reset Content`: `.code(205, .noContent)`
- `206 Partial Content`: `.code(206, .decode)` with `Response = Data`
- `304 Not Modified`: `.code(304, .noContent)` if you opt into conditional requests

Prefer explicit success codes. Use success ranges only when the endpoint truly varies and your `Response` can safely handle empty bodies.

## Guides

- [Request Parameters](request_parameters.md)
- [Response Handling](response_handling.md)
- [DataTaskProvider](data_task_provider.md)
- [Server Configuration](server_configuration.md)
- [Interface Constructor](interface_constructor.md)
