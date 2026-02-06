//
//  InterfaceConstructor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

/// Defines the steps required to construct a URLRequest from Interface parameters.
public protocol InterfaceConstructor {

    /// Builds a URLRequest using the provided parameters and configuration.
    static func buildRequest<Parameters: RequestParameters>(
        requestParameters: Parameters,
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) -> URLRequest

    /// Creates URL components from the server configuration.
    static func makeComponents(
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) -> URLComponents

    /// Applies the request path to the URL components.
    static func applyPath(
        _ path: String,
        to components: inout URLComponents
    )

    /// Applies query items and URL authentication parameters.
    static func applyQueryItems(
        _ queryItems: [String: String?]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError)

    /// Builds a URL from the components.
    static func makeURL(from components: URLComponents) throws(RequestError) -> URL

    /// Creates the base URLRequest.
    static func makeRequest(url: URL) -> URLRequest

    /// Applies the HTTP method.
    static func applyMethod(
        _ method: RequestMethod,
        to request: inout URLRequest
    )

    /// Applies headers, including authentication.
    static func applyHeaders(
        _ headers: [String: String]?,
        authentication: AuthenticationType,
        authToken: String?,
        to request: inout URLRequest
    ) throws(RequestError)

    /// Encodes and applies the request body with its content type.
    static func applyBody<B: RequestBody>(
        _ body: B,
        encoder: RequestEncoder,
        to request: inout URLRequest
    ) throws(RequestError)

}

// MARK: - Default InterfaceConstructor Implementation

public extension InterfaceConstructor {

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

        if let body = requestParameters.body {
            try applyBody(body, encoder: serverConfiguration.requestEncoder, to: &request)
        }

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
            currentQueryItems.removeAll {
                $0.name.caseInsensitiveCompare("token") == .orderedSame
            }
        }

        let newQueryItems: [URLQueryItem]?
        if case .url = authentication {
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
            throw RequestError.encoding(message: String(describing: error))
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
