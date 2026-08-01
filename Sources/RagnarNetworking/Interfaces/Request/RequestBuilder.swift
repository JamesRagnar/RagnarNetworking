//
//  RequestBuilder.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation
import OSLog

/// Advanced extension API for constructing `URLRequest` values from typed Interface parameters.
///
/// `RequestBuilder` exposes the request-construction pipeline as a set of stable customization
/// points. `URLRequestBuilder` provides the default implementation, and custom builders can
/// override individual steps while inheriting the rest of the pipeline.
///
/// Builders are values rather than metatypes, so a builder may carry its own state - a request
/// signer, a tenant path prefix, a clock - without reaching for globals.
///
/// Most consumers should use the default `URLRequestBuilder`. Conform to this protocol only when
/// you need to change request construction behavior in a targeted way.
///
/// Recommended override style:
/// - Override the smallest step that solves the problem.
/// - Compose with `URLRequestBuilder` when you want additive behavior.
/// - Reimplement `buildRequest` only when you need to change pipeline ordering or omit steps.
///
/// Builder invariants:
/// - Respect the request's declared `AuthenticationType`.
/// - Preserve explicit `RequestError` failures for malformed configuration or invalid requests.
/// - Keep body bytes and `Content-Type` in sync.
/// - Return a fully formed `URLRequest` with a valid URL.
///
/// - Warning: Do not delegate to `context.builder` from inside a builder. Once a builder is
///   set on `ServerConfiguration`, `context.builder` *is* the builder currently running, so
///   calling it recurses until the stack overflows. To reuse default behavior, construct
///   `URLRequestBuilder()` directly and call the step you want, as the examples below do.
///
/// - Note: `buildRequest` receives headers already resolved by
///   `ServerConfiguration.resolvedHeaders(for:)`, so overriding any pipeline step - including
///   `buildRequest` itself - cannot silently drop the configuration's `defaultHeaders`.
public protocol RequestBuilder: Sendable {

    /// Builds a `URLRequest` using the provided parameters and request context.
    ///
    /// Override this only when you need to change the overall construction flow.
    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest

    /// Creates base `URLComponents` from the request context.
    func makeComponents(
        context: RequestContext
    ) throws(RequestError) -> URLComponents

    /// Applies the request path to the URL components.
    ///
    /// Custom implementations should preserve the default path-joining semantics unless they are
    /// intentionally redefining how interface paths combine with the configured base URL.
    func applyPath(
        _ path: String,
        to components: inout URLComponents
    )

    /// Applies query items and URL authentication parameters.
    ///
    /// Custom implementations should ensure `.url` authentication still has a single final
    /// `token` query item when authentication succeeds.
    func applyQueryItems(
        _ queryItems: [URLQueryItem]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError)

    /// Builds a final URL from the components.
    func makeURL(from components: URLComponents) throws(RequestError) -> URL

    /// Creates the base `URLRequest`.
    func makeRequest(url: URL) -> URLRequest

    /// Applies the HTTP method.
    func applyMethod(
        _ method: RequestMethod,
        to request: inout URLRequest
    )

    /// Applies headers, including authentication.
    ///
    /// `headers` arrives already resolved against the configuration's `defaultHeaders`.
    /// Custom implementations should preserve case-insensitive header semantics and define how
    /// caller-supplied headers interact with generated authentication headers.
    func applyHeaders(
        _ headers: [String: String],
        authentication: AuthenticationType,
        authToken: String?,
        to request: inout URLRequest
    ) throws(RequestError)

    /// Encodes and applies the request body with its content type.
    ///
    /// Custom implementations must keep the encoded body bytes and `Content-Type` header aligned.
    func applyBody<B: RequestBody>(
        _ body: B,
        encoder: RequestEncoder,
        to request: inout URLRequest
    ) throws(RequestError)

    /// Applies a request body's `Content-Type`, called by the default `applyBody`.
    ///
    /// Custom implementations should preserve the existing-header conflict check unless they
    /// are intentionally redefining how a caller-supplied `Content-Type` interacts with the
    /// body's own.
    func applyContentType(
        _ contentType: String?,
        to request: inout URLRequest
    ) throws(RequestError)

    /// Compares two `Content-Type` values for equivalence, ignoring parameters (for example
    /// `charset`) and case. Called by the default `applyContentType`.
    func mediaTypesMatch(_ value1: String, _ value2: String) -> Bool

}

// MARK: - Default Pipeline Implementation

public extension RequestBuilder {

