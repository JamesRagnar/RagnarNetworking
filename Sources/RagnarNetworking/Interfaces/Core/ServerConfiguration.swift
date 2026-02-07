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
public struct ServerConfiguration: Sendable {

    /// The base URL for all API requests (e.g., "https://api.example.com")
    let url: URL

    /// Optional authentication token to be included in requests that require it
    let authToken: String?

    /// Encoder configuration for request bodies. Uses a factory pattern
    /// to maintain Sendable conformance in Swift 6.
    let requestEncoder: RequestEncoder

    /// Creates a server configuration with the specified base URL and optional auth token.
    /// - Parameters:
    ///   - url: The base URL for the API server
    ///   - authToken: Optional authentication token; required if any requests use bearer or URL authentication
    ///   - requestEncoder: Encoder configuration for request bodies
    public init(
        url: URL,
        authToken: String? = nil,
        requestEncoder: RequestEncoder = RequestEncoder()
    ) {
        self.url = url
        self.authToken = authToken
        self.requestEncoder = requestEncoder
    }

}
