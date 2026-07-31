# Interface Constructor Guide

This guide explains how `InterfaceConstructor` acts as the advanced request-construction extension API for `RagnarNetworking`.

## Overview

`InterfaceConstructor` defines a step-by-step pipeline for building a `URLRequest` from `RequestParameters` and `ServerConfiguration`. `URLRequest` conforms by default, and you can provide your own constructor type to override only the steps you need; unoverridden steps fall back to the default implementation.

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

`applyBody` encodes the request body using the configured `RequestEncoder`, then calls `applyContentType` to apply the inferred `Content-Type`. If a `Content-Type` header already exists, `applyContentType` calls `mediaTypesMatch` to compare it against the inferred value (case-insensitive, ignoring parameters such as `charset`); a mismatch fails request construction with `RequestError.invalidRequest`.

## Scope

A custom constructor changes request-construction policy below the Interface definition level: cross-cutting headers, path or query assembly rules, authentication placement rules, or body/header interplay. A plain `RequestParameters` value expresses per-request behavior without a custom constructor.

## Override Strategy

Each pipeline step affects a distinct part of request construction:
- `applyHeaders` adds or rewrites headers.
- `applyQueryItems` changes query assembly behavior.
- `applyBody` changes encoding behavior.
- `applyContentType` and `mediaTypesMatch` change how a body's `Content-Type` is applied or compared against an existing header.
- `buildRequest` changes the pipeline itself; the other steps above are called from its default implementation.

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
        _ queryItems: [URLQueryItem]?,
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
