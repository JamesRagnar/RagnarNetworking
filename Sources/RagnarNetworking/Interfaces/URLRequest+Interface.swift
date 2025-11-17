//
//  URLRequest+Interface.swift
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

}

// MARK: - URLRequest Construction

public extension URLRequest {
    
    init<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) throws (RequestError) {
        try self.init(
            requestParameters: parameters,
            serverConfiguration: configuration
        )
    }

    /// Constructs a URLRequest from Interface parameters and server configuration.
    ///
    /// This initializer builds a complete URLRequest by combining the base server configuration
    /// with request-specific parameters. It handles authentication, query parameters, headers,
    /// and body data according to the Interface specification.
    ///
    /// - Parameters:
    ///   - requestParameters: The Interface parameters defining the request
    ///   - serverConfiguration: The server configuration with base URL and auth token
    /// - Throws: `RequestError` if the request cannot be constructed
    init(
        requestParameters: RequestParameters,
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) {
        guard var components = URLComponents(
            url: serverConfiguration.url,
            resolvingAgainstBaseURL: false
        ) else {
            throw .configuration
        }

        // MARK: Path

        components.path = requestParameters.path

        // MARK: Query Items
        
        var currentQueryItems = components.queryItems ?? []
        
        if case .url = requestParameters.authentication {
            guard let token = serverConfiguration.authToken else {
                throw .authentication
            }
            
            currentQueryItems.append(
                URLQueryItem(
                    name: "token",
                    value: token
                )
            )
        }
        
        let newQueryItems = requestParameters.queryItems?.map {
            URLQueryItem(
                name: $0.key,
                value: $0.value
            )
        }
        
        if let newQueryItems {
            currentQueryItems.append(contentsOf: newQueryItems)
        }
        
        components.queryItems = currentQueryItems
        
        guard let url = components.url else {
            throw .componentsURL
        }

        var request = URLRequest(url: url)
        
        // MARK: Method
        
        request.httpMethod = requestParameters.method.rawValue
        
        // MARK: Headers
        
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        var currentHeaderFields = request.allHTTPHeaderFields ?? [:]
        
        if case .bearer = requestParameters.authentication {
            guard let token = serverConfiguration.authToken else {
                throw .authentication
            }
            
            currentHeaderFields["Authorization"] = "Bearer \(token)"
        }
        
        if let newHeaderFields = requestParameters.headers {
            currentHeaderFields.merge(
                newHeaderFields,
                uniquingKeysWith: { $1 }
            )
        }
        
        request.allHTTPHeaderFields = currentHeaderFields
        
        // MARK: Body
        
        if let body = requestParameters.body {
            request.httpBody = body
        }
        
        self = request
    }

}
