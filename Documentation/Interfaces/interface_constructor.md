# Interface Constructor Guide

This guide explains how `InterfaceConstructor` acts as the advanced request-construction extension API for `RagnarNetworking`.

## Overview

`InterfaceConstructor` defines a stable, step-by-step pipeline for building a `URLRequest` from `RequestParameters` and `ServerConfiguration`. `URLRequest` conforms by default, and you can provide your own constructor type to override only the steps you need.

Key benefits:
- Consistent, well-structured request construction
- Safe defaults for standard behavior
- Targeted overrides for advanced customization
- A clear extension seam for package consumers who need transport-level policy changes

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

## When to Use It

Use a custom constructor when you need request-construction policy that should live below the Interface definition level, for example:
- injecting cross-cutting headers
- changing path or query assembly rules
- adjusting authentication placement rules
- customizing body/header interplay

Do not reach for this when a plain `RequestParameters` value already expresses the behavior you need.

## Override Strategy

Prefer the narrowest possible override:
- Override `applyHeaders` to add or rewrite headers.
- Override `applyQueryItems` to change query assembly behavior.
- Override `applyBody` to change encoding or content-type handling.
- Override `buildRequest` only when you need to change the pipeline itself.

For additive behavior, call the default `URLRequest` step implementation first and then append your custom logic.

## Constructor Invariants

Custom constructors should preserve these guarantees unless they are intentionally redefining package behavior:
- successful construction returns a valid `URLRequest`
- request authentication semantics remain coherent with `AuthenticationType`
- body bytes and `Content-Type` stay aligned
- invalid construction still surfaces as `RequestError`
- caller-supplied overrides are handled deliberately and predictably

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

Inject a constructor at the `DataTaskProvider` call site.

```swift
let user = try await URLSession.shared.dataTask(
    GetUserInterface.self,
    .init(userId: 123),
    config,
    constructor: CustomConstructor.self
)
```

## Additional Example

This example preserves the default behavior and then adds a fixed query item to every request:

```swift
struct ClientTaggedConstructor: InterfaceConstructor {
    static func applyQueryItems(
        _ queryItems: [String: String?]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError) {
        try URLRequest.applyQueryItems(
            queryItems,
            authentication: authentication,
            authToken: authToken,
            to: &components
        )

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "client", value: "ios"))
        components.queryItems = items
    }
}
```

## Notes

- You do not need to reimplement `buildRequest` unless you want to change the overall flow.
- Overridden methods are used automatically by the default `buildRequest` implementation.
- You can call `URLRequest` step methods to reuse the default behavior before adding custom logic.
- `applyBody` uses the `RequestEncoder` factory from `ServerConfiguration` to create a per-request encoder.
- Treat this as an advanced customization API. Most consumers should stay on the default `URLRequest` constructor path.
