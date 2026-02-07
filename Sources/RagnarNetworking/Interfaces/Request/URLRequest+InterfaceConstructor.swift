//
//  URLRequest+InterfaceConstructor.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-03.
//

import Foundation

public extension URLRequest {

    /// Convenience initializer that constructs a URLRequest from an Interface type.
    ///
    /// This is a type-safe wrapper around the `RequestParameters` initializer.
    ///
    /// - Parameters:
    ///   - interface: The interface type (used for type inference)
    ///   - parameters: The Interface parameters defining the request
    ///   - configuration: The server configuration with base URL and auth token
    /// - Throws: `RequestError` if the request cannot be constructed
    init<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        _ configuration: ServerConfiguration
    ) throws(RequestError) {
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
    init<Parameters: RequestParameters>(
        requestParameters: Parameters,
        serverConfiguration: ServerConfiguration
    ) throws(RequestError) {
        self = try Self.buildRequest(
            requestParameters: requestParameters,
            serverConfiguration: serverConfiguration
        )
    }

}

extension URLRequest: InterfaceConstructor {}
