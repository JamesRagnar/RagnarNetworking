//
//  URLRequest+RequestBuilder.swift
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
    ///   - context: The server configuration and credential for this request. The
    ///     configuration's `builder` constructs the request.
    /// - Throws: `RequestError` if the request cannot be constructed
    init<T: Interface>(
        _ interface: T.Type,
        _ parameters: T.Parameters,
        context: RequestContext
    ) throws(RequestError) {
        try self.init(
            requestParameters: parameters,
            context: context
        )
    }

    /// Constructs a URLRequest from Interface parameters and a request context.
    ///
    /// Two steps, in this order: the configuration's `builder` produces an unauthenticated
    /// request from the parameters, then the `Authenticator` registered for the request's
    /// declared scheme applies the credential to it.
    ///
    /// - Parameters:
    ///   - requestParameters: The Interface parameters defining the request
    ///   - context: The server configuration and credential for this request. The
    ///     configuration's `builder` constructs the request; set
    ///     `ServerConfiguration.builder` to change how.
    /// - Throws: `RequestError` if the request cannot be constructed or the credential cannot
    ///   be applied
    init<Parameters: RequestParameters>(
        requestParameters: Parameters,
        context: RequestContext
    ) throws(RequestError) {
        self = try context.builder.buildRequest(
            requestParameters,
            context: context
        )

        try applyAuthentication(
            requestParameters.authentication,
            context: context
        )
    }

}
