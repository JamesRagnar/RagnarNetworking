//
//  RequestContext.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-07-31.
//

import Foundation

/// A `ServerConfiguration` paired with the credential to use for a single request.
///
/// `APIClient` holds one configuration for its lifetime and builds a context with the current
/// credential on each send. Construct one directly when calling `RequestPipeline` or
/// `URLRequest`'s initializers without an `APIClient`.
public struct RequestContext: Sendable {

    /// How the server is spoken to.
    public let configuration: ServerConfiguration

    /// The credential for a request that declares an `AuthenticationScheme`.
    ///
    /// A bearer token, a signing key, a pre-encoded basic-auth pair; what it means is the
    /// registered `Authenticator`'s business. A request declaring a scheme with no credential
    /// fails with `RequestError.missingCredential`.
    public let credential: String?

    /// Creates a request context.
    /// - Parameters:
    ///   - configuration: How the server is spoken to
    ///   - credential: The credential for this request; required by any declared scheme
    public init(
        configuration: ServerConfiguration,
        credential: String? = nil
    ) {
        self.configuration = configuration
        self.credential = credential
    }

    /// The base URL for the request.
    public var url: URL { configuration.url }

    /// Encoder configuration for the request body.
    public var requestEncoder: RequestEncoder { configuration.requestEncoder }

    /// Decoder configuration for the response body.
    public var responseDecoder: ResponseDecoder { configuration.responseDecoder }

    /// The builder that constructs this request.
    public var builder: any RequestBuilder { configuration.builder }

    /// The handler for this response, unless the Interface overrides it.
    public var responseHandler: any ResponseHandler { configuration.responseHandler }

    /// Configuration for handling this request's response.
    public var responseContext: ResponseContext { configuration.responseContext }

    /// The authenticator for `scheme`, or `nil` when the request declares no scheme.
    ///
    /// - Throws: `RequestError.unregisteredScheme` for a declared scheme with no authenticator.
    public func authenticator(
        for scheme: AuthenticationScheme?
    ) throws(RequestError) -> (any Authenticator)? {
        try configuration.authenticator(for: scheme)
    }

    /// The configuration's `defaultHeaders` overlaid with the request's own headers.
    public func resolvedHeaders(for parameters: some RequestParameters) -> [String: String] {
        configuration.resolvedHeaders(for: parameters)
    }

}
