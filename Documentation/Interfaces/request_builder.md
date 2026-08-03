# Request Builder Guide

This guide explains how `RequestBuilder` acts as the request-construction extension API for `RagnarNetworking`.

## Overview

`RequestBuilder` has one requirement:

```swift
func buildRequest<Request: InterfaceRequest>(
    _ interfaceRequest: Request,
    context: RequestContext
) throws(RequestError) -> URLRequest
```

`URLRequestBuilder` is the built-in implementation. It exposes every step of its pipeline as a public method, so a custom builder composes against those steps rather than overriding protocol members.

Builders are values, not metatypes, so a builder can carry its own state - a request signer, a tenant prefix, a client identifier - without reaching for globals.

## Narrower Seams

- **How a credential reaches the request** is an `Authenticator` on `ServerConfiguration.authenticators`. See [Authentication](authentication.md).
- **Behavior around the whole request/response exchange** - logging, retries, metrics, offline queuing, request signing - is a `Transport` decorator, this package's middleware seam. See [Transport Decoration](../request_pipeline.md#transport-decoration).
- **Cross-cutting headers** are `ServerConfiguration.defaultHeaders`.
- **Per-request behavior** is a plain `InterfaceRequest` value.

Write a builder to change how a `URLRequest` is constructed from its parameters: path joining, query assembly, body and header interplay.

## Construction Pipeline

`URLRequestBuilder.buildRequest` runs:

```
makeComponents → applyPath → applyQueryItems → makeURL
  → makeRequest → applyMethod → applyHeaders → applyBody
```

`applyHeaders` receives headers already resolved by `ServerConfiguration.resolvedHeaders(for:)`, so the configuration's `defaultHeaders` cannot be dropped by a builder that replaces `buildRequest` wholesale.

`applyBody` encodes the request body using the configured `RequestEncoder`, then calls `applyContentType` to apply the inferred `Content-Type`. If a `Content-Type` header already exists, `applyContentType` calls `mediaTypesMatch` to compare it against the inferred value (case-insensitive, ignoring parameters such as `charset`); a mismatch fails request construction with `RequestError.invalidRequest`.

## Authentication

No builder step applies a credential. `URLRequest.init(interfaceRequest:context:)` runs two things in order: the configuration's builder, then `URLRequest.applyAuthentication(_:context:)` on the request it returned. A builder that never mentions `AuthenticationScheme` still produces authenticated requests.

The authenticator therefore reads the final URL, method, headers, and body. Query items land before header fields, so a signing `headers(for:on:)` sees the URL its own `queryItems(for:on:)` produced.

Both sides are validated before anything is written: a query item outside the authenticator's `redactedQueryItemNames`, a name the request already carries, and an authenticator that contributes nothing all fail construction. See [Authentication](authentication.md).

## Builder Invariants

Custom builders should preserve these guarantees unless they are intentionally redefining package behavior:

- successful construction returns a valid `URLRequest` with a valid URL
- body bytes and `Content-Type` stay aligned
- invalid construction still surfaces as `RequestError`
- caller-supplied overrides are handled deliberately and predictably

## Wrapping the Default Pipeline

Run the default pipeline, then adjust the result:

```swift
struct ClientTaggingBuilder: RequestBuilder {
    let clientID: String

    func buildRequest<Request: InterfaceRequest>(
        _ interfaceRequest: Request,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        var request = try URLRequestBuilder().buildRequest(interfaceRequest, context: context)

        var current = request.allHTTPHeaderFields ?? [:]
        current["X-Client"] = clientID
        request.allHTTPHeaderFields = current

        return request
    }
}
```

## Changing a Step

Run the steps before it, then hand off. `finishRequest` runs everything from URL assembly onward, so a builder that only rewrites the URL does not restate header or body handling:

```swift
struct TenantPrefixBuilder: RequestBuilder {
    let tenant: String

    func buildRequest<Request: InterfaceRequest>(
        _ interfaceRequest: Request,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        let base = URLRequestBuilder()

        var components = try base.makeComponents(context: context)
        base.applyPath("/\(tenant)\(interfaceRequest.path)", to: &components)
        base.applyQueryItems(interfaceRequest.queryItems, to: &components)
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "client", value: "ios")
        ]

        return try base.finishRequest(
            interfaceRequest,
            components: components,
            context: context
        )
    }
}
```

## Using a Custom Builder

A builder is part of a server's contract, so it is set on `ServerConfiguration` rather than passed alongside the transport. There is no second place to set it and no precedence rule:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    builder: ClientTaggingBuilder(clientID: "ios")
)
```

```swift
let client = APIClient(
    configuration: config,
    credentialSource: .refreshing(
        read: { try await keychain.accessToken() },
        refresh: { try await authService.refresh() }
    )
)
```

```swift
let pipeline = RequestPipeline(transport: URLSession.shared)
let context = RequestContext(configuration: config, credential: token)
```

Or build a single request directly, which uses the context's configured builder:

```swift
let request = try URLRequest(
    GetUserInterface.self,
    .init(userId: 123),
    context: context
)
```

## Notes

- Do not call `context.builder` from inside a builder. Once set on `ServerConfiguration`, that is the builder currently running, so it recurses until the stack overflows. Construct `URLRequestBuilder()` directly instead.
- `applyBody` uses the `RequestEncoder` factory from the context's configuration to create a per-request encoder.
