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
    /// This is a type-safe wrapper around the `InterfaceRequest` initializer.
    ///
    /// - Parameters:
    ///   - interface: The interface type (used for type inference)
    ///   - request: The request shape defining how to construct the network request
    ///   - context: The server configuration and credential for this request. The
    ///     configuration's `builder` constructs the request.
    /// - Throws: `RequestError` if the request cannot be constructed
    init<T: Interface>(
        _ interface: T.Type,
        _ request: T.Request,
        context: RequestContext
    ) throws(RequestError) {
        try self.init(
            interfaceRequest: request,
            context: context
        )
    }

    /// Constructs a URLRequest from an Interface request and a request context.
    ///
    /// Two steps, in this order: the configuration's `builder` produces an unauthenticated
    /// request from the interface request, then the `Authenticator` registered for the
    /// request's declared scheme applies the credential to it.
    ///
    /// - Parameters:
    ///   - interfaceRequest: The request shape defining how to construct the network request
    ///   - context: The server configuration and credential for this request. The
    ///     configuration's `builder` constructs the request; set
    ///     `ServerConfiguration.builder` to change how.
    /// - Throws: `RequestError` if the request cannot be constructed or the credential cannot
    ///   be applied
    init<Request: InterfaceRequest>(
        interfaceRequest: Request,
        context: RequestContext
    ) throws(RequestError) {
        self = try context.builder.buildRequest(
            interfaceRequest,
            context: context
        )

        try applyAuthentication(
            interfaceRequest.authentication,
            context: context
        )
    }

}
