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

    /// The request requires authentication but no token was provided
    case authentication

    /// The URL components could not be assembled into a valid URL
    case componentsURL

    /// The request body could not be encoded
    case encoding(underlying: ErrorSnapshot)

    /// The request could not be constructed due to invalid parameters.
    case invalidRequest(description: String)

    public var errorDescription: String? {
        switch self {
        case .configuration:
            return "The server configuration could not be parsed or is malformed."

        case .authentication:
            return "This request requires authentication, but no token was provided."

        case .componentsURL:
            return "The request URL could not be assembled from its components."

        case .encoding(let underlying):
            return "The request body could not be encoded: \(underlying.description)"

        case .invalidRequest(let description):
            return "The request could not be constructed: \(description)"
        }
    }

}
