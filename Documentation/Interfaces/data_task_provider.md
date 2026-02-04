# DataTaskProvider

`DataTaskProvider` abstracts request execution and is the primary entry point for making Interface-driven requests.

## Default Usage

```swift
let response = try await URLSession.shared.dataTask(
    MyInterface.self,
    params,
    config
)
```

## Custom Request Construction

You can inject a custom `InterfaceConstructor` to override how requests are built.

```swift
struct CustomConstructor: InterfaceConstructor {
    static func applyHeaders(
        _ headers: [String: String]?,
        authentication: AuthenticationType,
        authToken: String?,
        to request: inout URLRequest
    ) throws(RequestError) {
        try URLRequest.applyHeaders(
            headers,
            authentication: authentication,
            authToken: authToken,
            to: &request
        )

        var current = request.allHTTPHeaderFields ?? [:]
        current["X-Client"] = "ios"
        request.allHTTPHeaderFields = current
    }
}

let response = try await URLSession.shared.dataTask(
    MyInterface.self,
    params,
    config,
    constructor: CustomConstructor.self
)
```

## Testing

You can implement `DataTaskProvider` in a mock to control responses without making real network calls.
