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

## When to Use It

Use a custom builder when you need request-construction policy that should live below the Interface definition level, for example:
- injecting cross-cutting headers
- changing path or query assembly rules
- adjusting authentication placement rules
- customizing body/header interplay

Do not reach for this when a plain `RequestParameters` value or `ServerConfiguration.defaultHeaders` already expresses the behavior you need.

## Override Strategy

Prefer the narrowest possible override:
- Override `applyHeaders` to add or rewrite headers.
- Override `applyQueryItems` to change query assembly behavior.
- Override `applyBody` to change encoding behavior.
- Override `applyContentType` or `mediaTypesMatch` to change how a body's `Content-Type` is applied or compared against an existing header.
- Override `buildRequest` only when you need to change the pipeline itself.

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
- Treat this as an advanced customization API. Most consumers should stay on the default `URLRequestBuilder` path.
