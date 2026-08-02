# Request Builder Guide

This guide explains how `RequestBuilder` acts as the request-construction extension API for `RagnarNetworking`.

## Overview

`RequestBuilder` has one requirement:

```swift
func buildRequest<Parameters: RequestParameters>(
    _ requestParameters: Parameters,
    context: RequestContext
) throws(RequestError) -> URLRequest
```

`URLRequestBuilder` is the built-in implementation. It exposes every step of its pipeline as a public method, so a custom builder composes against those steps rather than overriding protocol members.

Builders are values, not metatypes, so a builder can carry its own state - a request signer, a tenant prefix, a client identifier - without reaching for globals.

## Before Writing One

Most problems that look like they need a custom builder do not:

- **Changing how a credential reaches the request** is an `Authenticator` on `ServerConfiguration.authenticators`. See [Authentication](authentication.md).
- **Adding behavior around the whole request/response exchange** - logging, retries, metrics, offline queuing - is a `Transport` decorator. That is this package's middleware seam, the same shape as OpenAPI's `ClientMiddleware`.
- **Cross-cutting headers** are `ServerConfiguration.defaultHeaders`.
- **Per-request behavior** is a plain `RequestParameters` value.

Write a builder when you need to change how a `URLRequest` is *constructed* from its parameters: path joining rules, query assembly, body and header interplay.

## Construction Pipeline

`URLRequestBuilder.buildRequest` runs:

```
makeComponents → applyPath → applyQueryItems → applyAuthentication(to: &components)
  → makeURL → makeRequest → applyMethod → applyHeaders → applyBody
  → applyAuthentication(to: &request)
```

Authentication is two steps rather than one because a URL-carried credential must land before the URL is formed and a header-carried one after, and the pipeline never holds a live `URLComponents` and `URLRequest` at the same time. Each step asks the `Authenticator` registered for the request's scheme what to apply, then applies it. A request declaring no scheme short-circuits with no lookup. Because the builder sees the names before they land, it rejects a credential that would overwrite something the request already carries, a query item name the authenticator does not declare for redaction, or an authenticator that applies nothing at all.

The request-side step runs last, after the body, so a scheme that signs the request can see the method, headers, and body it signs.

`applyHeaders` receives headers already resolved by `ServerConfiguration.resolvedHeaders(for:)`, so the configuration's `defaultHeaders` cannot be dropped by a builder that replaces `buildRequest` wholesale.

`applyBody` encodes the request body using the configured `RequestEncoder`, then calls `applyContentType` to apply the inferred `Content-Type`. If a `Content-Type` header already exists, `applyContentType` calls `mediaTypesMatch` to compare it against the inferred value (case-insensitive, ignoring parameters such as `charset`); a mismatch fails request construction with `RequestError.invalidRequest`.

## Builder Invariants

Custom builders should preserve these guarantees unless they are intentionally redefining package behavior:

- successful construction returns a valid `URLRequest`
- the `Authenticator` registered for the request's `AuthenticationScheme` is applied
- body bytes and `Content-Type` stay aligned
- invalid construction still surfaces as `RequestError`
- caller-supplied overrides are handled deliberately and predictably

## Wrapping the Default Pipeline

The simplest custom builder runs the whole default pipeline and then adjusts the result:

```swift
struct ClientTaggingBuilder: RequestBuilder {
    let clientID: String

    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        var request = try URLRequestBuilder().buildRequest(requestParameters, context: context)

        var current = request.allHTTPHeaderFields ?? [:]
        current["X-Client"] = clientID
        request.allHTTPHeaderFields = current

        return request
    }
}
```

## Changing a Step

To change one step, run the steps before it yourself, then hand off. `finishRequest` runs everything from authentication onward, so a builder that only rewrites the URL never restates header, body, or authentication handling:

```swift
struct TenantPrefixBuilder: RequestBuilder {
    let tenant: String

    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        let base = URLRequestBuilder()

        var components = try base.makeComponents(context: context)
        base.applyPath("/\(tenant)\(requestParameters.path)", to: &components)
        base.applyQueryItems(requestParameters.queryItems, to: &components)
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "client", value: "ios")
        ]

        return try base.finishRequest(
            requestParameters,
            components: components,
            context: context
        )
    }
}
```

## Using a Custom Builder

A builder is part of a server's contract, so it is set on `ServerConfiguration` rather than passed alongside the transport. Everything that reads a configuration then uses it, with no second place to set it and no precedence rule:

```swift
let config = ServerConfiguration(
    url: URL(string: "https://api.example.com")!,
    builder: ClientTaggingBuilder(clientID: "ios")
)
```

```swift
let client = APIClient(
    configuration: config,
    token: { try await keychain.accessToken() },
    refresh: { try await authService.refresh() }
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
