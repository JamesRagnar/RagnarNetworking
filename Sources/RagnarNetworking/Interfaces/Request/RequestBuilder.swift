//
//  RequestBuilder.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

/// Constructs a `URLRequest` from typed Interface parameters.
///
/// `URLRequestBuilder` is the built-in implementation and exposes each step of its pipeline as a
/// public method, so a custom builder composes against those steps rather than inheriting them.
///
/// Builders are values rather than metatypes, so a builder may carry its own state - a request
/// signer, a tenant path prefix, a clock.
///
/// Narrower seams cover most cases: register an `Authenticator` to change how a credential
/// reaches the request, decorate the `Transport` to add behavior around the whole exchange, and
/// set `ServerConfiguration.defaultHeaders` for cross-cutting headers. Conform here to change
/// how a `URLRequest` is constructed from its request: path joining, query assembly, body
/// and header interplay.
///
/// A builder that wants the default pipeline plus a targeted change delegates to
/// `URLRequestBuilder`'s steps:
///
/// ```swift
/// struct TenantPrefixBuilder: RequestBuilder {
///     let tenant: String
///     private let base = URLRequestBuilder()
///
///     func buildRequest<Request: InterfaceRequest>(
///         _ interfaceRequest: Request,
///         context: RequestContext
///     ) throws(RequestError) -> URLRequest {
///         var components = try base.makeComponents(context: context)
///         base.applyPath("/\(tenant)\(interfaceRequest.path)", to: &components)
///         base.applyQueryItems(interfaceRequest.queryItems, to: &components)
///         return try base.finishRequest(interfaceRequest, components: components, context: context)
///     }
/// }
/// ```
///
/// A builder returns an unauthenticated request.
/// `URLRequest.init(interfaceRequest:context:)` applies the credential afterward.
///
/// Builder invariants:
/// - Preserve explicit `RequestError` failures for malformed configuration or invalid requests.
/// - Keep body bytes and `Content-Type` in sync.
/// - Return a fully formed `URLRequest` with a valid URL.
///
/// - Warning: Do not delegate to `context.builder` from inside a builder. Once set on
///   `ServerConfiguration`, `context.builder` is the builder currently running, so calling it
///   recurses until the stack overflows. Construct `URLRequestBuilder()` directly instead.
///
/// - Note: Resolve headers through `context.resolvedHeaders(for:)` rather than reading
///   `request.headers` directly, so the configuration's `defaultHeaders` cannot be dropped.
public protocol RequestBuilder: Sendable {

    /// Builds a `URLRequest` from the request and request context.
    func buildRequest<Request: InterfaceRequest>(
        _ interfaceRequest: Request,
        context: RequestContext
    ) throws(RequestError) -> URLRequest

}

// MARK: - Default Builder

/// The built-in `RequestBuilder`. Each pipeline step is a public method, so a custom builder can
/// reuse the parts it does not change.
///
/// ```
/// makeComponents → applyPath → applyQueryItems → makeURL
///   → makeRequest → applyMethod → applyHeaders → applyBody
/// ```
///
/// No step here applies a credential. `URLRequest.init(interfaceRequest:context:)` runs
/// `URLRequest.applyAuthentication(_:context:)` on the finished request, so an authenticator
/// reads the final URL, method, headers, and body. See `Authenticator`.
public struct URLRequestBuilder: RequestBuilder {

    /// Creates the default builder. Stateless; create one wherever you need it, including
    /// inside a custom builder that delegates to a default pipeline step.
    public init() {}

    public func buildRequest<Request: InterfaceRequest>(
        _ interfaceRequest: Request,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        var components = try makeComponents(context: context)
        applyPath(interfaceRequest.path, to: &components)
        applyQueryItems(interfaceRequest.queryItems, to: &components)

        return try finishRequest(
            interfaceRequest,
            components: components,
            context: context
        )
    }

    /// Runs every pipeline step from URL assembly onward, given components whose base URL,
    /// path, and query items are already applied.
    ///
    /// For a custom builder that only changes URL assembly: build the components, then hand
    /// them here rather than reimplementing header and body handling.
    public func finishRequest<Request: InterfaceRequest>(
        _ interfaceRequest: Request,
        components: URLComponents,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        let url = try makeURL(from: components)
        var request = makeRequest(url: url)
        applyMethod(interfaceRequest.method, to: &request)

        applyHeaders(
            context.resolvedHeaders(for: interfaceRequest),
            to: &request
        )

        try applyBody(
            interfaceRequest.body,
            encoder: context.requestEncoder,
            to: &request
        )

        return request
    }

    /// Creates base `URLComponents` from the request context.
    public func makeComponents(
        context: RequestContext
    ) throws(RequestError) -> URLComponents {
        guard let components = URLComponents(
            url: context.url,
            resolvingAgainstBaseURL: false
        ) else {
            throw .configuration
        }

        return components
    }

