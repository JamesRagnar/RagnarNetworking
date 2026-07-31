//
//  RequestContext.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// A `ServerConfiguration` paired with the credential to use for a single request.
///
/// Splitting the credential out of `ServerConfiguration` keeps lifetime-stable policy
/// separate from volatile per-request state: `APIClient` holds one configuration for its
/// lifetime and pairs it with whatever token is current each time it sends.
public struct RequestContext: Sendable {

    /// How the server is spoken to.
    public let configuration: ServerConfiguration

    /// The token to apply to requests whose `AuthenticationType` is `.bearer` or `.url`.
    /// `nil` for unauthenticated flows; those requests fail with `RequestError.authentication`.
    public let authToken: String?

    /// Creates a request context.
    /// - Parameters:
    ///   - configuration: How the server is spoken to
    ///   - authToken: The token for this request; required if the request uses bearer or URL authentication
    public init(
        configuration: ServerConfiguration,
        authToken: String? = nil
    ) {
        self.configuration = configuration
        self.authToken = authToken
    }

    /// The base URL for the request.
    public var url: URL { configuration.url }

    /// Encoder configuration for the request body.
    public var requestEncoder: RequestEncoder { configuration.requestEncoder }

    /// Decoder configuration for the response body.
    public var responseDecoder: ResponseDecoder { configuration.responseDecoder }

    /// The configuration's `defaultHeaders` overlaid with the request's own headers.
    public func resolvedHeaders(for parameters: some RequestParameters) -> [String: String] {
        configuration.resolvedHeaders(for: parameters)
    }

}