    /// Default pipeline:
    /// `makeComponents` → `applyPath` → `applyQueryItems` → `makeURL` →
    /// `makeRequest` → `applyMethod` → `applyHeaders` → `applyBody`
    func buildRequest<Parameters: RequestParameters>(
        _ requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) -> URLRequest {
        var components = try makeComponents(context: context)
        applyPath(requestParameters.path, to: &components)
        try applyQueryItems(
            requestParameters.queryItems,
            authentication: requestParameters.authentication,
            authToken: context.authToken,
            to: &components
        )

        let url = try makeURL(from: components)
        var request = makeRequest(url: url)
        applyMethod(requestParameters.method, to: &request)

        try applyHeaders(
            context.resolvedHeaders(for: requestParameters),
            authentication: requestParameters.authentication,
            authToken: context.authToken,
            to: &request
        )

        try applyBody(
            requestParameters.body,
            encoder: context.requestEncoder,
            to: &request
        )

        return request
    }

    func makeComponents(
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

    func applyPath(
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

    func applyQueryItems(
        _ queryItems: [URLQueryItem]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError) {
        var currentQueryItems = components.queryItems ?? []

        if case .url = authentication {
            if currentQueryItems.contains(where: {
                $0.name.caseInsensitiveCompare("token") == .orderedSame
            }) {
                Logger.diagnostics.warning(
                    "RagnarNetworking: URL authentication overrides an existing 'token' query item from the base URL."
                )
            }
            currentQueryItems.removeAll {
                $0.name.caseInsensitiveCompare("token") == .orderedSame
            }
        }

        let newQueryItems: [URLQueryItem]?
        if case .url = authentication {
            if queryItems?.contains(where: {
                $0.name.caseInsensitiveCompare("token") == .orderedSame
            }) == true {
                Logger.diagnostics.warning(
                    "RagnarNetworking: URL auth overrides a 'token' query param in request parameters."
                )
            }
            newQueryItems = queryItems?
                .filter { $0.name.caseInsensitiveCompare("token") != .orderedSame }
        } else {
            newQueryItems = queryItems
        }

        if let newQueryItems {
            currentQueryItems.append(contentsOf: newQueryItems)
        }

        if case .url = authentication {
            guard let token = authToken else {
                throw .authentication
            }

            currentQueryItems.append(
                URLQueryItem(
                    name: "token",
                    value: token
                )
            )
        }

        components.queryItems = currentQueryItems.isEmpty ? nil : currentQueryItems
    }

    func makeURL(from components: URLComponents) throws(RequestError) -> URL {
        guard let url = components.url else {
            throw .componentsURL
        }

        return url
    }

    func makeRequest(url: URL) -> URLRequest {
        URLRequest(url: url)
    }

    func applyMethod(_ method: RequestMethod, to request: inout URLRequest) {
        request.httpMethod = method.rawValue
    }

    func applyHeaders(
        _ headers: [String: String],
        authentication: AuthenticationType,
        authToken: String?,
        to request: inout URLRequest
    ) throws(RequestError) {
        var currentHeaderFields = request.allHTTPHeaderFields ?? [:]

        if case .bearer = authentication {
            guard let token = authToken else {
                throw .authentication
            }

            currentHeaderFields["Authorization"] = "Bearer \(token)"
        }

        for (key, value) in headers {
            if key.caseInsensitiveCompare("Authorization") == .orderedSame {
                if case .bearer = authentication {
                    Logger.diagnostics.warning(
                        "RagnarNetworking: custom Authorization header overrides bearer auth for this request."
                    )
                }
                currentHeaderFields = currentHeaderFields.filter {
                    $0.key.caseInsensitiveCompare("Authorization") != .orderedSame
                }
            }
            currentHeaderFields[key] = value
        }

        request.allHTTPHeaderFields = currentHeaderFields
    }

    func applyBody<B: RequestBody>(
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

    func applyContentType(
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

    func mediaTypesMatch(_ value1: String, _ value2: String) -> Bool {
        func extractMediaType(_ value: String) -> String {
            let mediaType = value.split(separator: ";").first ?? Substring(value)
            return mediaType.trimmingCharacters(in: .whitespaces).lowercased()
        }

        return extractMediaType(value1) == extractMediaType(value2)
    }

}

// MARK: - Default Builder

/// The built-in `RequestBuilder`, using the default pipeline unchanged.
public struct URLRequestBuilder: RequestBuilder {

    /// Creates the default builder. Stateless; create one wherever you need it, including
    /// inside a custom builder that delegates to a default pipeline step.
    public init() {}

}
