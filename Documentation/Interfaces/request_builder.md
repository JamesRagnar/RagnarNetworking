# Request Builder Guide

This guide explains how `RequestBuilder` acts as the advanced request-construction extension API for `RagnarNetworking`.

## Overview

`RequestBuilder` defines a step-by-step pipeline for building a `URLRequest` from `RequestParameters` and a `RequestContext`. `URLRequestBuilder` is the built-in implementation, and you can provide your own builder to override only the steps you need; unoverridden steps fall back to the default implementation.

Builders are values, not metatypes, so a builder can carry its own state - a request signer, a tenant prefix, a client identifier - without reaching for globals.

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

`applyHeaders` receives headers already resolved by `ServerConfiguration.resolvedHeaders(for:)`, so the configuration's `defaultHeaders` cannot be dropped by overriding a pipeline step - including `buildRequest` itself.

`applyBody` encodes the request body using the configured `RequestEncoder`, then calls `applyContentType` to apply the inferred `Content-Type`. If a `Content-Type` header already exists, `applyContentType` calls `mediaTypesMatch` to compare it against the inferred value (case-insensitive, ignoring parameters such as `charset`); a mismatch fails request construction with `RequestError.invalidRequest`.

## Scope

A custom builder changes request-construction policy below the Interface definition level: cross-cutting headers, path or query assembly rules, authentication placement rules, or body/header interplay. A plain `RequestParameters` value expresses per-request behavior without a custom builder, and `ServerConfiguration.defaultHeaders` expresses cross-cutting headers without one.

## Override Strategy

Each pipeline step affects a distinct part of request construction:
- `applyHeaders` adds or rewrites headers.
- `applyQueryItems` changes query assembly behavior.
- `applyBody` changes encoding behavior.
- `applyContentType` and `mediaTypesMatch` change how a body's `Content-Type` is applied or compared against an existing header.
- `buildRequest` changes the pipeline itself; the other steps above are called from its default implementation.

For additive behavior, call the corresponding `URLRequestBuilder()` step first and then append your custom logic.

## Builder Invariants

Custom builders should preserve these guarantees unless they are intentionally redefining package behavior:
- successful construction returns a valid `URLRequest`
- request authentication semantics remain coherent with `AuthenticationType`
- body bytes and `Content-Type` stay aligned
- invalid construction still surfaces as `RequestError`
- caller-supplied overrides are handled deliberately and predictably

## Creating a Custom Builder

Create a new type and override only the steps you need.

```swift
struct ClientTaggingBuilder: RequestBuilder {
    let clientID: String

    func applyHeaders(
        _ headers: [String: String],
        authentication: AuthenticationType,
        authToken: String?,
        to request: inout URLRequest
    ) throws(RequestError) {
        try URLRequestBuilder().applyHeaders(
            headers,
            authentication: authentication,
            authToken: authToken,
            to: &request
        )

        var current = request.allHTTPHeaderFields ?? [:]
        current["X-Client"] = clientID
        request.allHTTPHeaderFields = current
    }
}
```

## Using a Custom Builder

Inject a builder into `APIClient` or `RequestPipeline`:

```swift
let client = APIClient(
    configuration: config,
    builder: ClientTaggingBuilder(clientID: "ios"),
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
)
```

```swift
let pipeline = RequestPipeline(
    transport: URLSession.shared,
    builder: ClientTaggingBuilder(clientID: "ios")
)
```

Or build a single request directly:

```swift
let request = try URLRequest(
    GetUserInterface.self,
    .init(userId: 123),
    context: context,
    builder: ClientTaggingBuilder(clientID: "ios")
)
```

## Additional Example

This example preserves the default behavior and then adds a fixed query item to every request:

```swift
struct ClientTaggedQueryBuilder: RequestBuilder {
    func applyQueryItems(
        _ queryItems: [URLQueryItem]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError) {
        try URLRequestBuilder().applyQueryItems(
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
- You can call `URLRequestBuilder()` step methods to reuse the default behavior before adding custom logic.
- `applyBody` uses the `RequestEncoder` factory from the context's configuration to create a per-request encoder.
