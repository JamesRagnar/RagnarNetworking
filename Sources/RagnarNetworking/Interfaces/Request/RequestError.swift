//
//  RequestError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Errors that can occur during URLRequest construction.
public enum RequestError: LocalizedError, Sendable {

    /// The server configuration could not be parsed or is malformed
    case configuration

    /// The URL components could not be assembled into a valid URL
    case componentsURL

    /// The request body could not be encoded
    case encoding(underlying: ErrorSnapshot)

    /// The request could not be constructed due to invalid parameters.
    case invalidRequest(description: String)

    /// The request declared a scheme with no authenticator registered for it on the
    /// configuration.
    case unregisteredScheme(AuthenticationScheme)

    /// The request declared a scheme with a registered authenticator, but no credential was
    /// available for it.
    case missingCredential(AuthenticationScheme)

    /// The authenticator's credential would have overwritten a header field or query item the
    /// request already carried.
    ///
    /// Two sources claim one slot: a caller-supplied `Authorization` header alongside a header
    /// scheme, or a base URL with the credential's query item already baked in. Neither one
    /// silently wins.
    case credentialCollision(scheme: AuthenticationScheme, name: String)

    /// The authenticator returned a query item whose name it does not declare in
    /// `redactedQueryItemNames`.
    ///
    /// A credential written under a name the response side does not know to redact would leak
    /// into any captured `HTTPResponseSnapshot`.
    case undeclaredQueryItemName(scheme: AuthenticationScheme, name: String)

    /// The registered authenticator contributed neither a header field nor a query item, so the
    /// request would have gone out unauthenticated despite declaring a scheme.
    case authenticatorAppliedNothing(AuthenticationScheme)

    public var errorDescription: String? {
        switch self {
        case .configuration:
            return "The server configuration could not be parsed or is malformed."

        case .componentsURL:
            return "The request URL could not be assembled from its components."

        case .encoding(let underlying):
            return "The request body could not be encoded: \(underlying.description)"

        case .invalidRequest(let description):
            return "The request could not be constructed: \(description)"

        case .unregisteredScheme(let scheme):
            return "No authenticator is registered for the '\(scheme)' authentication scheme."

        case .missingCredential(let scheme):
            return "The '\(scheme)' authentication scheme requires a credential, but none was provided."

        case .credentialCollision(let scheme, let name):
            return """
            The '\(scheme)' authentication scheme writes '\(name)', which this request already \
            carries. Remove one of them.
            """

        case .undeclaredQueryItemName(let scheme, let name):
            return """
            The authenticator for the '\(scheme)' scheme wrote the query item '\(name)' without \
            declaring it in redactedQueryItemNames, so it would leak into captured errors.
            """

        case .authenticatorAppliedNothing(let scheme):
            return """
            The authenticator for the '\(scheme)' scheme applied no credential, so the request \
            would have been sent unauthenticated.
            """
        }
    }

}
