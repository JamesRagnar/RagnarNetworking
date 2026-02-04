# Interface Constructor Guide

This guide explains how `InterfaceConstructor` builds requests and how to override specific steps for custom behavior.

## Overview

`InterfaceConstructor` defines a step-by-step pipeline for building a `URLRequest` from `RequestParameters` and `ServerConfiguration`. `URLRequest` conforms by default, and you can provide your own constructor type to override only the steps you need.

Key benefits:
- Consistent, well-structured request construction
- Safe defaults for standard behavior
- Targeted overrides for advanced customization

## Construction Pipeline

The default pipeline is:
- `makeComponents`
- `applyPath`
- `applyQueryItems`
- `makeURL`
- `makeRequest`
- `applyMethod`
- `applyHeaders`
- `applyBody`

`applyBody` encodes the request body using the configured `RequestEncoder` and applies the inferred `Content-Type`. If a `Content-Type` header already exists, the media types must match (case-insensitive) or request construction will fail with `RequestError.invalidRequest`.

## Creating a Custom Constructor

Create a new type and override only the steps you need.

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
```

## Using a Custom Constructor

You can inject a constructor at the call site or the service level.

### DataTaskProvider

```swift
let user = try await URLSession.shared.dataTask(
    GetUserInterface.self,
    .init(userId: 123),
    config,
    constructor: CustomConstructor.self
)
```

### RequestService

```swift
let user = try await service.dataTask(
    GetUserInterface.self,
    .init(userId: 123),
    constructor: CustomConstructor.self
)
```

### InterceptableRequestService

```swift
let service = InterceptableRequestService(
    configurationProvider: { config },
    interceptors: [],
    constructor: CustomConstructor.self
)
```

## Notes

- You do not need to reimplement `buildRequest` unless you want to change the overall flow.
- Overridden methods are used automatically by the default `buildRequest` implementation.
- You can call `URLRequest` step methods to reuse the default behavior before adding custom logic.
- `applyBody` uses the `RequestEncoder` factory from `ServerConfiguration` to create a per-request encoder.