    /// Joins the request path onto the configured base URL's path.
    public func applyPath(
        _ path: String,
        to components: inout URLComponents
    ) {
        let basePath = components.path
        if basePath.isEmpty || basePath == "/" {
            if path.hasPrefix("/") {
                components.path = path
            } else {
                components.path = "/" + path
            }
            return
        }

        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if trimmedPath.isEmpty {
            components.path = trimmedBase
        } else {
            components.path = "\(trimmedBase)/\(trimmedPath)"
        }
    }

    /// Appends the request's own query items to any carried by the base URL.
    ///
    /// A URL-carried credential is appended after the whole request is built, by
    /// `URLRequest.applyAuthentication(_:context:)`.
    public func applyQueryItems(
        _ queryItems: [URLQueryItem]?,
        to components: inout URLComponents
    ) {
        var currentQueryItems = components.queryItems ?? []

        if let queryItems {
            currentQueryItems.append(contentsOf: queryItems)
        }

        components.queryItems = currentQueryItems.isEmpty ? nil : currentQueryItems
    }

    /// Builds a final URL from the components.
    public func makeURL(from components: URLComponents) throws(RequestError) -> URL {
        guard let url = components.url else {
            throw .componentsURL
        }

        return url
    }

    /// Creates the base `URLRequest`.
    public func makeRequest(url: URL) -> URLRequest {
        URLRequest(url: url)
    }

    /// Applies the HTTP method.
    public func applyMethod(_ method: RequestMethod, to request: inout URLRequest) {
        request.httpMethod = method.rawValue
    }

    /// Applies headers, matched case-insensitively.
    ///
    /// `headers` arrives resolved against `defaultHeaders` by
    /// `RequestContext.resolvedHeaders(for:)`. A header-carried credential is applied after the
    /// whole request is built, by `URLRequest.applyAuthentication(_:context:)`.
    public func applyHeaders(
        _ headers: [String: String],
        to request: inout URLRequest
    ) {
        var currentHeaderFields = request.allHTTPHeaderFields ?? [:]

        for (key, value) in headers {
            currentHeaderFields = currentHeaderFields.filter {
                $0.key.caseInsensitiveCompare(key) != .orderedSame
            }
            currentHeaderFields[key] = value
        }

        request.allHTTPHeaderFields = currentHeaderFields
    }

    /// Encodes and applies the request body with its content type.
    public func applyBody<B: RequestBody>(
        _ body: B,
        encoder: RequestEncoder,
        to request: inout URLRequest
    ) throws(RequestError) {
        let encoded: EncodedBody
        do {
            encoded = try body.encodeBody(using: encoder)
        } catch {
            throw RequestError.encoding(underlying: ErrorSnapshot(error))
        }

        guard !encoded.data.isEmpty || encoded.contentType != nil else {
            return
        }

        if !encoded.data.isEmpty && encoded.contentType == nil {
            throw RequestError.invalidRequest(
                description: "Request body produced data without a Content-Type"
            )
        }

        request.httpBody = encoded.data
        try applyContentType(encoded.contentType, to: &request)
    }

    /// Applies a request body's `Content-Type`, called by `applyBody`.
    ///
    /// A caller-supplied `Content-Type` disagreeing with the body's own throws
    /// `RequestError.invalidRequest`.
    public func applyContentType(
        _ contentType: String?,
        to request: inout URLRequest
    ) throws(RequestError) {
        guard let contentType else { return }

        var currentHeaderFields = request.allHTTPHeaderFields ?? [:]

        if let existingKey = currentHeaderFields.keys.first(where: {
            $0.caseInsensitiveCompare("Content-Type") == .orderedSame
        }) {
            let existingValue = currentHeaderFields[existingKey] ?? ""
            if !mediaTypesMatch(existingValue, contentType) {
                throw RequestError.invalidRequest(
                    description: "Content-Type mismatch: existing '\(existingValue)' conflicts with '\(contentType)'"
                )
            }
            return
        }

        currentHeaderFields["Content-Type"] = contentType
        request.allHTTPHeaderFields = currentHeaderFields
    }

    /// Compares two `Content-Type` values for equivalence, ignoring parameters (for example
    /// `charset`) and case. Called by `applyContentType`.
    public func mediaTypesMatch(_ value1: String, _ value2: String) -> Bool {
        func extractMediaType(_ value: String) -> String {
            let mediaType = value.split(separator: ";").first ?? Substring(value)
            return mediaType.trimmingCharacters(in: .whitespaces).lowercased()
        }

        return extractMediaType(value1) == extractMediaType(value2)
    }

}
