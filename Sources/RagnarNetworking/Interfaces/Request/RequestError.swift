//
//  RequestError.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2026-02-06.
//

import Foundation

/// Errors that can occur during URLRequest construction.
public enum RequestError: Error, Sendable {

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

}
