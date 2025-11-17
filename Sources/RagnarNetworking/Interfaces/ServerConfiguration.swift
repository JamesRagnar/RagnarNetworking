//
//  ServerConfiguration.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// Encapsulates the base configuration for connecting to a server.
///
/// This configuration provides the base URL and optional authentication token that will be
/// used across all requests made to the server. The token is automatically applied to requests
/// based on their `AuthenticationType` (bearer or URL parameter).
public struct ServerConfiguration {

    /// The base URL for all API requests (e.g., "https://api.example.com")
    let url: URL

    /// Optional authentication token to be included in requests that require it
    let authToken: String?

    /// Creates a server configuration with the specified base URL and optional auth token.
    /// - Parameters:
    ///   - url: The base URL for the API server
    ///   - authToken: Optional authentication token; required if any requests use bearer or URL authentication
    public init(
        url: URL,
        authToken: String? = nil
    ) {
        self.url = url
        self.authToken = authToken
    }

}

extension ServerConfiguration: Sendable {}
