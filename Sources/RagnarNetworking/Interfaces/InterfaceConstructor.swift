//
//  InterfaceConstructor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-12-22.
//

import Foundation

// MARK: - Request Error

/// Errors that can occur during URLRequest construction.
public enum RequestError: Error {

    /// The server configuration could not be parsed or is malformed
    case configuration

    /// The request requires authentication but no token was provided
    case authentication

    /// The URL components could not be assembled into a valid URL
    case componentsURL

    /// The request body could not be encoded
    case encoding(underlying: Error)

}

// MARK: - URLRequest Construction

/// Defines the steps required to construct a URLRequest from Interface parameters.
public protocol InterfaceConstructor {

    /// Builds a URLRequest using the provided parameters and configuration.
    static func buildRequest(
        requestParameters: RequestParameters,
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

    /// Encodes the body and returns data plus inferred content type.
    static func makeBody(
        _ body: RequestBody?
    ) throws(RequestError) -> (data: Data?, contentType: String?)

    /// Applies the encoded body to the request.
    static func applyBody(
        _ bodyResult: (data: Data?, contentType: String?),
        to request: inout URLRequest
    )

    /// Applies the inferred Content-Type header when appropriate.
    static func applyContentType(
        _ contentType: String?,
        to request: inout URLRequest
    )

}

// MARK: - Default InterfaceConstructor Implementation

public extension InterfaceConstructor {

    static func buildRequest(
        requestParameters: RequestParameters,
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

        let bodyResult = try makeBody(requestParameters.body)
        applyBody(bodyResult, to: &request)
        applyContentType(bodyResult.contentType, to: &request)

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
        components.path = path
    }

    static func applyQueryItems(
        _ queryItems: [String: String?]?,
        authentication: AuthenticationType,
        authToken: String?,
        to components: inout URLComponents
    ) throws(RequestError) {
        var currentQueryItems = components.queryItems ?? []

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

        let newQueryItems = queryItems?.map {
            URLQueryItem(
                name: $0.key,
                value: $0.value
            )
        }

        if let newQueryItems {
            currentQueryItems.append(contentsOf: newQueryItems)
        }

        components.queryItems = currentQueryItems
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
            currentHeaderFields.merge(
                newHeaderFields,
                uniquingKeysWith: { $1 }
            )
        }

        request.allHTTPHeaderFields = currentHeaderFields
    }

    static func makeBody(
        _ body: RequestBody?
    ) throws(RequestError) -> (data: Data?, contentType: String?) {
        guard let body else {
            return (data: nil, contentType: nil)
        }

        switch body {
        case .data(let data):
            return (data: data, contentType: nil)
        case .json(let encodable):
            do {
                let data = try JSONEncoder().encode(encodable)
                return (
                    data: data,
                    contentType: "application/json"
                )
            } catch {
                throw .encoding(underlying: error)
            }
        case .text(let text):
            let data = Data(text.utf8)
            let contentType = "text/plain; charset=utf-8"
            return (
                data: data,
                contentType: contentType
            )
        }
    }

    static func applyBody(
        _ bodyResult: (data: Data?, contentType: String?),
        to request: inout URLRequest
    ) {
        request.httpBody = bodyResult.data
    }

    static func applyContentType(
        _ contentType: String?,
        to request: inout URLRequest
    ) {
        guard let contentType else {
            return
        }

        var currentHeaderFields = request.allHTTPHeaderFields ?? [:]
        if currentHeaderFields["Content-Type"] == nil {
            currentHeaderFields["Content-Type"] = contentType
            request.allHTTPHeaderFields = currentHeaderFields
        }
    }

}
