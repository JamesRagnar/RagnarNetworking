//
//  InterfaceConstructor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

/// Advanced extension API for constructing `URLRequest` values from typed Interface parameters.
///
/// `InterfaceConstructor` exposes the request-construction pipeline as a set of stable
/// customization points. `URLRequest` provides the default implementation, and custom
/// constructors can override individual steps while inheriting the rest of the pipeline.
///
/// Most consumers should use the default `URLRequest` constructor path. Conform to this
/// protocol only when you need to change request construction behavior in a targeted way.
///
/// Recommended override style:
/// - Override the smallest step that solves the problem.
/// - Call the default `URLRequest` implementation first when you want additive behavior.
/// - Reimplement `buildRequest` only when you need to change pipeline ordering or omit steps.
///
/// Constructor invariants:
/// - Respect the request's declared `AuthenticationType`.
/// - Preserve explicit `RequestError` failures for malformed configuration or invalid requests.
/// - Keep body bytes and `Content-Type` in sync.
/// - Return a fully formed `URLRequest` with a valid URL.
public protocol InterfaceConstructor {

    /// Builds a `URLRequest` using the provided parameters and server configuration.
    ///
    /// Override this only when you need to change the overall construction flow.
    static func buildRequest<Parameters: RequestParameters>(
        requestParameters: Parameters,
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) -> URLRequest

    /// Creates base `URLComponents` from the server configuration.
    static func makeComponents(
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) -> URLComponents

    /// Applies the request path to the URL components.
    ///
    /// Custom implementations should preserve the default path-joining semantics unless they are
    /// intentionally redefining how interface paths combine with the configured base URL.
    static func applyPath(
        _ path: String,
        to components: inout URLComponents
    )

    /// Applies query items and URL authentication parameters.
    ///
    /// Custom implementations should ensure `.url` authentication still has a single final
    /// `token` query item when authentication succeeds.
    static func applyQueryItems(
        _ queryItems: [String: String?]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError)

    /// Builds a final URL from the components.
    static func makeURL(from components: URLComponents) throws(RequestError) -> URL

    /// Creates the base `URLRequest`.
    static func makeRequest(url: URL) -> URLRequest

    /// Applies the HTTP method.
    static func applyMethod(
        _ method: RequestMethod,
        to request: inout URLRequest
    )

    /// Applies headers, including authentication.
    ///
    /// Custom implementations should preserve case-insensitive header semantics and define how
    /// caller-supplied headers interact with generated authentication headers.
    static func applyHeaders(
        _ headers: [String: String]?,
        authentication: AuthenticationType,
        authToken: String?,
        to request: inout URLRequest
    ) throws(RequestError)

    /// Encodes and applies the request body with its content type.
    ///
    /// Custom implementations must keep the encoded body bytes and `Content-Type` header aligned.
    static func applyBody<B: RequestBody>(
        _ body: B,
        encoder: RequestEncoder,
        to request: inout URLRequest
    ) throws(RequestError)

}

// MARK: - Default Pipeline Implementation

public extension InterfaceConstructor {

    /// Default pipeline:
    /// `makeComponents` → `applyPath` → `applyQueryItems` → `makeURL` →
    /// `makeRequest` → `applyMethod` → `applyHeaders` → `applyBody`
    static func buildRequest<Parameters: RequestParameters>(
        requestParameters: Parameters,
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) -> URLRequest {
        var components = try makeComponents(serverConfiguration: serverConfiguration)
        applyPath(requestParameters.path, to: &components)
        try applyQueryItems(
            requestParameters.queryItems,
            authentication: requestParameters.authentication,
            authToken: serverConfiguration.authToken,
            to: &components
        )

        let url = try makeURL(from: components)
        var request = makeRequest(url: url)
        applyMethod(requestParameters.method, to: &request)

        try applyHeaders(
            requestParameters.headers,
            authentication: requestParameters.authentication,
            authToken: serverConfiguration.authToken,
            to: &request
        )

        try applyBody(
            requestParameters.body,
            encoder: serverConfiguration.requestEncoder,
            to: &request
        )

        return request
    }

    static func makeComponents(
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) -> URLComponents {
        guard let components = URLComponents(
            url: serverConfiguration.url,
            resolvingAgainstBaseURL: false
        ) else {
            throw .configuration
        }

        return components
    }

    static func applyPath(
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

    static func applyQueryItems(
        _ queryItems: [String: String?]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError) {
        var currentQueryItems = components.queryItems ?? []

        if case .url = authentication {
            if currentQueryItems.contains(where: {
                $0.name.caseInsensitiveCompare("token") == .orderedSame
            }) {
                rnDiagnostic(
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
                $0.key.caseInsensitiveCompare("token") == .orderedSame
            }) == true {
                rnDiagnostic(
                    "RagnarNetworking: URL authentication overrides a 'token' query item provided in request parameters."
                )
            }
            newQueryItems = queryItems?
                .filter { $0.key.caseInsensitiveCompare("token") != .orderedSame }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        } else {
            newQueryItems = queryItems?
                .map { URLQueryItem(name: $0.key, value: $0.value) }
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

    static func makeURL(from components: URLComponents) throws(RequestError) -> URL {
        guard let url = components.url else {
            throw .componentsURL
        }

        return url
    }

    static func makeRequest(url: URL) -> URLRequest {
        URLRequest(url: url)
    }

    static func applyMethod(_ method: RequestMethod, to request: inout URLRequest) {
        request.httpMethod = method.rawValue
    }

    static func applyHeaders(
        _ headers: [String: String]?,
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

        if let newHeaderFields = headers {
            for (key, value) in newHeaderFields {
                if key.caseInsensitiveCompare("Authorization") == .orderedSame {
                    if case .bearer = authentication {
                        rnDiagnostic(
                            "RagnarNetworking: custom Authorization header overrides bearer authentication for this request."
                        )
                    }
                    currentHeaderFields = currentHeaderFields.filter {
                        $0.key.caseInsensitiveCompare("Authorization") != .orderedSame
                    }
                }
                currentHeaderFields[key] = value
            }
        }

        request.allHTTPHeaderFields = currentHeaderFields
    }

    static func applyBody<B: RequestBody>(
        _ body: B,
        encoder: RequestEncoder,
        to request: inout URLRequest
    ) throws(RequestError) {
        let jsonEncoder = encoder.makeJSONEncoder()

        let encoded: EncodedBody
        do {
            encoded = try body.encodeBody(using: jsonEncoder)
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

    static func applyContentType(
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

    static func mediaTypesMatch(_ value1: String, _ value2: String) -> Bool {
        func extractMediaType(_ value: String) -> String {
            let mediaType = value.split(separator: ";").first ?? Substring(value)
            return mediaType.trimmingCharacters(in: .whitespaces).lowercased()
        }

        return extractMediaType(value1) == extractMediaType(value2)
    }

}
