//
//  RequestParameters.swift
//  RagnarNetworking
//
//  Created by James Harquail on 2024-11-18.
//

import Foundation

/// Defines the components needed to construct an HTTP request.
///
/// Implement this protocol to specify all the details of your network request, including
/// the HTTP method, path, query parameters, headers, body, and authentication requirements.
/// This protocol is typically implemented as a nested type within an `Interface` conformance.
public protocol RequestParameters: Sendable {

    /// The HTTP method for this request (GET, POST, etc.)
    var method: RequestMethod { get }

    /// The path component of the URL (e.g., "/api/users/123")
    var path: String { get }

    /// Optional query parameters to append to the URL
    var queryItems: [String: String]? { get }

    /// Optional HTTP headers to include in the request
    var headers: [String: String]? { get }

    /// Optional request body data (typically JSON-encoded)
    var body: Data? { get }

    /// The authentication strategy for this request
    var authentication: AuthenticationType { get }

}

// MARK: - Authentication Type

/// Specifies how authentication credentials should be included in a request.
public enum AuthenticationType: Sendable {

    /// No authentication required for this request
    case none

    /// Authentication token included in request headers as `Authorization: Bearer <token>`
    case bearer

    /// Authentication token included in query parameters as `?token=<token>`
    case url

}

// MARK: - Request Method

/// Standard HTTP request methods.
public enum RequestMethod: String, Sendable {

    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case head = "HEAD"
    case delete = "DELETE"
    case patch = "PATCH"
    case options = "OPTIONS"
    case connect = "CONNECT"
    case trace = "TRACE"

}
